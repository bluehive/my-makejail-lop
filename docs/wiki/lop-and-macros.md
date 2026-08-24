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

## 関連

- [Overview](Overview) — makejail の LOP 実践  
- [creating-languages-in-racket](creating-languages-in-racket) — Flatt / ACM Queue  
- [P02 エージェント契約](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)  
- [Beautiful Racket: Introduction](https://beautifulracket.com/introduction.html)  
