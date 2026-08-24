# Beautiful Racket と stacker — LOP 入門

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause（本 Wiki 整理文）  
> 関連: [lop-and-macros](lop-and-macros) · [stack-calc](stack-calc) · [creating-languages-in-racket](creating-languages-in-racket)  
> 原典の学習教材: [Beautiful Racket](https://beautifulracket.com/)（Matthew Butterick）— 著作権は各権利者に帰属。本文の引き写しではなく手順の整理。

---

## Beautiful Racket と LOP の概要

『Beautiful Racket』は、Racket を使ってプログラミング言語（DSL）を作る方法を学ぶための書籍・サイトです。Racket は「プログラマブルなプログラミング言語」を自称し、**言語指向プログラミング（Language-Oriented Programming, LOP）** を実践するための強力なツールを提供します。

LOP では、「**言語を作ることがプログラミングの一部**」という考え方が中心にあります。汎用言語で直接問題を解くのではなく、**問題に最適化された小さな言語（DSL）をまず作り、その上で解決策を記述する** というアプローチです。

makejail の `#lang makejail` も同じ発想です。stacker は、その入口として **数十行で完結するスタック計算機** を体験する教材です。本リポジトリの [stack-calc](stack-calc) は、Beautiful Racket に依存しない姊妹実験です。

---

## スタック計算機「stacker」とは

stacker は、スタックベースの計算機言語です。ルール:

| 規則 | 意味 |
|------|------|
| 初期状態 | スタックは空 |
| 各行 | スタックへの 1 操作 |
| 数字 | 一番上に積む（push） |
| 演算子 `+` または `*` | 上から 2 つを pop し、結果を push |

例: `3 * (8 + 4)` → 結果 **36**

```
4
8
+
3
*
```

---

## step 1: 環境の準備

```bash
# Racket インストール後
raco pkg install beautiful-racket
```

DrRacket では、新しいファイルの先頭に `#lang br` と書くと Beautiful Racket 言語が有効になります。

---

## step 2: 言語の骨格

`stacker.rkt` が **言語実装そのもの** です。最小骨格:

```racket
#lang br/quicklang
```

`br/quicklang` は Beautiful Racket の簡易言語作成用基盤です。リーダーとエキスパンダーを最小限のコードで定義できます。

---

## step 3: リーダー（reader）

**リーダー**は、ソースコード（テキスト）を Racket が理解できるデータ構造（S 式）に変換します。

stacker では、各行を `(handle 行の内容)` にします。

```racket
#lang br/quicklang

(define (read-syntax path port)
  ;; ポートから全行を読み込む
  (define src-lines (port->lines port))
  ;; 各行を (handle ...) という形に変換
  (define src-datums (format-datums '(handle ~a) src-lines))
  ;; モジュールとしてまとめる
  (define module-datum
    `(module stacker-mod "stacker.rkt"
       ,@src-datums))
  ;; 構文オブジェクトにして返す
  (datum->syntax #f module-datum))

(provide read-syntax)
```

| API | 役割 |
|-----|------|
| `port->lines` | 各行をリストに |
| `format-datums` | 各行を `(handle 値)` に |
| `module` でラップ | Racket モジュールとして認識 |
| `datum->syntax` | 生 datum → **構文オブジェクト**（位置情報付き） |

---

## step 4: エキスパンダー（expander）

**エキスパンダー**は、リーダーが作った S 式を、実行可能な Racket コードに変換します。

stacker では `handle` の列のあと、スタック先頭を表示します。

```racket
(define-macro (stacker-module-begin HANDLE_EXPR ...)
  #'(#%module-begin
      HANDLE_EXPR ...
      (display (first stack))))

(provide (rename-out [stacker-module-begin #%module-begin]))
```

| 要点 | 意味 |
|------|------|
| `#%module-begin` | モジュール本体を包む特殊フォーム。置き換えると言語の振る舞いを変えられる |
| `define-macro` | BR 流のマクロ。`HANDLE_EXPR ...` で複数式を受ける |
| 展開結果 | 元の handle 列の後に `(display (first stack))` |
| `rename-out` | `stacker-module-begin` を `#%module-begin` として提供 |

makejail の `mj-module-begin` → `current-plan` も同じ段です（[lop-and-macros](lop-and-macros)）。

---

## step 5: スタック操作

```racket
(define stack empty)

(define (pop-stack!)
  (define arg (first stack))
  (set! stack (rest stack))
  arg)

(define (push-stack! arg)
  (set! stack (cons arg stack)))

(define (handle [arg #f])
  (cond
    [(number? arg) (push-stack! arg)]
    [(or (equal? + arg) (equal? * arg))
     (define op-result (arg (pop-stack!) (pop-stack!)))
     (push-stack! op-result)]))

(provide handle)
(provide + *)
```

- `stack` は可変リスト（`set!`）
- 数字 → push、演算子 → 2 pop して演算して push
- `+` / `*` も provide（利用者プログラムの語彙）

---

## step 6: 全体像（完成コード）

`stacker.rkt`:

```racket
#lang br/quicklang

;; ===== リーダー =====
(define (read-syntax path port)
  (define src-lines (port->lines port))
  (define src-datums (format-datums '(handle ~a) src-lines))
  (define module-datum
    `(module stacker-mod "stacker.rkt"
       ,@src-datums))
  (datum->syntax #f module-datum))

(provide read-syntax)

;; ===== エキスパンダー =====
(define-macro (stacker-module-begin HANDLE_EXPR ...)
  #'(#%module-begin
      HANDLE_EXPR ...
      (display (first stack))))

(provide (rename-out [stacker-module-begin #%module-begin]))

;; ===== スタック操作 =====
(define stack empty)

(define (pop-stack!)
  (define arg (first stack))
  (set! stack (rest stack))
  arg)

(define (push-stack! arg)
  (set! stack (cons arg stack)))

(define (handle [arg #f])
  (cond
    [(number? arg) (push-stack! arg)]
    [(or (equal? + arg) (equal? * arg))
     (define op-result (arg (pop-stack!) (pop-stack!)))
     (push-stack! op-result)]))

(provide handle)
(provide + *)
```

---

## step 7: 言語を使ってみる

`test.rkt`:

```racket
#lang reader "stacker.rkt"
4
8
+
3
*
```

**実行結果:** `36`

### 仕組み

1. `#lang reader "stacker.rkt"` → `read-syntax` が呼ばれる  
2. 各行が `(handle 4)` `(handle 8)` `(handle +)` … に変換  
3. モジュールとして Racket に渡る  
4. `stacker-module-begin` が展開され、各 `handle` が実行  
5. 最後に `(display (first stack))`

---

## LOP の重要な概念まとめ

### リーダーとエキスパンダー

| 役割 | 入力 | 出力 |
|------|------|------|
| リーダー | ソース（テキスト） | S 式（構文オブジェクト） |
| エキスパンダー | S 式（構文オブジェクト） | 実行可能な Racket コード |

### マクロによる言語拡張

`#%module-begin` の置き換えが、言語の動作を根本から変える鍵です。前後に処理を足したり、意味を変えたりできます。

### DSL 作成の 3 ステップ

1. **リーダー** … テキスト → S 式  
2. **エキスパンダー** … S 式 → Racket コード  
3. **実行関数** … 実際の処理（スタック操作など）

makejail では:

1. `lang/reader.rkt`（S 式のまま `syntax/module-reader`）  
2. `main.rkt` の `mj-module-begin` + 語彙  
3. `plan->effects` + `runtime/executor.rkt`  

---

## 初学者へのアドバイス

1. **まず動かす** — 完成コードをコピーして結果を確認  
2. **1 行ずつ追う** — リーダー → エキスパンダー → 実行関数  
3. **改造する** — `-` や `/` を足すと理解が深まる  
4. **`#lang br` を使う** — BR のマクロ・関数を活用  

stacker はわずか **40 行程度**で実装できる LOP 入門です。「言語を作ることが自然で強力な手法であること」を体感するための入口になります。

---

## 本リポジトリとの対応

| Beautiful Racket stacker | makejail / stack-calc |
|--------------------------|------------------------|
| 行単位リーダー | 当面 S 式（`lang/reader.rkt`） |
| `handle` + スタック | jail 語彙 + `mj-plan` / 効果列 |
| `#%module-begin` で末尾 display | `current-plan` を provide |
| `br/quicklang` | `racket/base` + `syntax/parse`（依存少なめ） |

姉妹実装: リポジトリ内 [`artifacts/stack-calc/`](https://github.com/bluehive/my-makejail-lop/tree/main/artifacts/stack-calc) · Wiki [stack-calc](stack-calc)

---

## 関連

- [lop-and-macros](lop-and-macros)  
- [stack-calc](stack-calc)  
- [creating-languages-in-racket](creating-languages-in-racket)  
- [Beautiful Racket](https://beautifulracket.com/)  
- [Beautiful Racket: Introduction](https://beautifulracket.com/introduction.html)  
