# Overview — Racket LOP としての makejail

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause（リポジトリ本体に準拠）  
> 対象コード: [bluehive/my-makejail-lop](https://github.com/bluehive/my-makejail-lop)（Grok-order MVP プロトタイプ）

このリポジトリは **Racket の LOP（Language-Oriented Programming）** を使って、FreeBSD の Jail 設定を **`#lang makejail` という独自の言語** として実装したプロトタイプです。[Beautiful Racket](https://beautifulracket.com/introduction.html) の「ドメインを安く言語化する」という考え方の実験台になっています。

ここでは、このコードから読み取れる **「Racket で LOP をどう実践しているか」** を中心に説明します。

---

## 1. LOP の全体像：言語を「定義」して「使う」

このプロジェクトでは、ユーザーが特別な API を覚えるのではなく、**ドメイン固有の構文をトップレベルに並べる**ことで Jail を定義できるようにしています。

```racket
#lang makejail

(name "web-nginx")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/web-nginx")
(option network host)

(pkg "nginx")
(sysrc "nginx_enable" "YES")
(copy "templates/nginx.conf" "/usr/local/etc/nginx/nginx.conf")
(service nginx start)
```

このコードは **Racket のプログラム** でありながら、**makejail という言語で書かれた設定ファイル** のように見えます。これが LOP の特徴です。

---

## 2. 言語の「定義」側（Language Implementation）

LOP ではまず「言語の文法と意味」を Racket で実装します。このリポジトリでは次の 3 つが核になります。

### (1) `lang/reader.rkt` — 言語のエントリポイント

```racket
#lang s-exp syntax/module-reader
makejail
```

S 式ベースの言語として `makejail` を登録しています。これにより `#lang makejail` と書くと、`main.rkt` で定義された言語が使われます。

### (2) `main.rkt` — 構文と意味の実装

ここで **「どのような構文を使えるか」** と **「その構文が何を表すか」** を定義しています。

#### 構文の定義（例）

```racket
(define-syntax (name stx)
  (syntax-parse stx
    [(_ n:str) #'(mj-option 'name n)]))
```

`(name "web-nginx")` という構文を、内部データ構造 `mj-option` に変換するマクロです。

#### データ構造（AST）

```racket
(struct mj-arg (name has-default? default-val) #:prefab)
(struct mj-from (kind ref) #:prefab)
(struct mj-option (key val) #:prefab)
(struct mj-step (op args) #:prefab)
(struct mj-plan (name args from options steps) #:prefab)
```

すべての構文は最終的にこれらの構造体（**prefab** 構造体）に変換され、**AST（抽象構文木）** として組み立てられます。

#### モジュール開始時の処理

```racket
(define-syntax (mj-module-begin stx)
  (syntax-parse stx
    [(_ form:expr ...)
     #'(#%module-begin
        (provide current-plan)
        (define current-plan (assemble-plan (list form ...)))
        (void))]))
```

`#lang makejail` と書かれたモジュールが読み込まれるとき、トップレベルに並べられた構文が `assemble-plan` で 1 つの `mj-plan` にまとめられます。

### (3) `runtime/executor.rkt` — 実行エンジン

`plan->effects` で AST を **「効果（effect）の列」** に変換し、`execute-plan!` で実際のコマンド（`zfs clone`、`jail`、`pkg` など）を実行します。

```racket
(define (plan->effects p #:phase [phase 'build])
  ...
  (case phase
    [(build) (push! 'zfs-clone ref ds) (push! 'jail-create-path name path) ...]
    ...))
```

**dry-run モード** では効果を表示するだけで、`--apply` で実際に FreeBSD 上で実行されます。

---

## 3. LOP の設計パターンから学べること

このコードから読み取れる LOP の典型的なパターンは次のとおりです。

1. **`#lang` で新しい言語を定義**（`lang/reader.rkt`）
2. **構文をマクロで定義**（`main.rkt` の `define-syntax`）
3. **構文を AST（`struct`）に変換**
4. **AST を「効果リスト」に変換**（`plan->effects`）
5. **効果を実行または表示**（`execute-plan!` / `effects->display`）

この **「構文 → AST → 効果 → 実行」** という流れは、Beautiful Racket で推奨される LOP の典型的なアーキテクチャです。

---

## 4. まとめ

このリポジトリは **Racket の LOP を実践するための具体的な教材** としても使えます。

| 層 | ファイル |
|----|----------|
| 言語定義 | `lang/reader.rkt` + `main.rkt` |
| 構文の拡張 | マクロ（`define-syntax` / `syntax-parse`） |
| AST の設計 | prefab `struct` |
| 実行エンジン | `runtime/executor.rkt` |
| CLI | `raco.rkt`（`raco makejail`） |

このコードを読み解くことで、「Racket でどうやって独自言語を作るか」の実装パターンを学ぶことができます。

---

## 関連ページ

- [使い方](使い方) — 構文一覧・CLI・MVP の注意点  
- [Issue #1 設計レビュー](https://github.com/bluehive/my-makejail-lop/issues/1)  
- [Issue #3 thin-vnet 仕様](https://github.com/bluehive/my-makejail-lop/issues/3)  

## 関連

- [bsd-appsと比較](bsd-appsと比較)
