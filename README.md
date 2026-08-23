# makejail — FreeBSD Jail Automation DSL in Racket

Racket の言語指向プログラミング（**LOP**）に基づく、FreeBSD Jail 構築・自動化のためのドメイン固有言語（DSL）です。

| 項目 | 内容 |
|------|------|
| リポジトリ | `bluehive/my-makejail-lop` |
| コレクション名 | `makejail`（`#lang makejail` / `raco makejail`） |
| ライセンス | **BSD-2-Clause** |
| 設計・仕様支援 | Gemini |
| 公開 | Public |

> **注意**: ランタイム（`runtime/executor.rkt`）は FreeBSD 上の root 相当権限と ZFS / jail / VNET を前提とします。Linux ホストでは DSL の構文テストのみ可能です。

## 目的

FreeBSD Jail に対するアプリケーションの **自動インストール・設定** を、宣言的 S 式で記述し、ローカルまたは SSH 経由で自動実行する。

## アーキテクチャ

| 層 | 内容 |
|----|------|
| フロントエンド (DSL) | S 式の `#lang makejail`。`syntax-parse` で静的に形を検証し、Prefab AST（`jail-plan` 等）を生成 |
| トランスポート | SSH 経由で AST を S 式としてリモートへ送信。設定テキストは `file:copy` 時にインライン化してバンドル |
| バックエンド (Runtime) | FreeBSD 上で `zfs clone`、動的 epair/bridge による VNET Jail、nullfs マウント、`jexec` を順に実行 |
| エラー制御 | コマンド失敗時は **ロールバックせず即時中断**。Jail は稼働状態で保持し、`/var/log/makejail-error.log` に失敗を記録 |

```
[ #lang makejail 定義 ]
        │  AST (prefab)
        ▼
[ raco makejail build ]
        │  ローカル or SSH + write
        ▼
[ runtime/executor ] ── zfs / ifconfig / jail / jexec
```

## 特徴

- 宣言的 S 式構文: `#lang makejail`
- ZFS 高速クローン: ベーススナップショットから展開
- 独立ネットワーク (VNET): epair / bridge の動的生成
- nullfs マウント（読み取り専用可）
- 失敗時も Jail を残し、ログで原因調査可能
- SSH 経由のリモート構築（AST シリアライズ）

## 構文一覧

| 構文 | 説明 |
|------|------|
| `(jail-spec name ...)` | Jail 定義のルートフォーム |
| `#:from "dataset@snap"` | クローン元 ZFS スナップショット |
| `#:dataset "dataset"` | 作成する ZFS データセット |
| `#:network (vnet #:bridge ... #:ip4 ... #:gw ...)` | VNET 構成 |
| `#:mounts ((mount host dst [#:readonly? #t]) ...)` | nullfs マウント |
| `#:expose (80 443)` | 公開ポート（文書・表示用） |
| `(pkg:install ...)` | `pkg install -y` |
| `(sysrc:set key val)` | `sysrc` |
| `(service:start name)` | `service <name> start` |
| `(file:copy src dst)` | ホスト上テキストを Jail 内へ配置 |
| `(exec:run cmd args...)` | 任意コマンド |

## ディレクトリ

```
my-makejail-lop/
├── LICENSE                 # BSD-2-Clause
├── README.md
├── info.rkt
├── main.rkt                # DSL / AST
├── raco.rkt                # raco makejail CLI
├── lang/reader.rkt         # #lang makejail
├── runtime/executor.rkt    # FreeBSD 実行系
├── test/dsl-test.rkt
└── examples/
    ├── web.rkt
    └── templates/nginx.conf
```

## インストールと利用

```bash
# 1. パッケージのリンクインストール
cd /path/to/my-makejail-lop
raco pkg install --link .

# 2. DSL テスト（AST 生成）
raco test -l makejail/test/dsl-test
# または
raco test test/dsl-test.rkt

# 3. ビルド（ローカル FreeBSD / または SSH 先）
raco makejail build examples/web.rkt
raco makejail build examples/web.rkt root@freebsd-server.local

# 4. 破棄
raco makejail destroy examples/web.rkt
raco makejail destroy examples/web.rkt root@freebsd-server.local
```

リモート側には `makejail` パッケージ（少なくとも `makejail/runtime/executor`）と Racket が必要です。

## 仕様メモ（0.1.0）

- 失敗時 **ロールバックなし**（意図的）。壊れた中間状態の jail を残してデバッグする。
- `expose` は現状ドキュメント／表示用。pf/ipfw ルール自動生成は未実装。
- `zfs:clone` フォームは予約・スタブ。実際のクローンは executor が `#:from` / `#:dataset` から行う。
- `when:step` / build-arg は STUB（将来拡張）。

## 関連プロジェクト

- FreeBSD Handbook JA: https://github.com/bluehive/my-freebsd-handbk-jp  
  （Jail / Service Jails / appjail-ephemeral メモ）

## クレジット

- 設計・仕様の原案支援: **Gemini**
- リポジトリ整備・公開: bluehive (Hiroki Kato) / Hermes
