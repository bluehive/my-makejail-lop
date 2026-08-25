# makejail 0.4 仕様（承認済）

正本: [Issue #9](https://github.com/bluehive/my-makejail-lop/issues/9)（ユーザー承認 2026-08-25）

## 三軸

| 軸 | 表面 | 実装 |
|----|------|------|
| 個体 | `(instance #:name #:hostname #:data-host #:ip #:dataset)` + `(arg …)` | `mj-instance` → assemble で正規化 |
| 種族 | `(wiki-site …)` | 展開表 `family/dokuwiki.rkt` |
| 運用 | agent 受理 | `plan-validate!`（cmd / host ネット禁止） |

## 展開は言語側

- hostname → `template-subst`（sed 禁止）
- dataset 未指定 → `zroot/jails/${name}` 導出
- 二重 hostname（スロットと wiki-site リテラル矛盾）→ エラー

## host / in-jail

表面セクションは **設けない**（jail 個体計画が自明の前提）。

## 例

```bash
raco makejail check examples/dokuwiki-caddy.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data
```
