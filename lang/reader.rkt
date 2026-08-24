#lang s-exp syntax/module-reader
;; =============================================================================
;; lang/reader.rkt — `#lang makejail` の入口（言語リーダー）
;;
;; 【このファイルの役割】
;;   利用者がファイル先頭に
;;     #lang makejail
;;   と書いたとき、Racket はコレクション makejail の lang/reader.rkt を探す。
;;   ここで「どのモジュールを言語本体として読むか」を宣言する。
;;
;; 【1行目】#lang s-exp syntax/module-reader
;;   - s-exp … 表面構文は通常の S 式（カッコ付きリスト）のまま
;;   - syntax/module-reader … 「次の行のモジュールを #lang 言語にする」定番テンプレ
;;   独自の非 S 式構文（Flatt の txtadv-reader のようなもの）はまだ使っていない。
;;
;; 【2行目】makejail
;;   言語の中身はコレクション名 makejail（= リポジトリ直下の main.rkt 等）。
;;   main.rkt が provide する #%module-begin（→ mj-module-begin）や
;;   name / from / pkg などが、そのファイルのトップレベル語彙になる。
;;
;; 【LOP との関係】（Wiki: lop-and-macros / stack-calc）
;;   require して関数を呼ぶ「ライブラリ」ではなく、
;;   「このファイル全体の言語」を差し替える段がここ。
;;   Flatt の階段で言う「モジュール言語（#lang）」の入口。
;;
;; 【次に読むファイル】
;;   main.rkt … 語彙・AST・plan-validate! / plan->effects
;;   runtime/executor.rkt … 効果列の dry-run / 実実行
;; =============================================================================
makejail
