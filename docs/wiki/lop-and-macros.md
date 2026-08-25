# LOP とマクロ — `#lang makejail` の見方

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 関連: [Overview](Overview) · [creating-languages-in-racket](creating-languages-in-racket) · [Issue #4](https://github.com/bluehive/my-makejail-lop/issues/4)

LOP ではマクロは「便利関数」ではなく、**コンパイラに語彙を足す手続き**です。`#lang makejail` が目指しているのもそれです。ライブラリを `require` して呼ぶのではなく、**ファイル先頭の言語指定そのもの**が、書ける形と書けない形を決めます。

---

## 1. LOP から見たマクロ

Racket のモジュールは、実行時の値だけでなく **構文（マクロ）も export** します。`#lang makejail` は `lang/reader.rkt` が `makejail` モジュールを言語として読み、`mj-module-begin` が通常の `#%module-begin` を置き換えます。

```
ソースの (name …) (from …) (pkg …)
        ↓  マクロ / トップレベル束縛（コンパイル時〜モジュール展開）
prefab AST（mj-plan / mj-step …）
        ↓  実行時関数
効果列 → plan / --dry-run / --apply
```

### ポイントは3つ

1. **表記を狭める**  
   エージェントに渡すのは「jail を書く語彙」だけ。`define` や任意の `system` を言語から出さなければ、書けるものが言語の受理集合になります。

2. **コンパイル時に形を決める**  
   マクロは「展開後の Racket」を返す関数です。ここで引数の形（文字列か識別子か）、必須の `(from …)`、二重定義などを落とせます。実行してから気づく検査ではありません。

3. **実行器と切り離す**  
   マクロの仕事は AST まで。`zfs clone` や `pkg install` は `plan->effects` 側です。失敗時ロールバックなし、という実行方針はマクロの外に置けます。

Flatt の階段で言うと、マクロは「構文抽象」から「モジュール言語」へ上がる段です。`#lang` にした瞬間、それはパッケージではなく **そのファイルの言語** になります（[creating-languages-in-racket](creating-languages-in-racket)）。

---

## 2. 現状の `main.rkt` — 全部がマクロではない

| 層 | 実体 | 例 |
|----|------|-----|
| 言語の入口 | マクロ | `mj-module-begin`、`name`、`from`、`arg`、`option`、`service` |
| 見た目は語彙、中身は関数 | 実行時に `mj-step` を返す | `pkg`、`copy`、`sysrc`、`volume`、`wiki-site`、`pw-*` |
| 実行 | 関数 | `assemble-plan`、`plan-validate!`、`plan->effects` |

LOP として効くのは「**表面が語彙に見えること**」です。

ただし **関数のまま残した語彙**は、呼び出し規約以外の静的検査が弱い。`(cmd …)` が関数である限り、エージェントは「呼べる手続き」を持ってしまいます。語彙を閉じるなら:

- 禁止したい形は **マクロ側で reject** する、または  
- 言語の **`provide` から外す**  

のが本筋です（P02: agent モードで `cmd` を実行時拒否するのは暫定。理想は provide 分離や `#lang makejail/agent`）。

`wiki-site` のようなドメイン語彙は、マクロでも関数でも「効果列に展開する」点は同じです。差は **書けるタイミングとエラーの出る段** です。

- マクロ → 展開時  
- 関数 → `assemble-plan` / `plan-validate!` 時  

エージェント権限を「DSL 記述だけ」にするなら、閉じたい規則はできるだけ **マクロ（または `#%module-begin`）** に寄せます。

---

## 3. 構文（Syntax / Macros）— 言語側の道具

これはライブラリ API ではなく、**コンパイラをプログラムする構文**です。

### 定義

| 形 | 意味 |
|----|------|
| `define-syntax` | 識別子をマクロにする。右辺は「構文オブジェクト → 構文オブジェクト」の変換器。makejail の `(define-syntax (from stx) …)` がこれ |
| `define-simple-macro` | `syntax-parse` 前提の短い定義。パターンとテンプレートだけ書くとき。`define-syntax-rule` よりパターンが細かい |
| `begin-for-syntax` | コンパイル時だけ存在する定義。構文クラスや、展開中に使う表 |
| `define-for-syntax` | そのコンパイル時世界の関数・値。展開器から呼ばれる補助 |

### テンプレート

| 形 | 意味 |
|----|------|
| `syntax`（`#'`） | コード断片を「値」ではなく **構文オブジェクト** にする。展開結果はこれで返す |
| `syntax/loc` | 同じだが、エラー位置を指定の構文に貼る。DSL の `(from …)` の行番号を残す |
| `with-syntax` | テンプレートに穴を開ける。パターンから取り出した部品を `#'(mj-from …)` に埋め込む |

### 構文の解析

| 形 | 意味 |
|----|------|
| `syntax-parse` | マクロ引数のパターンマッチ。`n:str`、`name:id`、`default-expr:expr` のように **構文の種類** で切る。`from` が `kind:id` と `ref:str` を分けるのがこれ |
| `define-syntax-class` | 繰り返し使うパターンに名前を付ける。例: jail 名、ZFS dataset、パッケージ名リスト。語彙が増えたらクラス化 |
| `pattern` | 構文クラス内の1パターン。任意個の `...`、キーワード引数などもここで書く |

### 構文オブジェクト

マクロが触るのは文字列ではなく、**ソース位置付きの木**です。

- `syntax-source` … どのファイルか  
- `syntax-line` … 何行目か  

エラーを「展開後の `mj-option`」ではなく「利用者が書いた `(name …)`」に指すために必要です。独自 reader をまだ持たない今でも、S 式の位置情報はここに載っています。

`#%module-begin` の置き換えは、これらの上に乗る **モジュール全体のマクロ** です。`mj-module-begin` がフォーム列を `assemble-plan` に渡し、`current-plan` だけを残す。これが「**ファイル全体が1つの jail 計画である**」という言語規則です。

---

## 4. Classes — LOP の表面には出さない層

Racket の `class` も言語機能です（歴史的にはマクロで載っている）。ただし **makejail の受理集合を `class` で作る必要はありません**。計画は prefab 構造体で十分で、オブジェクトのアイデンティティや継承は jail 量産の問題と直交します。

### 簡易対応表

**定義**

| 形 | 意味 |
|----|------|
| `interface` | メソッド名の集合。実装側がこれを満たす契約 |
| `class*` | 親クラスとインタフェースを指定してクラスを定義する本命。`class` はその省略形 |

**生成**

| 形 | 意味 |
|----|------|
| `make-object` | 位置引数でインスタンスを作る古い形 |
| `new` | キーワード初期化が自然。`(new foo% [x 1])` |
| `instantiate` | 位置引数とキーワードを混ぜる |

**メソッド**

| 形 | 意味 |
|----|------|
| `send` | 1つのメソッド呼び出し |
| `send/apply` / `send/keyword-apply` | 引数リスト／キーワードリストを実行時に渡す |
| `send*` | 同じオブジェクトに連続 `send` |
| `send+` | チェーン（戻り値のオブジェクトに続けて送る） |

**フィールド**

| 形 | 意味 |
|----|------|
| `get-field` / `set-field!` | 公開フィールドの読み書き。jail 計画の `mj-option` をこれにすると、検査が実行時に落ちやすい |

**合成**

| 形 | 意味 |
|----|------|
| `mixin` | クラス → クラスの関数。機能を後付けする |
| `trait` / `trait-sum` / `trait-exclude` / `trait-rename` | メソッド集合の代数。足す・除く・改名してから class に落とす |

**契約**

| 形 | 意味 |
|----|------|
| `class/c` | クラスそのものの契約 |
| `instanceof/c` / `is-a?/c` | 値がそのクラス／インタフェースか |
| `implementation?/c` / `subclass?/c` | 実装関係・継承関係 |

### LOP 的な使い分け

| 関心 | 手段 |
|------|------|
| 構文の形・必須項目・禁止語彙 | **マクロ**（`syntax-parse`、`#%module-begin`） |
| 計画の値 | **prefab / struct**（`mj-plan`） |
| 実行器の内部状態（接続、ログ、進捗） | 必要なら **class**。表面 DSL には出さない |
| エージェントに渡すもの | class でも汎用関数でもなく、**閉じた `#lang` のフォームだけ** |

HtDP は設計の考え方の本で、上の表そのものの仕様書ではありません。`class` / マクロの規範的な意味は **Racket の言語リファレンス**側です。著作権のある本文はここでは引き写しません。

---

## 5. makejail に落とすと

今の平坦構文でマクロが担うべき仕事は、だいたいこの4つです。

1. `(from …)` はちょうど1回、`thin` か `zfs` だけ  
2. `(arg name)` は必須束縛。欠けるなら展開または組み立て時に落ちる  
3. エージェント向け言語から `(cmd)` を **provide しない**  
4. 量産なら `(option network host)` を **言語側で拒否**する  

`wiki-site` をマクロにすると、hostname / data volume / 禁止パスが **語彙** になります。関数のままでも展開はできますが、エージェントから見ると「引数付き手続き」です。方針が「DSL の記述権だけ」なら、閉じたいものはマクロか、もっと狭い **`#lang makejail/agent`** に切り出す方が一貫します。

独自表面構文（非 S 式）はまだ reader 段階です。今の `lang/reader.rkt` は S 式のまま `makejail` を言語にするだけなので、マクロ説明の中心は **S 式の形をドメインの文にする** ところにあります。

---

## 6. 3点の深掘り — 「マクロで何を閉じるか」

3点は「マクロで何を閉じるか」の話です。ライブラリの便利さではなく、**そのファイルで何が合法な文かを言語が決める**、という見方です。

### 6.1 表記を狭める

エージェントに渡すのは「jail を書く語彙」だけ、という意味です。

Racket ではモジュールが **export したもの**が、その言語の語彙になります。`#lang makejail` は `main.rkt` が `provide` した識別子だけがトップレベルに現れます。

| | |
|--|--|
| **provide にあるもの** → 書ける | 例: `name` `from` `pkg` `volume` `wiki-site` |
| **provide にないもの** → その言語では存在しない | 例: 利用者ファイルでの `define`、`system`、`open-output-file`、任意の `require` |

**受理集合**（この言語で合法なプログラムの集合）は、export した語彙の組み合わせです。

- 関数ライブラリだと「呼んではいけない関数」をドキュメントや実行時チェックで抑えることになります。
- `#lang` にすると、そもそも名前が束縛されていないので、**書けません**。

エージェント権限を「DSL の記述だけ」にする、という方針はここに対応します。実行器やシェルへの逃げ道を語彙から外すほど、受理集合が狭くなります。

### 6.2 コンパイル時に形を決める

マクロは実行時の関数ではなく、**展開時に動く変換器**です。入力も出力も構文オブジェクト（ソース位置付きの木）です。

`main.rkt` の例:

```racket
(define-syntax (from stx)
  (syntax-parse stx
    [(_ kind:id ref:str)
     #'(mj-from (normalize-from-kind 'kind) ref)]
    ...))
```

`(from zfs "zroot/jails/base@clean")` を読むと、マクロが次を決めます。

- 第1引数は識別子か文字列か
- `kind` は `thin` / `zfs` に正規化できるか
- 展開結果は `mj-from` という prefab を作る式になる

ここで落ちるエラーは **プログラムを走らせる前** です。`pkg install` が失敗した、という実行時エラーではありません。

同じく `mj-module-begin` がモジュール全体を受け取り、フォーム列を `assemble-plan` に渡します。二重の `(from …)` や「対応しないトップレベル」は、組み立ての段階で拒否できます。必須の `(arg …)` が無い、といった規則も、展開〜組み立てに寄せれば「実行してから」ではなく「**言語が受理しない**」になります。

| | マクロ側 | 実行時関数側 |
|--|----------|----------------|
| いつ動くか | 展開時（コンパイル／モジュール読込） | `plan->effects` や `--apply` 時 |
| 典型的な誤り | 形が違う、語が無い、必須が無い | ZFS が無い、pkg が無い |
| エージェント向け | **受理集合を切る** | もう計画が出来た後 |

### 6.3 実行器と切り離す

**マクロの仕事は AST まで** です。

パイプラインはこう分かれます。

```
ソースの語彙
  → マクロ／トップレベル束縛（形の検査・内部表現）
  → mj-plan（prefab AST）
  → plan->effects（効果列）
  → dry-run または --apply
```

- `zfs clone` や `pkg install` は `plan->effects` / executor の仕事
- 「失敗したらロールバックしない」も **実行方針** であり、マクロの意味ではない
- SSH で運ぶのも AST（または効果列）であり、展開済みのシェル脚本をエージェントに書かせる話ではない

マクロが実行コマンドを直接叩くと、dry-run と検査が黒箱になります。言語側は「何をする計画か」を木にし、実行器は「その木をどう適用するか」だけを担当する、という分離です。

### 6.4 Flatt の階段との対応

Matthew Flatt の説明では、言語を育てる段がだいたい次の順です。

1. 普通の Racket（struct と手続き）
2. **構文抽象** … マクロで繰り返しを短くする
3. **構文拡張** … マクロをモジュールで配る
4. **モジュール言語** … `#lang` でファイル全体の言語にする
5. **静的チェック** … `begin-for-syntax` などで展開時検査を厚くする
6. 独自表面構文 … reader
7. IDE

マクロは 2 から効き始め、`#lang` にした瞬間に **4** です。`require` して関数を呼ぶパッケージではなく、**そのファイルの言語** になります。`lang/reader.rkt` が `makejail` を指し、`#%module-begin` を `mj-module-begin` に差し替えているのがその段です。

→ 詳細: [creating-languages-in-racket](creating-languages-in-racket)

### 6.5 「現状の main.rkt では全部がマクロではない」

見た目はどれも「語彙」ですが、実装は二層です。

**マクロ（展開時に形を触る）**

- `arg` `from` `option` `name` `service`
- `mj-module-begin` `mj-top-interaction`

**実行時関数（呼ばれると `mj-step` などを返す）**

- `pkg` `copy` `sysrc` `volume` `mount` `workdir`
- `wiki-site` `pw-user` `smb-password` `template-subst`
- および `cmd` / `human-cmd`

関数の語彙でも、モジュール本文に並べれば `assemble-plan` が集めます。ただし次の差があります。

| | |
|--|--|
| **マクロ** | 引数の構文クラス（`id` / `str`）や「引数を取らない」などを **展開時** に拒否できる |
| **関数** | 呼び出し規約は通常の Racket。間違った引数は実行時（または `plan-validate!`）まで残りやすい |

だから LOP として「閉じたい」ものほどマクロ（または `provide` から外す）に寄せます。例えばエージェント向けに `(cmd …)` を許したくないなら、

1. `provide` から外す（表記から消す）
2. マクロの `#%module-begin` / `plan-validate!` で拒否する

のどちらも「言語の規則」です。実行器に「cmd は無視」と書くだけだと、**受理集合はまだ広い**です。

### 6.6 一文でまとめると

| 観点 | 意味 |
|------|------|
| **表記を狭める** | export しないものは言語に存在しない |
| **コンパイル時に形を決める** | マクロが受理集合を切る |
| **実行器と切り離す** | マクロは AST まで、副作用は `plan->effects` 以降 |

`#lang` はパッケージの薄いラッパではなく、**そのファイルで何が文かを定義する装置**です。`main.rkt` の関数語彙は便利ですが、狭めと静的検査の本丸は **マクロと provide の境界** にあります。


---

## 関連

- [Overview](Overview) — makejail の LOP 実践  
- [creating-languages-in-racket](creating-languages-in-racket) — Flatt / ACM Queue  
- [P02 エージェント契約](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)  
- [Beautiful Racket: Introduction](https://beautifulracket.com/introduction.html)  

- [stack-calc](stack-calc) — #lang スタック計算機

- [beautiful-racket-stacker](beautiful-racket-stacker)

- [dsl-testing](dsl-testing) — DSL テスト四層

---

## 0.4 追記（Issue #9）

makejail の変更軸は **個体・種族・運用** に固定する（[three-axes-isomorphism](three-axes-isomorphism)）。  
展開は言語側。**`(host)/(in-jail)` は DSL 表面のルールにしない**（jail 個体計画であることが自明の前提）。  
マクロで閉じる対象は、まず **運用の禁止（cmd、host ネット量産）** と **必須個体スロット**、種族の単一入口である。

- [dsl-design-principles](dsl-design-principles)
