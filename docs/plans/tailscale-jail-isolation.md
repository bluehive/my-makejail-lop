# 計画: Tailscale を FreeBSD jail に隔離し Muse と接続する

| 項目 | 内容 |
|------|------|
| 状態 | **計画のみ**（実装・`--apply` なし） |
| 対象ホスト | `192.168.0.5` · FreeBSD 15.1-RELEASE-p3 · hostname 表示 `@[]\/` |
| 関連リポ | 本リポジトリ `bluehive/my-makejail-lop` |
| 外部エージェント | Muse（Tailscale 端末名 `muse` · tailnet `goalwill@gmail.com`） |
| 作成日 | 2026-11-03（Asia/Tokyo） |

## 1. 結論（希望の読み）

- **やりたいこと:** VPN（Tailscale）上の Muse とホームの FreeBSD を繋ぐ。ただし Muse にホスト全体の権限は渡さない。
- **手段:** ホスト直下に `pkg install tailscale` するのではなく、**jail 内だけ**に Tailscale を入れ、Muse からはその jail の Tailscale アドレス／名前にだけ届くようにする。
- **本 PR の範囲:** 解析結果と段階計画・DSL 側ギャップの明示。**まだ jail 作成も `tailscale up` も行わない。**

## 2. 現状解析（根拠）

### 2.1 ホスト（2026-11-03 ThinkPad → `ssh freebsd-home` 実測）

| 観測 | 値 |
|------|-----|
| OS | FreeBSD 15.1-RELEASE-p3 amd64 |
| LAN | `re0` = `192.168.0.5/24` · gateway `192.168.0.1` |
| Bastille | `bastille_enable=YES` · `bastille-1.4.4` |
| AppJail | `appjail_enable=YES` · `appjail-4.13.0`（併存） |
| 既存 jail | `dokuwiki`（ACTIVE · `192.168.0.50`）· `samba` · `wireguard`（ZFS 上に root あり） |
| インターフェース | `bastille0`（lo1 改名）· `jailbridge`（`10.10.10.1/24`）· epair `e0a/b_samba` · `e0a/b_wireguard` |
| Tailscale | **未インストール**（`pkg info` に無し） |
| makejail | ホスト上での適用状況は本計画では未確認（DSL リポ側のギャップが主眼） |

→ ホストはすでに **Bastille による VNET/epair 運用**に慣れている。VPN 系の先例として `wireguard` jail が存在する。

### 2.2 Muse / Tailscale（ユーザー提供情報）

- Muse 側は端末名 `muse` で `goalwill@gmail.com` tailnet へのログイン／参加申請済み。
- ユーザー承認リンクあり（有効期限約 5 日）。**ホスト／jail 側の作業とは独立した承認ステップ。**
- Muse 側の方針メモ: SSH は通常の OpenSSH（`sshd`）。FreeBSD での `tailscale up --ssh` は未確認のため寄せない。鍵は従来どおり利用者側。

### 2.3 素のインストール手順（ユーザー提示・ホスト直下）との差分

提示コマンド:

```sh
pkg install tailscale
sysrc tailscaled_enable="YES"
service tailscaled start
tailscale up
```

これは **ホスト userspace に Tailscale を載せる**手順。成功すると Muse はホスト全体（少なくともホストの `sshd` や LAN 経路）に近くなりやすく、**「Muse に全権限を渡したくない」希望と衝突しやすい。**

希望どおりにするなら、同コマンド列は **jail 内（または `pkg -j <jail>` + `jexec`）に閉じる**必要がある。

### 2.4 FreeBSD jail + Tailscale の技術要件（公開知見）

代表例: [How to run tailscale in a FreeBSD jail](https://rpassos.net/articles/how-to-run-tailscale-in-a-freebsd-jail.html) · FreeBSD Forums（tun/bpf · VNET）。

| 要件 | 理由 |
|------|------|
| **VNET jail** | 自前のネットワークスタックと `tun` が必要。IP 共有の classic jail では困難 |
| **devfs で `tun*`（必要なら `bpf*`）を unhide** | `tailscaled` が TUN を作れないと起動／`up` が失敗する |
| **bridge / epair（または Bastille `-V`）** | jail が LAN または専用セグメントへ出る |
| **jail 内で `tailscaled` + `tailscale up`** | ノードは jail 単位。100.x は jail のもの |
| **ホストに Tailscale を入れない（本希望）** | Muse の到達面を jail に限定しやすい |

非推奨ショートカット: `--tun=userspace-networking` は VNET なしで動く場合があるが、プロキシ前提になり Muse→任意サービスが壊れやすい。**本計画では第一候補にしない。**

### 2.5 makejail（本リポ）とのギャップ

| 事実 | 意味 |
|------|------|
| README / Issue #1 | **VNET パイプラインは凍結**（`TODO virtualnet … (frozen per Issue #1)`） |
| `(option network vnet-default)` | 例・契約上は書けるが、実行器は **実 VNET を組まない** |
| P02 agent 契約 | agent は `network host` 禁止・`--apply` 禁止。人間が apply |
| 種族フォーム | `wiki-site` 等はあるが **`tailscale-*` 種族は未定義** |

→ **「今すぐ `raco makejail build … --apply` で Tailscale jail」は不可能。**  
計画は (A) Bastille で先行実体化 → 後から makejail に落とす、か (B) makejail の VNET 凍結解除を先にやる、の二系統になる。

## 3. 隔離モデル（目標アーキテクチャ）

```
[ Muse (tailnet) ]
        |
   Tailscale 100.x
        |
[ FreeBSD jail: muse-gw ]  ← tailscaled + sshd（鍵は Muse 用に限定）
        |
   epair / VNET
        |
[ host 192.168.0.5 ]  ← Tailscale なし（原則）
   ├─ dokuwiki jail 192.168.0.50
   ├─ samba / wireguard jails
   └─ ホスト sshd（LAN / 既存鍵のみ。Muse からは非公開が望ましい）
```

**権限の切り方（希望の具体化）:**

1. Muse が持てるのは **jail `muse-gw` のシェル／明示公開ポートだけ**。
2. ホストの `jexec`・ZFS・他 jail へは、jail から出ない限り届かない（追加マウントや `allow.*` を与えない）。
3. 他 LAN サービスへ Muse から行きたい場合は、**明示的な許可（jail 内プロキシ、限定 `pf`、または別途承認）**が必要。デフォルトは閉じる。
4. Tailscale の **subnet router / exit node は初期オフ**（オンにすると Muse の到達範囲が一気に広がる）。

## 4. 段階計画

### Phase 0 — 承認・方針確定（人間・本 PR）

1. Tailscale コンソールで **`muse` を承認**（既存リンク）。
2. 本計画の隔離モデルと「ホストに Tailscale を載せない」を承認。
3. 実装パスを選ぶ（下記 Q1）。

### Phase 1 — 実体の最小パイロット（ホスト操作・makejail 外でも可）

目標: **動く VNET jail 1 個**に Tailscale を入れ、Muse から `sshd` 到達確認まで。

1. Bastille（推奨・既存運用に乗る）または手書き `jail.conf` で VNET jail `muse-gw` を作成。  
   - LAN 側 IP 例: `192.168.0.x/24` on `re0` bridge、または既存 `jailbridge` 方針に合わせる（要決定）。
2. host: `pkg -j muse-gw install tailscale`（または jail 内 pkg）。
3. jail: `sysrc tailscaled_enable=YES` · `service tailscaled start` · `tailscale up`（ブラウザ承認・タグ付け）。
4. jail: `sshd` 有効 · Muse 用の **専用 authorized_keys のみ**（ホスト鍵を流用しない）。
5. host: `/etc/devfs.rules` に tun/bpf 用 ruleset を追加し jail に紐付け（Bastille なら ruleset 番号の流儀に合わせる）。
6. 検証: jail 内 `tailscale ip -4` → Muse からその 100.x:22 へ到達テスト（Muse 側確認ダイアログあり）。
7. **ホストに `security/tailscale` が入っていないこと**を再確認。

**成功条件:** Muse → jail の SSH のみ成功。ホスト `192.168.0.5:22` へは Muse 経路で届かない（または意図的に拒否）。

### Phase 2 — makejail への取り込み（本リポ）

1. Issue: **VNET 凍結の部分解除**（Tailscale gateway 用途に限定した最小 epair/bridge 効果列）か、「Bastille テンプレ呼び出し」効果の設計。
2. 種族フォーム案: `(tailscale-gateway)` または `(muse-gateway)`  
   - 展開: `pkg tailscale` · `sysrc tailscaled` · `service` ·（人間ステップの `tailscale up` は `human-cmd` または手順書）
3. 例: `examples/muse-tailscale-gateway.rkt` + `raco makejail plan/check` が通るところまで。
4. P02: agent は穴埋めのみ。`--apply` と初回 `tailscale up` は人間。

### Phase 3 — 運用

1. jail 再起動後も `tailscaled` 自動起動。
2. ACL: Tailscale ACL で `muse` → `tag:muse-gw` の 22 のみ、など。
3. 文書: 本ファイルを「実施記録」節で更新。ホスト直下インストール手順は **非推奨** と明記。

## 5. リスクと非目標

| リスク | 緩和 |
|--------|------|
| ホストに Tailscale を入れてしまう | Phase 1 チェックリストで禁止 |
| subnet router を安易に有効化 | 初期オフ・別 PR |
| makejail だけで完結しようとして頓挫 | Phase 1 は Bastille 先行を許容 |
| `tailscale up --ssh` | Muse 方針どおり使わない |
| jail から host への抜け道（nullfs / allow.mount） | 与えない |

**非目標（当面）:** Muse から dokuwiki/samba を直接触ること、exit node、ホスト管理 SSH の Tailscale 化。

## 6. 推奨パス（意見）

ホストがすでに Bastille + VNET なので、**Phase 1 は Bastille で `muse-gw` を切り、成功後に makejail へ「再現可能な記述」を戻す**のが最短。  
makejail の VNET 凍結解除を先にやるのは正しい長期投資だが、Muse 接続のブロッカーになる。

## 7. 本 PR に含めるもの / 含めないもの

**含む:** 本計画書のみ。  
**含めない:** 実 jail 作成、pkg、sysrc、service、`tailscale up`、ACL 変更、実行器の VNET 実装。
