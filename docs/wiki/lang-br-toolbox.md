# `#lang br` — 言語開発のティーチング用ツールボックス

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause（本 Wiki 整理文）  
> 関連: [beautiful-racket-stacker](beautiful-racket-stacker) · [lop-and-macros](lop-and-macros) · [stack-calc](stack-calc)  
> 教材: [Beautiful Racket](https://beautifulracket.com/) — 著作権は各権利者に帰属。

---

## 概要

`#lang br` は、Racket の言語開発をよりスムーズにするための **teaching language**（教育・入門向け言語）です。

単なる言語処理系ではなく、次をまとめた **「言語開発のためのツールボックス」** です。

- マクロ作成を簡略化するモジュール群（`br/macro`、`br/syntax`）
- 便利な制御構文
- デバッグ用の関数

`#lang br` を使うとこれらが自動的に入ります。必要なら **個別モジュール** としても `require` できます。

makejail 本体は依存を抑えるため `racket/base` + `syntax/parse` を使いますが、**stacker 入門やマクロ練習**では `#lang br` / `br/quicklang` が近道です（[beautiful-racket-stacker](beautiful-racket-stacker)）。

---

## マクロ作成を強力にサポート（`br/macro`, `br/syntax`）

Racket 標準の `define-syntax` や `syntax-parse` をよりシンプルに使えるようにした、`#lang br` の核です。

### `define-macro`

マクロを定義する主要なフォーム。

**シンプルな定義**

```racket
(define-macro (macro-name ARG ...)
  #'...)
```

- パターン変数は **大文字** で書くルール（リテラルと視覚的に区別しやすい）
- 展開結果は `#'…`（構文テンプレート）

**リネームマクロ**

```racket
(define-macro id #'other-id)
```

`id` を `other-id` に置き換えるだけのマクロを短く書ける。

### `define-macro-cases`

一つのマクロに **複数の呼び出しパターン**（引数の数など）を持たせたいとき。  
Racket の `case-lambda` に近い感覚で、パターンごとに異なる展開を書ける。

### `caller-stx`

`define-macro` 本体の内部で使える特殊変数。  
**マクロが呼び出された場所全体**の構文オブジェクトを取得する。  
デバッグや、呼び出し元情報を使った高度なマクロに役立つ。

---

## 便利な制御構文（`br/cond`）

| 構文 | 意味 |
|------|------|
| `while` | 条件が真のあいだ繰り返し |
| `until` | 条件が真になるまで繰り返し |

手続き的な処理を、言語実装の「実行関数」側で書きやすくする。

---

## デバッグを容易にする（`br/debug`）

| フォーム | 意味 |
|----------|------|
| `report` | 式を評価し、**名前と値**を標準エラーに出す。戻り値はそのまま → 動作を変えずに差し込める |
| `report-datum` | `report` に似るが、構文オブジェクトではなく **中身の datum** だけを表示 |

複雑なマクロ展開の途中経過を見るのに向く。

---

## その他のユーティリティ

| モジュール | 内容 |
|------------|------|
| `br/list` | リスト操作の便利関数群 |
| `br/define` | `define-cases` など、関数定義を補助するマクロ |

---

## `define-macro` の具体例（標準との比較）

### 1. 標準: `define-syntax` + `syntax-rules`

```racket
(define-syntax mac1
  (syntax-rules ()
    [(mac1 X bar Y) (list X "second" Y)]))
```

### 2. Beautiful Racket: `define-macro`

```racket
(define-macro (mac1 X bar Y)
  #'(list X "second" Y))
```

`define-macro` の方が、直感的・宣言的にマクロを定義できることがわかります。  
（本番の makejail では `syntax-parse` の細かい構文クラスが欲しくなることが多く、標準側に寄せています。）

---

## まとめ：`#lang br` を選ぶ理由

`#lang br` が提供するマクロや関数は、Racket 言語開発の **入り口のハードルを下げる** ために設計されています。

| 利点 | 内容 |
|------|------|
| `define-macro` | 標準マクロより学習コストが低い |
| `while` / `until` | 手続き的処理が書きやすい |
| `report` | マクロ展開のデバッグが容易 |

stacker のような DSL を作るとき、「言語のロジック」に集中できるようにするための道具です。

**進め方の提案**

1. まず `#lang br` / `br/quicklang` で気軽に始める（[beautiful-racket-stacker](beautiful-racket-stacker)）  
2. 慣れたら、内側で動いている Racket（`syntax-parse`、`#%module-begin`）を覗く（[lop-and-macros](lop-and-macros)）  
3. 依存を減らした本番 DSL は `racket/base` 側へ（makejail / [stack-calc](stack-calc)）

気になるマクロや関数は、ぜひ実際に動かしてみてください。

---

## 関連

- [beautiful-racket-stacker](beautiful-racket-stacker) — stacker チュートリアル  
- [lop-and-macros](lop-and-macros) — makejail 視点のマクロ論  
- [stack-calc](stack-calc) — BR 非依存の姊妹スタック言語  
- [Beautiful Racket](https://beautifulracket.com/)  
