# bsd-apps と makejail — 比較レクチャー

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 対象:
> - [bluehive/my-makejail-lop](https://github.com/bluehive/my-makejail-lop)（`#lang makejail` / LOP）
> - [tschettervictor/bsd-apps](https://github.com/tschettervictor/bsd-apps)（jail 向けシェルインストール集）

[makejail Overview](Overview) で LOP の読み方を見たあと、ここでは **運用知見の宝庫である bsd-apps** と突き合わせます。

---

## 1. bsd-apps リポジトリの概要と設計思想

このリポジトリは、「**シェルスクリプトを使って FreeBSD jail 内にアプリケーションをインストールする**」ためのコレクションです。

| 特徴 | 内容 |
|------|------|
| スクリプト駆動 | 各アプリは `xxx-install.sh` として提供 |
| 変数による設定 | 先頭で変数定義 → ユーザーが編集して実行 |
| マウントポイント | データ永続化のためホスト側を jail 内にマウント |
| jail プロパティ | 例: `allow.sysvipc` などアプリ依存 |
| 再インストール耐性 | データを外に出せば jail 破棄後も再構築可能 |

中心思想は **手続き型の運用レシピ** であり、宣言的 DSL ではない。

---

## 2. Caddy のスクリプトを詳細に読む

例: `caddy/caddy-install.sh`（bsd-apps 側の実装パターン）。

### 2.1 変数定義（ユーザーが設定する箇所）

```sh
HOST_NAME=""              # FQDN（必須）
NO_CERT=0                 # HTTPのみ（0=無効）
SELFSIGNED_CERT=0         # 自己署名
STANDALONE_CERT=0         # Let's Encrypt（スタンドアロン）
DNS_CERT=0                # DNS-01
DNS_PLUGIN=""             # 例: cloudflare
DNS_TOKEN=""
CERT_EMAIL=""
```

**1 つの証明書オプションだけを有効（1）にする** 運用。

### 2.2 依存パッケージ

```sh
pkg install -y git-lite go openssl
```

Go で Caddy をソースビルドするため `go` と `git-lite` が必要。

### 2.3 Caddy のビルド（xcaddy）

```sh
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
cp /root/go/bin/xcaddy /usr/local/bin/xcaddy

if [ ${DNS_CERT} -eq 1 ]; then
    xcaddy build --output /usr/local/bin/caddy \
        --with github.com/caddy-dns/"${DNS_PLUGIN}"
else
    xcaddy build --output /usr/local/bin/caddy
fi
```

DNS-01 のときは対応プラグインを **ビルド時に組み込む**。

### 2.4 自己署名証明書

```sh
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=${HOST_NAME}" \
    -keyout /tmp/privkey.pem -out /tmp/fullchain.pem
# → /usr/local/etc/pki/tls/... へ配置
```

### 2.5 Caddyfile の取得と置換

証明書モードごとにテンプレートを `fetch` し、`sed` でホスト名・トークン等を埋める。

### 2.6 サービス

```sh
sysrc caddy_config="/usr/local/www/Caddyfile"
sysrc caddy_enable="YES"
service caddy start
```

### 2.7 このスクリプトからわかること

| 観点 | 内容 |
|------|------|
| マウント | **none** — 設定もデータも jail 内完結（Caddy 単体の場合） |
| jail プロパティ | **none** — 特別指定なし |
| 柔軟性 | 証明書モード 4 種 |
| 運用注意 | ステージング証明書後は本番化スクリプト（例: remove-staging） |

---

## 3. makejail アプローチとの比較

| 比較軸 | bsd-apps（シェル） | makejail（DSL） |
|--------|-------------------|-----------------|
| 抽象化 | 手続き型（どうやるか） | 宣言型（何をしたいか） |
| 学習コスト | sh が読めればよい | 独自構文 |
| 可読性 | 処理の流れがそのまま | 意図が構文に載る |
| 再利用 | コピペ＆変数編集 | マクロ・モジュール化の余地 |
| エラー処理 | シェル任せ | Racket 側で拡張しやすい |
| dry-run | 独自実装が必要 | **標準**（`plan` / `--dry-run`） |
| リモート | 別途 | **SSH + plan 送信**（MVP） |

### 3.1 コード比較（概念）

**bsd-apps スタイル（Caddy）**

```sh
HOST_NAME="web.example.com"
STANDALONE_CERT=1
CERT_EMAIL="admin@example.com"
sh caddy-install.sh
```

**makejail スタイル（Caddy・理想形のスケッチ）**

```racket
#lang makejail
(name "caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/caddy")
(option network host)

(arg host-name "web.example.com")
(arg standalone-cert #t)
(arg cert-email "admin@example.com")

(pkg "git-lite" "go" "openssl")
(copy "files/Caddyfile" "/usr/local/www/Caddyfile")
(sysrc "caddy_enable" "YES")
(service caddy start)
```

※ xcaddy ビルドや証明書分岐は、現状 MVP では `(cmd ...)` や将来の専用構文が必要。

### 3.2 bsd-apps から学べる makejail 改善ポイント

| アイデア | 例（将来構文の候補） |
|----------|----------------------|
| 証明書モード | `(cert-mode standalone)` ; dns / selfsigned / none |
| DNS 設定の束 | `(dns-config #:plugin "cloudflare" #:token "…" #:email "…")` |
| リモートテンプレ | `(fetch "https://…/Caddyfile" "/usr/local/www/Caddyfile")` |

LOP 的には、bsd-apps の **変数群＝ドメインの語彙候補** である。

---

## 4. DokuWiki と Samba（bsd-apps に無い場合の考察）

リポジトリに DokuWiki / Samba が無くても、**同じパターン**でスクリプトが組める、という想定。

### 4.1 DokuWiki（想定スクリプト構造）

```sh
# 変数
DB_PASSWORD=""
ADMIN_PASSWORD=""
FQDN=""

# パッケージ（例・版は環境で変わる）
pkg install -y apache24 mod_php81 php81-{gd,xml,ctype,zlib,curl,session,mbstring,iconv,tokenizer} \
  mariadb106-server dokuwiki

sysrc apache24_enable="YES"
sysrc mysql_enable="YES"

mysql_install_db
service mysql-server start
mysql -e "CREATE DATABASE dokuwiki; GRANT ALL ON dokuwiki.* TO 'dokuwiki'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"

cp /usr/local/share/dokuwiki/conf/local.php.sample \
   /usr/local/share/dokuwiki/conf/local.php
# local.php を編集（DB 等）

# マウント（データ永続化）
# ホスト /mnt/dokuwiki/data → jail /usr/local/share/dokuwiki/data
# ホスト /mnt/dokuwiki/conf → jail .../conf
```

**makejail / thin-vnet との接続**（[Issue #3](https://github.com/bluehive/my-makejail-lop/issues/3)）:

- 量産単位は **同一 jail 内 Caddy + DokuWiki**（ホスト分離 Caddy ではない）。
- DB を同じ jail に載せるか、別 jail にするかは設計分岐（上の想定は **同居型**）。
- `volume` で data/conf をホスト側に出すのが bsd-apps 流の再インストール耐性。

### 4.2 Samba（想定スクリプト構造）

```sh
WORKGROUP="WORKGROUP"
SERVER_STRING="Samba Server"
SHARE_PATH="/mnt/share"
SAMBA_USER="smbuser"
SAMBA_PASSWORD=""

pkg install -y samba416
# smb4.conf 生成、pw useradd、pdbedit
sysrc samba_server_enable="YES"
service samba_server start
# マウント: ホスト共有パス → SHARE_PATH
```

jail では **sysvipc / raw sockets** など追加プロパティが要る場合がある（bsd-apps 他アプリと同様、アプリごとに調査）。

---

## 5. 統合分析：ベストプラクティス

### 5.1 得意領域

| シナリオ | 推奨 | 理由 |
|----------|------|------|
| 使い捨て実験 | bsd-apps 風 | 手軽・修正容易 |
| チーム共有の意図 | makejail | 宣言的で意図が残る |
| CI / リモート | makejail | dry-run・SSH が土台にある |
| 既存 sh の移行 | bsd-apps 風 or `(cmd …)` | 資産を捨てない |

### 5.2 ハイブリッド

makejail の `(cmd ...)` で bsd-apps スクリプトを呼ぶ例:

```racket
#lang makejail
(name "caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/caddy")

(cmd "fetch" "-o" "/tmp/caddy-install.sh"
     "https://raw.githubusercontent.com/tschettervictor/bsd-apps/master/caddy/caddy-install.sh")
(cmd "chmod" "+x" "/tmp/caddy-install.sh")
(cmd "/bin/sh" "-c"
     "HOST_NAME=web.example.com STANDALONE_CERT=1 CERT_EMAIL=admin@example.com /tmp/caddy-install.sh")
```

**注意**: この場合、構文チェック・段階・dry-run の恩恵が **薄くなる**（中身は巨大な黒箱コマンド）。

---

## 6. まとめ：両方から学ぶ LOP の本質

| リポジトリ | アプローチ | 学び |
|------------|------------|------|
| my-makejail-lop | `#lang makejail` | ドメインを **言語化**する理想形（構文→AST→効果） |
| bsd-apps | シェル集 | **運用知見**（変数・マウント・jail プロパティ・証明書モード） |

合わせて読むと得られるもの:

1. **抽象化の方向** — bsd-apps のノウハウをどの構文に昇華するか  
2. **実用と厳密さのバランス** — sh の柔軟さと DSL の検査  
3. **ドメインモデルの発見** — 変数群＝次の DSL 候補  

次の makejail 改善案の例: **証明書モード構文**、**DNS 設定構文**、DokuWiki 量産向け **volume +（将来）thin-vnet**。

> LOP の本質は「まずドメインをよく観察し、それを言語の形にする」こと。  
> 両方のリポジトリは、そのための良い教材になる。

---

## 関連 Wiki

- [Overview](Overview) — makejail と LOP  
- [使い方](使い方) — CLI と構文表  
- [Issue #3 thin-vnet](https://github.com/bluehive/my-makejail-lop/issues/3) — 同一 jail 内 Caddy+DokuWiki 量産のネット仕様  
