# stack-calc — `#lang` のスタック計算機

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 場所: [`artifacts/stack-calc/`](https://github.com/bluehive/my-makejail-lop/tree/main/artifacts/stack-calc)  
> 関連: [lop-and-macros](lop-and-macros) · [creating-languages-in-racket](creating-languages-in-racket)

**`#lang` の語彙であり、関数ライブラリではありません。**  
関数を並べたライブラリではなく、**数字と語だけが文になる言語**です。

---

## 置き場所

| パス | 役割 |
|------|------|
| `artifacts/stack-calc/stack-calc.rkt` | 言語本体 |
| `artifacts/stack-calc/example.rkt` | 使い方 |

## 実行

```bash
cd artifacts/stack-calc
racket example.rkt
```

---

## 使い方（後置だけ）

```racket
#lang s-exp "stack-calc.rkt"
3 4 +          ; [7]
5 *            ; [35]
10 swap /      ; [3.5]
peek
```

`(3 + 4)` も `(+ 3 4)` も **言語にありません**。`#%app` が適用を拒否します。

---

## 語彙

| 語 | 意味 |
|----|------|
| 数字 | 積む |
| `+` `-` `*` `/` | 2個取って結果を積む |
| `neg` | 1個の符号反転 |
| `dup` `drop` `swap` `over` `clear` | スタック操作 |
| `print` | 頂点を出して捨てる |
| `peek` | 頂点を出す（残す） |
| `show` | 底→頂点で表示 |

モジュールが終わると残りのスタックを `stack: …` と出します。

---

## 言語側の要点

利用者プログラムには **`require` も `define` もありません**。

| フック | 役割 |
|--------|------|
| `#%datum` | 数字だけを `push!` にする |
| `#%app` | 括弧適用を構文エラーにする |
| `#%top` | 未知の語を構文エラーにする |
| `+` などは **識別子マクロ**（裸の `+` で実行、`(+ 1 2)` は構文エラー）。  
実装の算術は Racket の `+` をそのまま export せず、`r+` に退避しています。

```racket
(define-stack-word + (apply-binop r+))
```

ここが [lop-and-macros](lop-and-macros) の「**マクロはコンパイラに語彙を足す**」と同じ層です。計算そのものは実行時のリスト `the-stack` です。

---

## 中置の例を後置にする

`(1 + 2) * (3 - 4)` の後置:

```racket
clear
1 2 +
3 4 -
*
print
```

結果は `-3`、そのあとスタックは空です。

---

## makejail との対応

| stack-calc | makejail |
|------------|----------|
| 数字・語だけ受理 | jail 語彙だけ受理（agent） |
| `#%app` で適用禁止 | agent で `cmd` / host 禁止 |
| 0引数マクロの演算子 | `from` / `name` マクロ + 関数語彙 |
| 終了時に stack 表示 | `current-plan` を export |

両方とも「**パッケージを require する**」のではなく「**ファイルの言語を替える**」実験です。

---

## 関連

- [lop-and-macros](lop-and-macros)  
- [creating-languages-in-racket](creating-languages-in-racket)  
- [Overview](Overview)  

- [beautiful-racket-stacker](beautiful-racket-stacker)

- [dsl-testing](dsl-testing)
