# makejail — FreeBSD Jail Automation DSL (Racket LOP)

| 項目 | 内容 |
|------|------|
| リポジトリ | https://github.com/bluehive/my-makejail-lop |
| バージョン | **0.2.0** (Grok-order MVP prototype) |
| コレクション | `makejail`（`#lang makejail`） |
| ライセンス | BSD-2-Clause |
| 設計レビュー | [Issue #1](https://github.com/bluehive/my-makejail-lop/issues/1) |
| **Wiki** | [Overview](https://github.com/bluehive/my-makejail-lop/wiki/Overview) · [使い方](https://github.com/bluehive/my-makejail-lop/wiki/%E4%BD%BF%E3%81%84%E6%96%B9) · [bsd-appsと比較](https://github.com/bluehive/my-makejail-lop/wiki/bsd-apps%E3%81%A8%E6%AF%94%E8%BC%83) · [Home](https://github.com/bluehive/my-makejail-lop/wiki) |
| Wiki ソース | リポジトリ内 [`docs/wiki/`](docs/wiki/)（記述: DeepSeek、ライセンス BSD-2-Clause） |

> **0.2 方針 (Issue #1 pivot)**  
> Gemini 0.1 の「VNET 先出し一発パイプライン」をやめ、Grok 仕様の **MVP 順**（計画=dry-run → 寿命 phase → アプリ投入 → volume → 単純 net）に寄せたプロトタイプです。  
> Beautiful Racket 的には「ドメインを安く言語化」する実験台。本番 AppJail 互換ではありません。

### ドキュメント（Wiki）

LOP の読み方と CLI は Wiki に分けてあります（本文は DeepSeek 記述）。

| ページ | 内容 |
|--------|------|
| [Overview](https://github.com/bluehive/my-makejail-lop/wiki/Overview) | `#lang makejail` と LOP（構文→AST→効果→実行） |
| [使い方](https://github.com/bluehive/my-makejail-lop/wiki/%E4%BD%BF%E3%81%84%E6%96%B9) | 構文表・`raco makejail`・MVP 注意 |
| [bsd-appsと比較](https://github.com/bluehive/my-makejail-lop/wiki/bsd-apps%E3%81%A8%E6%AF%94%E8%BC%83) | bsd-apps との比較、Caddy/DokuWiki/Samba、ハイブリッド |
| リポジトリミラー | [`docs/wiki/`](docs/wiki/) |

Wiki 未作成の場合は GitHub 上で一度 Wiki を有効化／最初のページ作成後、`scripts/publish-wiki.sh` で `docs/wiki` を同期できます。

## 何が言語か

jail にアプリを入れる作業を `#lang makejail` のトップレベル構文にします（require して手続きを並べるライブラリ API が表向きではありません）。

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

### 構文（MVP）

| 構文 | 意味 |
|------|------|
| `(name "…")` | jail 名 |
| `(from thin freebsd-14.3)` | thin + release 名（作成は TODO） |
| `(from zfs "pool/ds@snap")` | ZFS clone 元 |
| `(option dataset "…")` | clone 先 dataset |
| `(option network host)` | ホスト共有 net（既定寄り） |
| `(option nat)` / `(option expose 80)` / `(option virtualnet …)` | **受理するが executor では TODO/凍結** |
| `(arg password)` / `(arg x "default")` | 引数宣言（効果列に出る・未バインド検査は今後） |
| `(pkg …)` `(sysrc k v)` `(service name [start])` | アプリ投入 |
| `(copy src dst)` | ホストファイルを jail へ（build 時に中身をバンドル） |
| `(volume host jail-path)` / `(mount … #:readonly? #t)` | 永続・nullfs |
| `(cmd …)` `(workdir …)` | 任意コマンド / 作業ディレクトリ |

### 段階（phase）

| phase | 内容 |
|-------|------|
| `build` | 作成 + パッケージ等（既定） |
| `start` / `stop` | 寿命操作 |
| `destroy` | 停止 + zfs destroy 等 |

## CLI

```bash
raco pkg install --link /path/to/my-makejail-lop

# 効果列のみ（どの OS でも安全・既定）
raco makejail plan examples/nginx.rkt
raco makejail build examples/nginx.rkt          # dry-run 既定
raco makejail build examples/nginx.rkt --dry-run

# FreeBSD で実実行
raco makejail build examples/nginx.rkt --apply
raco makejail destroy examples/nginx.rkt --apply

# SSH（リモートに makejail パッケージが必要）
raco makejail build examples/nginx.rkt --apply root@freebsd.local
```

## ディレクトリ

```
main.rkt                 #lang / AST / plan->effects
lang/reader.rkt
raco.rkt                 # plan|build|start|stop|destroy
runtime/executor.rkt     # dry-run + FreeBSD apply（VNET 凍結）
examples/nginx.rkt
examples/nginx-thin.rkt
examples/templates/nginx.conf
test/dsl-test.rkt
```

## 0.1 (Gemini) から変わったこと

| 削除・凍結 | 採用・追加 |
|------------|------------|
| 必須 VNET epair パイプライン | `plan->effects` + **dry-run 既定** |
| jail-spec 巨大マクロのみ | Grok 風トップレベル `(from thin …)` 等 |
| expose が「あるフリ」 | net-* は TODO と明示 |
| | phase: build/start/stop/destroy |
| | zfs from を当面の実用経路に |

流用: prefab AST、raco エントリ、SSH で plan を `write` する発想、BSD-2-Clause、copy インライン化。

## テスト

```bash
raco test test/dsl-test.rkt
```

## 未実装（意図的）

- thin jail の release 取得と nullfs base の完全自動化  
- pf NAT / port expose の実体  
- VNET（Issue #1 で凍結）  
- `#lang jail/stack` / template  
- ARG のコンパイル時必須チェック強化  
- INCLUDE / STAGE 分割の本格化  

## クレジット

- 0.1 スケッチ: Gemini  
- MVP 方向・工程観: Grok  
- LOP 物差し: [Beautiful Racket](https://beautifulracket.com/introduction.html)  
- pivot レビュー: [Issue #1](https://github.com/bluehive/my-makejail-lop/issues/1)  
