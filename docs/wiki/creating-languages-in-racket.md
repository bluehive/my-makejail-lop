# Racket における言語作成（Matthew Flatt / ACM Queue）

> 記述: DeepSeek（意訳・整理）  
> 原典: Matthew Flatt, *Creating Languages in Racket*（ACM Queue 掲載）  
> ライセンス: 本 Wiki ページの整理文はリポジトリ同様 **BSD-2-Clause** の趣旨で公開。原論文・商標は各権利者に帰属。  
> 関連: [Overview](Overview)（makejail での LOP 実践）

Racket が **プログラミング言語であると同時に、言語を作るためのフレームワーク** でもあることを、テキストアドベンチャーゲームの実装を例に、段階を追って説明する記事の整理です。

---

## 1. はじめに：言語指向プログラミング

複雑なタスクには最適なツールを選ぶことが重要です。プログラマーはしばしば、問題を解決するための **新しい言語** を作り出すことで、より生産的になれます。この考え方は **言語指向プログラミング（LOP）** と呼ばれます。

Racket はこのアプローチを強力に支援します。

- プログラム内で言語の **構文を拡張** する  
- まったく **新しい言語をモジュール** として定義する  

記事では、単純な構文拡張から、独自言語と IDE サポートまでを段階的に示します。

---

## 2. プレーンな Racket で実装する世界

拡張なしで、ゲームのデータ構造を定義します。

```racket
(struct verb
  (aliases      ; 記号のリスト
   desc         ; 文字列
   transitive?)) ; ブール値

(struct thing
  (name
   [state #:mutable] ; 任意の値
   actions))         ; 動詞-関数のペアのリスト

(struct place
  (desc
   [things #:mutable]
   actions))
```

- `struct` … 構造体型  
- `#:mutable` … 変更可能なフィールド  

例: `south` 動詞

```racket
(define south (verb (list 'south 's) "go south" #false))
```

場所と物は登録され、名前と値のマッピングが管理されます。  
ただしこの方法では、世界を構築するコードが **非常に冗長** になります。

---

## 3. 構文抽象化（Syntactic Abstraction）

冗長さを減らすために **マクロ** を使います。`define-syntax-rule` でパターンベースのマクロを定義できます。

```racket
(define-syntax-rule (define-place id desc [thng ...] ([vrb expr] ...))
  (begin
    (define id
      (place desc
             (list thng ...)
             (list (cons vrb (lambda () expr)) ...)))
    (record-element! 'id id)))
```

- 直後が **パターン**、次が **テンプレート**  
- `...` は 0 個以上の繰り返し  

利用例:

```racket
(define-place desert
  "You're in a desert."
  [cactus key]
  ([north meadow]
   [south desert]
   [east desert]
   [west desert]))
```

同様に `define-thing` や `define-verbs` も定義できます。  
これは **構文抽象化** の例で、ボイラープレートを消し、ゲームの本質に集中させます。

---

## 4. 構文拡張（Syntactic Extension）

複数ゲームでエンジンを再利用するときは、マクロや関数を **モジュール化** します。

| ファイル | 役割 |
|----------|------|
| `world.rkt` | 世界定義（`#lang racket` + `require` エンジン） |
| `txtadv.rkt` | エンジン実装。マクロと関数を `provide` |

```racket
;; txtadv.rkt
#lang racket
(provide define-verbs define-thing
         define-place define-everywhere
         save-game load-game ....)
(struct verb ....)
(define-syntax-rule (define-place ....) ....)

;; world.rkt
#lang racket
(require "txtadv.rkt")
(define-verbs ....)
(define-place ....) ...
```

重要な点: **マクロバインディングも変数と同様にモジュールシステムで扱われ**、展開時も字句スコープが維持されます。

---

## 5. モジュール言語（Module Languages）

さらに進めると、`txtadv.rkt` 自体を **言語** として使えます。

```racket
;; world.rkt
#lang s-exp "txtadv.rkt"
(define-verbs ....)
...
```

- `s-exp` … S 式構文を使う  
- 言語側は Racket 全機能を export してもよいし、制限してもよい  
- `#%module-begin` の置き換えで、モジュール構造（例: `define-verbs` が先頭必須）を強制し、**ドメイン固有のエラー**を出せる  

→ makejail の `#lang makejail` + `mj-module-begin` と同じ階層の話（[Overview](Overview)）。

---

## 6. 静的チェック（Static Checks）

マクロで **コンパイル時** の検査ができます。

一般形:

```racket
(define-syntax id transformer-expr)
```

`begin-for-syntax` でコンパイル時専用コードを書けます。識別子に型情報（`"place"` / `"thing"` など）を付け、`define-place` 内で参照の型を検証する例が記事にあります。

```racket
(begin-for-syntax
  (struct typed (id type)
    #:property prop:procedure
    (lambda (self stx) (typed-id self))))

(define-syntax-rule (define-place id desc [thng ...] ([vrb expr] ...))
  (begin
    (define gen-id
      (place desc
             (list (check-type thng "thing") ...)
             (list (cons (check-type vrb "intransitive verb")
                         (lambda () expr)) ...)))
    (define-syntax id (typed #'gen-id "place"))
    (record-element! 'id id)))
```

物であるべき場所に誤って place を置いた場合など、**実行前（コンパイル時）** に検出できます。

makejail での対応イメージ: 二重 `(from …)` 禁止、将来の ARG 必須チェック、STAGE 規則など（現状 MVP は一部のみ）。

---

## 7. 新しい構文（New Syntax）

S 式以外の表面構文も可能です。

```racket
#lang reader "txtadv-reader.rkt"
===VERBS===
north, n "go north"
get _, grab _, take _ "take"
....
===PLACES===
---desert---
"You're in a desert."
[cactus, key]
north start
south desert
....
```

- `reader` 言語がパーサを指定  
- テキスト → **ソース位置付き構文オブジェクト**（S 式相当）  
- エラー位置は **生成コードではなく元の独自構文** を指せる  

makejail は当面 **S 式**（`#lang s-exp` / `syntax/module-reader`）。独自表面構文は将来の選択肢。

---

## 8. IDE サポート

DrRacket は、言語定義者が追加情報を出すと支援が厚くなります。

- リーダーを **コレクション** としてインストールし、名前で参照  
- 構文カラーリング等を提供する関数を実装  
- 言語固有のハイライト・エラーチェックが可能  

`#lang makejail` を `raco pkg install` したときの体験と同系統です。

---

## まとめ（Flatt の階段）

| 段階 | 内容 | makejail での位置 |
|------|------|-------------------|
| 1. プレーン Racket | struct と手続き | executor の土台 |
| 2. 構文抽象 | `define-syntax-rule` | `(name)` `(pkg)` 等のマクロ |
| 3. 構文拡張 | モジュール + provide | `main.rkt` パッケージ化 |
| 4. モジュール言語 | `#lang` | `#lang makejail` |
| 5. 静的チェック | begin-for-syntax | 二重 from 等（拡張余地） |
| 6. 新構文 | カスタム reader | 未着手（S 式のまま） |
| 7. IDE | DrRacket 連携 | パッケージ化で一部 |

Racket は単なる言語ではなく、**問題に合う言語を作るツールキット**である——記事の中心メッセージです。makejail は、その階段の **4 付近** にいる実験台、と読むと [Overview](Overview) とつながります。

---

## 関連

- [Overview](Overview) — makejail での LOP  
- [使い方](使い方)  
- [bsd-appsと比較](bsd-appsと比較)  
- [Beautiful Racket: Introduction](https://beautifulracket.com/introduction.html)  
- ACM Queue / Matthew Flatt *Creating Languages in Racket*（原記事を検索）  

- [lop-and-macros](lop-and-macros)
