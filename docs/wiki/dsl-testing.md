# DSL のテスト — 構文・展開・意味・拒否の四層

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 関連: [lop-and-macros](lop-and-macros) · [three-axes-isomorphism](three-axes-isomorphism) · [Issue #9](https://github.com/bluehive/my-makejail-lop/issues/9) · [Issue #8](https://github.com/bluehive/my-makejail-lop/issues/8)（アーカイブ） · [stack-calc](stack-calc) · [P02](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)

DSL のテストは「ライブラリーの単体」ではなく、**構文・展開（静的意味）・意味・拒否**の四層で見ます。  
Racket `#lang` 側の定石を、makejail / stack-calc に寄せて整理します。

---

## 導入

DSL のテストは関数の単体ではない。**言語が受理するもの・拒否するもの・意味するもの**を、パイプラインの段ごとに固定する作業である。

ライブラリーの `check-equal?` を語彙に足しても、言語のテストにはならない。

産業側の整理（mbeddr / Spoofax SPT）と Racket `#lang` の定石は、**層がほぼ一致**する。

---

## 何をテスト対象にするか

言語は部品なので、テストも **部品の境界**に置く。  
`#lang L` のファイルが入力、その言語が約束する **観測**が出力である。

| 言語 | 言語の仕事（観測） | 言語の外 |
|------|-------------------|----------|
| **makejail** | 効果列まで | `jexec` / 実 OS（実行器） |
| **stack-calc** | 最終スタック（や print） | — |

実行器や OS を単体の期待値にすると、言語の回帰がホストの都合に溶ける。

### 層は四つ。混ぜない。

| 層 | 問うこと | 観測 |
|----|----------|------|
| **構文** | このプログラムは言語に入るか | 読める / `exn:fail:syntax` |
| **静的意味** | 入ったあと、軸は揃っているか | AST・必須スロット・段階 |
| **動的意味** | 正規形の意味はこれか | 効果列・スタック・値 |
| **拒否の言葉** | 失敗はドメイン語か | エラー文・位置 |

Kats らの SPT が「言語定義の TDD」を可能にしたのは、テスト本文が **被試験言語の断片**だからである。  
Racket でも同じで、テストの正本は `#lang makejail` / `#lang s-exp "stack-calc.rkt"` のプログラムであり、`jail-api.rkt` の関数呼び出しではない。

---

## 1. 構文：受理と拒否を対にする

正例だけ書くと、言語は広がり続ける。**拒否のテストが表面を固定する。**

### stack-calc の対

```racket
;; 受理
#lang s-exp "stack-calc.rkt"
3 4 +
```

```racket
;; 拒否（別ファイル）
#lang s-exp "stack-calc.rkt"
(+ 1 2)          ; 適用はない
;; "hi"          ; 数字以外のリテラルはない
;; foo           ; 未知の語
```

Racket ではコンパイル時エラーを値にするために、テスト側を普通の `#lang racket` にしてモジュールを動的に読む。

```racket
#lang racket
(require rackunit)
(define (load-as L src)
  (parameterize ([read-accept-reader #t])
    (define p (open-input-string (~a "#lang " L "\n" src)))
    (read-syntax 'test p)))

(check-exn
 exn:fail:syntax?
 (λ ()
   (expand (load-as "s-exp \"stack-calc.rkt\"" "(+ 1 2)\n"))))
```

実務では文字列埋め込みより、小さな `.rkt` を **fixtures** にして `dynamic-require` する方が位置情報が残る。  
Beautiful Racket の jsonic がパーサ試験を別ファイルに切ったのは、`#lang brag` 側に `module+ test` が無いからで、言語本体が `#lang` ならそれが普通である。

### 正例・負例の比

語彙が狭い DSL ほど **負例を厚く**する。makejail 量産面なら少なくとも:

- `(cmd)` が書けない  
- host ネットの量産が書けない  
- `(arg hostname)` 欠落が展開前に落ちる  
- build 外の `pkg` が段階エラーになる（段階マクロ導入後）  

これらは「実行したら失敗する」ではなく「**言語に入らない**」。  
**エージェント権限の境界そのものがテスト**である（[P02](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)）。

---

## 2. 静的意味：正規形をゴールデンにする

構文が通ったあと、同じ要求が同じ AST / 効果列になるかを固定する。  
ここが [Issue #8](https://github.com/bluehive/my-makejail-lop/issues/8) の **同型**の検査点である。

```racket
#lang racket
(require rackunit makejail) ; plan 取得 API はプロジェクトに合わせる

(check-equal?
 (plan-effects-of "examples/wiki-03.rkt") ; 例: 効果列 or prefab 正規形
 expected-normalized-effects)
```

### ポイント

- **ソース文字列ではなく正規形を比較する**  
- 空白やキーワード順を期待値にすると、同型を測るつもりで整形を測ることになる  
- prefab AST と効果列は、そのためにパイプラインが切ってある  

Spoofax 流に書くと、静的試験は「この断片は succeeds / この箇所に `$error`」である。  
Turnstile なら型付き言語に対して試験言語が先にある。

```racket
(check-type (λ ([x : Int]) x) : (→ Int Int))
(typecheck-fail (+ 1 #t))
```

makejail に型は無くてよい。代わりに:

- スロットが埋まっている  
- 段階が守られている  
- フリート一意性  

が型の役割を果たす。検査関数を実行器に置かず、`#%module-begin` の出口で AST に対して走らせ、その失敗を **構文エラー**にする。テストは `check-exn` でそのエラーを掴む。

### ゴールデンが腐るのを防ぐ

期待値を手で増やすより、**種族テンプレに対する差分だけ**を期待する。

- 種族 dokuwiki の効果列は固定フィクスチャ  
- 個体ファイルは「種族 + 名前/volume/IP の上書き」だけが差  

`check-equal?` の右辺に個体パラメータ以外が出てきたら、**言語が漏れている**。

---

## 3. 動的意味：効果の解釈を言語から切り離して試す

動的試験は二段に分ける。

### 言語内の意味

- **stack-calc** … モジュールを `dynamic-require` し、終了時スタック（または print）を見る  
- recspecs の `expect` は出力ゴールデンに向く  

### 効果の解釈器

- **makejail** … `--dry-run` が本試験。`--apply` は少数の契約試験に落とす  
- dry-run が効果列をテキスト化するなら、**そのテキストではなく効果列そのもの**を比較する  
- 文字列 diff は実行器の表示の試験であって、言語の試験ではない  

参照実装があるなら差分解釈が効く。同じ AST を「計画器 A」と「計画器 B」に渡し、効果列が一致するか。  
ホスト sh で書いた旧手順を正解にすると、旧手順の冗長まで仕様になるので、正解は **人間が承認した効果列**にする。

### 性質試験（property）

可変点が少ない DSL ほど安い。

- 任意の個体パラメータに対し、計画は種族効果列を包含する  
- 名前を変えてもパッケージ集合は変わらない  
- 同じソースを二度読んだ計画は `equal?`  

入力生成は **文法に沿わせる**。汎用のランダム S 式はほとんど構文エラーになり、静的層の再試験で終わる。  
jail 名の文字種、IPv4 の形、volume の絶対パス、といった意味制約だけを generator に書く。

---

## 4. 拒否の言葉と位置

ドメイン語で落ちること自体が仕様である。  
`car: contract violation` や namespace-undefined が出る試験は、言語が部品として閉じていない印である。

試験は例外の型だけでなく、**メッセージの断片**と、可能なら **構文位置**を見る。

```racket
(define (syntax-msg th)
  (with-handlers ([exn:fail:syntax? (λ (e) (exn-message e))])
    (th)
    #f))

(check-regexp-match
 #rx"未知の語"
 (syntax-msg (λ () (expand (load-as "s-exp \"stack-calc.rkt\"" "foo\n")))))
```

位置が元の `#lang` ファイルを指すこと（マクロ展開後の一時識別子を指さないこと）は、hygiene と `syntax/loc` の回帰である。  
エージェントが直すとき、エラーがスロット名を言わなければ **同型は使えない**。

---

## テストを言語にする

テストハーネスを Racket の手続きの山にすると、またライブラリーになる。  
層が増えたら、試験側も `#lang` にする。

Spoofax SPT、Rascal の TestQL、MPS のテスト DSL はみな「被試験言語を埋め込む試験言語」である。Racket なら例えば:

```racket
#lang makejail/test

(ok
  (name "wiki-03")
  (hostname "wiki-03.example")
  ...)

(reject "host net in fleet"
  (option network host)
  ...)

(plan=
  (name "wiki-03")
  ...
  =>
  (pkg "caddy")
  (wiki-site #:forbid-install? #t)
  ...)
```

`ok` / `reject` / `plan=` は試験言語の語彙で、本文は makejail の語彙である。  
これで試験ファイル自体がドメインの文書になる。

Gherkin（`#lang feature`）を先に置く必要はない。Given/When/Then は汎用語で、jail の変更軸（**個体・種族・運用**）の方が試験の軸として短い。

Turnstile が `check-type` を言語の隣に置いたのも同じ発想である。

---

## 三軸と前提（0.4）

同型の軸は **個体 / 種族 / 運用** である（[three-axes-isomorphism](three-axes-isomorphism)）。  
`(host)/(in-jail)` を必須構文としてはテストしない（設けない方針）。内部効果の scope 表示は任意。

## 同型をテストする

Issue #8 の尺度 **ρ(R)**（要求一点に対するロックステップ編集数）は、テストでも測れる。

1. 種族フィクスチャを一つ持つ  
2. 個体パラメータを一つだけ変えたクローンを機械的に作る  
3. 効果列の diff が、そのパラメータに対応するスロットだけであることを `check-equal?` する  

hostname を変えて Caddy の forbid パスや pkg 集合が動いたら、言語が同型を失っている。  
この試験は機能試験ではなく **設計試験**である。失敗したら利用例を直すのではなく、**フォームを直す**。

冗長度そのものを CI で数えるなら、計画器に「スロット由来」の起源を付けておき、diff のキー集合の濃度を ρ の近似にする。  
起源が無い効果（生の `(cmd)`）は常に失敗扱いする。

---

## 走らせ方（Racket の型）

| 置き場 | 内容 |
|--------|------|
| 言語モジュールの `module+ test` | 層 2・3 の小さな検査（置けるなら） |
| reader / brag 専用 | 別 `*-test.rkt` |
| 被試験プログラム | `tests/ok/` と `tests/reject/` |
| 正本 | `raco test`（DrRacket の test サブモジュールと同じ契約） |

実行器の結合試験（実 jail）はタグを分け、**既定の `raco test` から外す**。  
Linux 上では構文・計画までが全部通る、が makejail の約束なので、**CI の主列はそこまで**である。

ランダム生成は「落ちない」だけを見ると弱い。  
生成した個体が計画に通り、かつ種族ゴールデンとの diff がスロット集合に含まれる、までを性質にする。

---

## やってはいけないこと

| 禁止 | 理由 |
|------|------|
| 表面を経由せず内部の `push!` / `install-pkg` を直接叩く | 実装の単体であり部品境界の試験ではない |
| `--apply` の成功を言語の正解にする | 副作用は実行器と OS の試験 |
| エラーを「例外が出ればよい」で止める | ドメイン語と位置が仕様 |
| 正例だけをサンプルに置く | **拒否集合が言語の輪郭** |
| ホスト Racket の行網羅を言語カバレッジとみなす | 見るべきはフォーム・段階・変更軸（構文非終端と効果の種類） |

内部関数の試験は、パイプラインが厚くなってから **補助的に**足す。

---

## 短い導入順（言語の TDD）

関数の TDD より先に **拒否から入る**。

1. 拒否ファイルを一つ書く（まだ実装が無くて落ちる）  
2. その拒否がドメイン語で出るまで `#%app` / フォームを閉じる  
3. 正例を一つ書き、効果列（またはスタック）をゴールデンにする  
4. 個体パラメータを一つ変えた正例を足し、diff が 1 スロットか見る  
5. 種族を変える試験は **言語モジュール側にだけ**置く  

- **1 と 2** … 「言語を部品にする」のテスト  
- **3 と 4** … 「要求と実装を同型に近づける」のテスト  
- **5** を利用ファイルに書くと ρ がまた増える  

---

## makejail 現状との対応（メモ）

| 層 | いまの足場 | 伸ばす方向 |
|----|------------|------------|
| 構文 | `raco test` で assemble / agent-plan-ok | `tests/ok`・`tests/reject` の `#lang makejail` 正本 |
| 静的 | prefab + `plan->effects` | 正規形ゴールデン、種族 diff のみ |
| 動的 | dry-run 表示 | 効果列オブジェクト比較（文字列ではない） |
| 拒否の言葉 | 実行時 `plan-validate!` が多い | `raise-syntax-error` + メッセージ試験 |
| 同型 ρ | Issue #8 コメント | 個体1変更 diff 試験 |

---

## 関連

- [lop-and-macros](lop-and-macros)  
- [stack-calc](stack-calc)  
- [beautiful-racket-stacker](beautiful-racket-stacker)  
- [Issue #4](https://github.com/bluehive/my-makejail-lop/issues/4) · [Issue #8](https://github.com/bluehive/my-makejail-lop/issues/8)  
- Spoofax SPT / mbeddr / Turnstile（外部概念の参照）  
