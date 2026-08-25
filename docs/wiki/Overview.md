# Overview — Racket LOP としての makejail

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 対象: [bluehive/my-makejail-lop](https://github.com/bluehive/my-makejail-lop) **0.4**  
> 仕様: [Issue #9](https://github.com/bluehive/my-makejail-lop/issues/9) · [three-axes-isomorphism](three-axes-isomorphism) · [dsl-design-principles](dsl-design-principles)

このリポジトリは **Racket の LOP（Language-Oriented Programming）** で、FreeBSD Jail へのアプリ投入を **`#lang makejail`** として実装した DSL です。[Beautiful Racket](https://beautifulracket.com/introduction.html) の「ドメインを安く言語化する」実験台でもあります。

利用者ファイルは「一つの jail **個体**をどうしたいか」を書きます。ホスト上の ZFS や `jexec` は言語と実行器の仕事です（host/in-jail セクションは設けません）。

---

## 1. 利用者が書くもの（0.4）

変更軸は三つです（[three-axes-isomorphism](three-axes-isomorphism)）。

| 軸 | 表面 | 編集のしかた |
|----|------|----------------|
| **個体** | `(instance …)` / `(arg …)` | 名前・hostname・volume パスなどスロットだけ |
| **種族** | `(wiki-site)` など **1 フォーム** | 中身の pkg 列は書かない（言語が展開） |
| **運用** | 言語の受理（agent 既定） | cmd 不可、host ネット量産不可 |

### 量産向け例（DokuWiki 種族）

```racket
#lang makejail

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance
 #:name "dokuwiki-caddy"
 #:hostname "{{hostname}}"
 #:data-host "{{data-host}}")

(arg hostname)
(arg data-host)

(wiki-site)
```

```bash
raco makejail check examples/dokuwiki-caddy.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data
```

- **dataset** は `name` から導出（二重に書かない）  
- **hostname** の Caddyfile への埋め込みは言語側（`template-subst`）。sed / `(cmd)` は使わない  
- 種族の展開表は `family/dokuwiki.rkt`（1 モジュール）

### 単純な pkg 例（nginx）

```racket
#lang makejail

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance #:name "web-nginx")

(pkg "nginx")
(sysrc "nginx_enable" "YES")
(copy "templates/nginx.conf" "/usr/local/etc/nginx/nginx.conf")
(service nginx start)
```

（agent 量産では `network host` は不可。実験で使うなら人間が `--human --allow-host-net`。）

---

## 2. 言語の定義側（実装の読み方）

### (1) `lang/reader.rkt`

```racket
#lang s-exp syntax/module-reader
makejail
```

`#lang makejail` の入口。表面は S 式のまま。

### (2) `main.rkt`

- **provide** = 受理集合（無い名前は書けない）  
- **マクロ** … `name` / `from` / `arg` / `option` / `service` など  
- **個体** … `(instance …)` → assemble で name・arg・option に正規化  
- **種族** … `(wiki-site)` → `family/dokuwiki.rkt` が効果の種に展開  
- **AST** … prefab の `mj-plan` / `mj-step` など  
- **`#%module-begin`** … ファイル全体を `assemble-plan` → `current-plan`  

### (3) `runtime/executor.rkt`

`plan->effects` の効果列を dry-run 表示、または FreeBSD 上で実行。  
言語の観測の正本は **効果列**まで（[dsl-testing](dsl-testing)）。

```
ソース（個体 + 種族 + from/…）
  → マクロ / assemble / normalize
  → mj-plan
  → 種族展開 → plan->effects
  → dry-run / --apply
```

---

## 3. CLI

```bash
raco pkg install --link /path/to/my-makejail-lop

raco makejail plan  examples/dokuwiki-caddy.rkt --arg hostname=… --arg data-host=…
raco makejail check examples/dokuwiki-caddy.rkt --arg hostname=… --arg data-host=…
raco makejail build examples/dokuwiki-caddy.rkt --dry-run --arg …
# FreeBSD のみ:
raco makejail build examples/dokuwiki-caddy.rkt --apply --arg …
raco makejail destroy examples/dokuwiki-caddy.rkt --apply --arg …
```

| フラグ | 意味 |
|--------|------|
| `--agent`（既定） | cmd 不可、host ネット量産不可 |
| `--human` | 人間向け（なお cmd には `--allow-cmd`） |
| `--arg k=v` | 必須個体スロットの注入 |
| `--dry-run` / `--apply` | 計画表示 / 実実行 |

詳細は [使い方](使い方)、エージェント契約は [P02](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)。

---

## 4. LOP として学べること

1. `#lang` で受理集合を閉じる  
2. 名詞（スロット・種族）をフォームにし、How は展開に閉じる  
3. 禁止は運用（受理）で切る  
4. テストはライブラリー単体ではなく四層（[dsl-testing](dsl-testing)）  
5. 設計原則の一般化（[dsl-design-principles](dsl-design-principles)）  

---

## 関連

- [three-axes-isomorphism](three-axes-isomorphism)  
- [dsl-design-principles](dsl-design-principles)  
- [使い方](使い方) · [examples-freebsd15](examples-freebsd15)  
- [dsl-testing](dsl-testing) · [lop-and-macros](lop-and-macros)  
- [Beautiful Racket: Introduction](https://beautifulracket.com/introduction.html)  
