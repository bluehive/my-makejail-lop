# 三軸と展開 — makejail の同型設計（0.4 仕様）

> 記述: DeepSeek + Issue #8/#9 議論の整理  
> ライセンス: BSD-2-Clause  
> **正本（承認待ち）:** [Issue #9](https://github.com/bluehive/my-makejail-lop/issues/9)  
> 議論アーカイブ: [Issue #8](https://github.com/bluehive/my-makejail-lop/issues/8)（クローズ）  
> 関連: [dsl-testing](dsl-testing) · [lop-and-macros](lop-and-macros) · [P02](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)

---

## 1. 一般論: DSL と冗長度・同型

### 冗長度 ρ

DSL は冗長性を最小にすべきである。

**悪い設計:** 一つの事柄だけ変えたいのに、記述の **複数箇所を必ず同時変更**しなければならない。

そのコストを **ρ（冗長度）** と呼ぶ。目標は、意味のある変更軸ごとに **ρ ≈ 1**。

### 要求の動く単位（一般）

多くの運用 DSL では、変更はだいたい次に分かれる。

| 軸 | 一般的な意味 | 編集点 |
|----|--------------|--------|
| **個体** | この 1 インスタンスだけ違う属性 | スロット 1 か所 |
| **種族（型・テンプレ）** | 同じ種類に共通の中身 | 種族定義 1 か所 |
| **運用（政策）** | フリート全体で許す／許さない | 言語の受理 1 か所 |

**同型:** 要求文の軸と、ソース上の編集軸が揃って見えること。

**同型でない例:** ホスト名を「変数」「sed」「設定ファイル本文」「別の sysrc」の 4 箇所に持つ。要求「ホスト名を変えよ」に編集が 4 回要る。

### 同型の作り方（Racket・ライブラリではない）

「汎用 Racket で解いてから綺麗にする」のではない。**先に**要求の語彙と変更軸を言語の表面にする。

1. **名詞をフォームに** — 必須スロットは構文が持つ  
2. **動詞は効果に** — 今すぐ sh ではなく AST 上の効果  
3. **禁止は構文で消す** — linter ではなく `raise-syntax-error` / provide から外す  
4. **展開は言語側** — 埋め込み・導出・種族の表。利用側に sed を残した瞬間 ρ が戻る  

---

## 2. 本リポジトリへの適用（makejail）

### 対象ドメイン

FreeBSD 上で **一つの jail にアプリを入れる**（量産時は個体だけ変える）。  
代表例: 同一 jail 内 Caddy + DokuWiki。

### 三軸（表面に固定する）

| 軸 | makejail での意味 | 表面 | ρ=1 の編集 |
|----|-------------------|------|------------|
| **個体** | この jail の名前・hostname・volume パス・（将来）IP | `instance` スロット / `arg` / `name` | そのスロットだけ |
| **種族** | dokuwiki 等に共通の pkg・forbid・待ち受け | `(wiki-site …)` 等 **1 フォーム**、展開表は 1 モジュール | family 定義だけ |
| **運用** | 量産で host ネット禁止、cmd 禁止、秘密をソースに書かない | **受理集合**（agent 既定） | 言語側だけ |

### 展開は言語側（B）

| 事柄 | 言語がやる | 利用者がやらない |
|------|------------|------------------|
| hostname → Caddyfile 等 | `template-subst` 等の効果を生成 | `(cmd "sed" …)` |
| forbid / install 禁止 | 種族フラグ → harden 効果 | 個体ごとの rm コピペ |
| dataset 名 | 既定は `name` から導出 | name と dataset の常時二重管理 |
| 種族の pkg 列 | 1 マクロ／1 モジュールの展開表 | 個体に長い `(pkg)…` を並べる |

P02（#4）で例から sed を外したのはこの方向。0.4 では **検査を構文側**へ寄せ、常用の受理から cmd/sed を消す完了形を目指す。

### host / in-jail セクションは設けない（C）

**決定:** `(host …)` / `(in-jail …)` を DSL の **ルールとして導入しない**。

**理由（自明の前提）:**  
本 DSL が書くのは常に「**この jail 個体をどうしたいか**」である。個体スロットが指す設定対象が jail（およびその実現）であることは自明であり、利用者がホスト用ブロックと jail 用ブロックを書き分ける分割規則にはしない。

| よい | よくない |
|------|----------|
| 仕様書・Wiki に「前提」として一文で書く | 必須セクションとして覚えさせる |
| dry-run 内部で zfs と jexec を区別して表示してよい | 表面で host/in-jail を強制する |
| 三軸の同型を優先する | ネストを増やして ρ を隠す |

> makejail の利用者プログラムは、一つの jail 個体の計画である。  
> ホスト上の ZFS や jail(8) は言語と実行器の仕事であり、利用者が host / in-jail を書き分ける前提にはしない。

（Issue #8 初期の「構造化第一候補」は、三軸議論の結果 **表面としては不採用**。詳細は #9。）

---

## 3. 目標形（イメージ）

```racket
#lang makejail
;; 運用は言語既定（agent）— ここに運用ルールを並べない

(instance
  #:name "wiki-03"
  #:hostname "wiki-03.example"
  #:data-host "/zroot/wiki-03/data")

(wiki-site)   ; 種族。スロットを読んで展開（入口は一つ）
```

要求「hostname と data パスだけ変えよ」→ **instance の 2 スロットだけ**触る。

---

## 4. 他概念との対応

| 概念 | 位置 |
|------|------|
| 効果列 | 言語の意味の観測（[dsl-testing](dsl-testing)） |
| executor / jexec | 言語の外。`--apply` は結合試験 |
| `#lang br` | 教材（[lang-br-toolbox](lang-br-toolbox)）。本番 makejail は `syntax-parse` |
| thin-vnet (#3) | 個体スロット `ip` 等と接続。表面セクション問題ではない |
| Beautiful Racket | 「ドメインを安く言語化」— 三軸がそのドメイン語彙 |

---

## 5. テストとの接続

同型はテストで測る（[dsl-testing](dsl-testing) § 同型をテストする）:

1. 種族フィクスチャを一つ持つ  
2. 個体パラメータを一つだけ変える  
3. 効果列の diff が **そのスロット由来だけ**である  

hostname を変えて pkg 集合が動いたら、言語が同型を失っている。  
失敗したら利用例ではなく **フォーム／展開**を直す。

---

## 関連

- [Issue #9 仕様草案](https://github.com/bluehive/my-makejail-lop/issues/9)（**承認待ち**）  
- [Issue #8](https://github.com/bluehive/my-makejail-lop/issues/8)（議論・クローズ）  
- [dsl-testing](dsl-testing) · [lop-and-macros](lop-and-macros) · [使い方](使い方) · [Overview](Overview)  
