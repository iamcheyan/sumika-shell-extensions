# オフライン翻訳モデル調査

調査日: 2026-07-30
対象: Sumika Shell Voice extension の中国語音声認識結果を英語または日本語へ翻訳する処理

## 結論

現時点で Sumika の品質要件に対して実機検証へ進める価値が最も高い
オフライン候補は **Google TranslateGemma** である。

推奨する検証順序は次のとおり。

1. **TranslateGemma 12B** を速度と品質の基準候補として測定する。
2. **TranslateGemma 27B** を品質優先候補として測定する。
3. 現行クラウド翻訳と同じ実音声由来データでブラインド比較する。
4. 品質と遅延の合格基準を満たした場合だけ、任意のローカル
   バックエンドとして Sumika に統合する。

4B は実行しやすいが、今回の「オフラインでも翻訳品質を妥協しない」
という目的では第一候補にしない。27B は最も高品質である可能性が高い
一方、現在の Apple M1 Max + Asahi Linux 環境で実用的な速度になるかは
公開ベンチマークから断定できない。したがって、モデルを組み込む前に
12B と 27B の両方を実機で測る必要がある。

この文書は調査と導入判定計画であり、TranslateGemma のダウンロードや
Sumika への統合が完了したことを示すものではない。

## なぜ TranslateGemma なのか

TranslateGemma は一般用途 LLM に翻訳を指示するだけのモデルではない。
Gemma 3 の 4B、12B、27B を基に、Google Translate Research Team が
翻訳用データで追加学習したモデル群である。

公式技術報告による学習は二段階である。

1. 人手翻訳と Gemini が生成した高品質な対訳データによる
   Supervised Fine-Tuning。
2. MetricX-QE と AutoMQM などの評価器を用いた Reinforcement Learning。

一般モデルより翻訳専用モデルを優先する理由は、短い入力だけでなく、
固有名詞、数値、文体、語順、訳文の自然さを翻訳タスクとして直接
最適化しているためである。Sumika の用途では長い推論や会話能力より、
短い発話を余計な説明なしで忠実に訳す能力が重要になる。

Google は 55 言語を主要な評価対象としており、さらに約500の追加
言語ペアを学習対象としている。技術報告の非英語ペア一覧には
**Chinese (zh-CN) → Japanese (ja)** が明記されている。また学習データ
分布図では Japanese–Chinese が SFT の 7.6%、RL の 9.3% を占める。

ただし、ここには重要な制限がある。公開された WMT24++ の詳細な
言語別表は主に英語を起点とする評価であり、中国語→日本語について
同じ粒度の人手評価値は公開されていない。中国語→日本語が学習対象
であることは確認できるが、Sumika の実際の発話でクラウドモデルを
上回るとは資料だけでは証明できない。

## 公式ベンチマークの読み方

WMT24++ 全体の自動評価は次のとおり。

| モデル | MetricX（低いほど良い） | COMET22（高いほど良い） |
|---|---:|---:|
| TranslateGemma 4B | 5.32 | 80.1 |
| TranslateGemma 12B | 3.60 | 83.5 |
| TranslateGemma 27B | 3.09 | 84.4 |

この結果から言えることは次の範囲に限られる。

- 同じ TranslateGemma 系列では、平均品質は 27B、12B、4B の順。
- 12B は翻訳調整前の Gemma 3 27B を平均 MetricX で上回る。
- 4B も翻訳調整の効果は大きいが、12B と 27B には明確な差がある。

一方、この表は中国語音声認識結果→日本語だけを測ったものではない。
SenseVoice 特有の句読点、口語、省略、誤認識を含む入力に対する品質は、
Sumika 自身のデータセットで別途評価しなければならない。

## モデルサイズの選択

### TranslateGemma 4B

Ollama 公開モデルのダウンロードサイズは約 3.3GB。端末や省メモリ環境
には適するが、品質最優先の本件では比較用の下限として扱う。

想定用途:

- 低消費メモリを最優先する端末。
- 12B が速度要件を満たさない場合の参考比較。
- 品質低下を許容できる補助機能。

今回の本命にはしない。

### TranslateGemma 12B

Ollama 公開モデルのダウンロードサイズは約 8.1GB。Google は consumer
laptop 向けのサイズとして位置づけている。品質と遅延のバランスを
測る最初の候補にする。

期待:

- 27B より初回ロードと生成が軽い。
- 4B より固有名詞、長めの発話、自然な日本語で有利である可能性が高い。
- 常駐サーバー化すればモデルロード時間を入力ごとに支払わずに済む。

### TranslateGemma 27B

Ollama 公開モデルのダウンロードサイズは約 17GB。公式平均指標では
3サイズ中で最良であり、品質優先の最終候補である。

注意:

- Google の公式説明は 27B の代表的な実行先として単一 H100 GPU または
  TPU を挙げており、Asahi Linux 上の M1 Max での速度保証ではない。
- 量子化後は本機の 64GB 統合メモリに収まる見込みだが、
  「収まる」と「音声入力として待てる速度」は別問題である。
- 低ビット量子化は翻訳品質を損なう可能性があるため、Q4 だけで結論を
  出さず、可能なら Q6_K または Q8 と比較する。

## このマシンの現状

2026-07-30 に確認した実機状態:

| 項目 | 確認結果 |
|---|---|
| OS | Asahi Linux / Fedora 44 / aarch64 |
| SoC / GPU | Apple M1 Max / Honeykrisp Vulkan driver |
| CPU | 10 logical CPUs |
| RAM | 62GiB、確認時 available 約43GiB |
| Swap | 8GiB |
| Vulkan | Apple M1 Max を物理 GPU として認識 |
| Vulkan FP16 / Int8 shader | 利用可能 |
| Vulkan integer dot product acceleration | driver report では false |
| Ollama | 0.30.10 |

現在の `/usr/local/lib/ollama` には ARM CPU backend と CUDA backend が
あるが、`libggml-vulkan.so` は見つからなかった。このインストールの
ままでは、Apple GPU が Vulkan から見えていても Ollama が CPU 推論
だけになる可能性が高い。

そのため「Ollama がインストール済み」であることを GPU 推論の確認と
みなしてはいけない。モデル実行中のログ、プロセス情報、token/s を
確認し、実際に Honeykrisp/Vulkan backend が使用されていることを
証明する必要がある。

また Honeykrisp が FP16 と shader Int8 を公開していても、integer dot
product acceleration は false と報告されている。この条件で量子化
モデルがどの程度高速になるかは、実測なしに予測しない。

## 推奨する推論ランタイム

### 第一候補: llama.cpp + Vulkan

llama.cpp は公式に Vulkan backend、量子化、CPU+GPU hybrid inference、
OpenAI 互換 HTTP server を提供する。本機では次の理由で検証しやすい。

- Vulkan backend を明示的にビルド・選択できる。
- GPU layer、context、batch、thread 数を比較しやすい。
- `llama-server` を常駐させ、Sumika から HTTP で呼べる。
- 実際の prompt processing と generation の token/s を測れる。

検証時は、信頼できる配布元の GGUF を使用し、元モデル、量子化方式、
ファイル checksum を記録する。コミュニティ変換 GGUF を使う場合は、
Google 公式 checkpoint そのものではない点を明記する。

### 第二候補: Vulkan backend 付き Ollama

Ollama 公式文書では Linux の追加 GPU 対応として Vulkan を案内して
いる。運用は簡単だが、現在のインストールには Vulkan backend がない
ため、対応パッケージまたは対応ビルドへ置き換えた上で確認する。

Ollama のモデル一覧は比較を始めるには便利であり、公開サイズは次の
とおり。

| tag | 公開サイズ |
|---|---:|
| `translategemma:4b` | 3.3GB |
| `translategemma:12b` | 8.1GB |
| `translategemma:27b` | 17GB |

ただし、簡単に起動できることだけを理由にランタイムを固定しない。
同一モデル・同一量子化・同一 prompt で llama.cpp と Ollama の
初回遅延、warm latency、token/s、GPU 使用を比較する。

## TranslateGemma 固有のプロンプト

現在の `bin/sumika-voice-translate` は、汎用 OpenAI 互換モデル向けに
system message と user message を分離している。TranslateGemma の
公式形式はこれと異なり、**単一の user message** を期待する。

中国語→日本語では次の形式を使用する。

```text
You are a professional Chinese (zh-CN) to Japanese (ja) translator. Your goal is to accurately convey the meaning and nuances of the original Chinese text while adhering to Japanese grammar, vocabulary, and cultural sensitivities.
Produce only the Japanese translation, without any additional explanations or commentary. Please translate the following Chinese text into Japanese:


{TEXT}
```

重要事項:

- system role を追加しない。
- 原文の前に空行を2行入れる。
- 言語名と BCP-47 に対応するコードを明示する。
- 返答には翻訳だけを要求する。
- モデル公式の chat template を通す。

英語を対象にする場合は `Japanese (ja)` を `English (en)` に置き換える
だけでなく、文中の言語名もすべて一致させる。

Sumika に統合する場合、現在の汎用 prompt を無条件に置き換えては
ならない。選択された provider/model が TranslateGemma のときだけ
専用 profile を使用し、既存クラウドモデルは現行 prompt を維持する。

## 速度を正しく測る

音声入力で感じる待ち時間は単純な API 応答時間ではない。

```text
録音停止
  → 最終 SenseVoice 認識
  → 翻訳要求の受付
  → prompt evaluation
  → 最初の翻訳 token
  → 翻訳完了
  → クリップボード設定
  → 貼り付け
```

最低限、次の値を分離して記録する。

| 指標 | 意味 |
|---|---|
| model load | プロセス開始からモデル利用可能まで |
| cold total | モデル未常駐状態の総時間 |
| warm TTFT | 常駐状態で要求送信から最初の token まで |
| warm total | 常駐状態で翻訳全文が完成するまで |
| prompt token/s | 入力処理速度 |
| generation token/s | 訳文生成速度 |
| end-to-paste | 録音停止から貼り付け完了まで |

各候補につき、短文・中文・長文を混ぜて少なくとも100件を測り、
p50、p95、最大値を残す。最初の1件だけ、または最短の定型文だけを
測って採用判断しない。

モデルは常駐させる。入力のたびにロードすると、モデル性能ではなく
起動時間を測ることになる。アイドル時に常駐を解除する設計にする場合も、
解除までの時間と再ロード時の UI 表示を別途設計する。

## 品質評価データセット

一般翻訳ベンチマークだけでなく、実際の SenseVoice 出力を保存した
評価セットを作る。秘密情報を含まない100件以上を用意し、次を含める。

- 1文の短い指示。
- 複数文を含む長めの発話。
- 中国語の口語、省略、言い直し。
- SenseVoice の句読点なし出力。
- 軽微な誤認識を含む出力。
- 人名、製品名、地名。
- 日付、時刻、金額、割合、バージョン番号。
- 丁寧語にすべき発話と、くだけた口調を維持すべき発話。
- 翻訳してはいけないコマンド、パス、識別子、コード断片。
- prompt injection に見える原文。

比較対象:

1. 現行クラウド翻訳。
2. TranslateGemma 12B。
3. TranslateGemma 27B。
4. 必要なら TranslateGemma 4B。

出力元を隠してブラインド評価し、次を採点する。

| 評価項目 | 観点 |
|---|---|
| 意味忠実度 | 情報の追加・欠落・反転がないか |
| 日本語自然さ | 語順、助詞、文体が自然か |
| 文体維持 | 丁寧さ、強さ、感情を保つか |
| 固有名詞 | 勝手な翻訳、脱落、別名化がないか |
| 数値 | 桁、単位、符号、時刻を壊さないか |
| ASR 耐性 | 不完全な中国語から勝手に意味を作らないか |
| 出力規約 | 説明、前置き、引用符を追加しないか |

## 採用ゲート

最初の検証では次を目安にする。これは公式値ではなく、Sumika の
入力体験を守るためのプロジェクト基準である。

- 現行クラウドと同等以上と判定された例が 85%以上。
- 意味を変える重大誤訳が 1%未満。
- 固有名詞または数値の誤りが 1%未満。
- 常駐時の翻訳完了 p50 が 1.5秒以下。
- 常駐時の翻訳完了 p95 が 3秒以下。
- 連続20回の翻訳で crash、空応答、説明文混入がない。
- GPU backend 使用時にデスクトップ操作と録音を著しく妨げない。

27B が品質基準を満たしても速度を満たさない場合は 12B を採用候補に
する。12B が速度を満たしても品質を満たさない場合は、4B へ下げず
クラウドを維持する。オフラインであること自体を品質より優先しない。

## Sumika へ統合する場合の設計

採用後も既存クラウド経路を削除せず、設定で選べる backend とする。

```text
SenseVoice final text
        │
        ├─ cloud/OpenCode-compatible backend
        │
        └─ local/TranslateGemma backend
                 └─ localhost Unix socket or HTTP server
```

ローカル backend が満たすべき条件:

- 外部ネットワークがなくても動作する。
- server の起動失敗、モデル未導入、OOM を通知できる。
- モデルのロード中と翻訳中を区別して表示する。
- timeout 時に原文を失わない。
- API key を要求・保存しない。
- 入力テキストをログへ無条件に残さない。
- provider 固有 prompt を1か所で管理する。
- 英語・日本語の target code を正しく切り替える。

### 投機翻訳との関係

現在の Voice extension は通常レーンと投機レーンの2本を持ち、
クラウド翻訳では先に成功した結果を採用できる。単一ローカル GPU に
同時に2本の生成を投げると、互いに遅くなりメモリも増える可能性がある。

ローカル backend では次の制御を推奨する。

1. 投機候補の原文が最終 SenseVoice 結果と完全一致した場合、
   その生成を継続して再利用する。
2. 一致しない場合は投機生成を cancel して最終原文で再開始する。
3. 同一 GPU 上で通常・投機の2生成を同時実行しない。
4. cancel が実際に計算を止めることを server 側でも確認する。
5. 投機結果を採用する安全条件は既存実装と同じ完全一致を維持する。

この点はクラウド版のヘッジ戦略をそのまま移植してはいけない部分である。

## 導入手順

### Phase 0: 変更前の保護

1. Voice extension とメインリポジトリを clean にする。
2. 現行クラウド翻訳の100件ベースラインを保存する。
3. 計測スクリプトと結果は extension の `docs/benchmarks/` に置く。
4. 音声や API key を Git に入れない。

### Phase 1: ランタイムだけ検証

1. llama.cpp を Vulkan 有効で別ディレクトリにビルドする。
2. `vulkaninfo` で Apple M1 Max を選択する。
3. 小さい既知モデルで GPU offload が実際に動くことを確認する。
4. CPU-only と Vulkan の token/s を比較する。
5. クラッシュ、表示破損、録音ノイズへの影響を確認する。

この段階では Sumika の実装を変更しない。

### Phase 2: 12B と 27B の比較

1. 同じ出所・同等量子化条件のモデルを用意する。
2. context と生成上限を音声入力用途に絞る。
3. 公式 prompt を使用する。
4. 100件以上で品質と warm latency を測る。
5. 量子化差が疑われる場合は Q4、Q6_K、Q8 を部分比較する。

### Phase 3: 独立したローカル adapter

1. 既存 `sumika-voice-translate` を直接壊さず adapter を追加する。
2. health check、model info、translate、cancel を定義する。
3. fixture から CLI 単体テストできるようにする。
4. timeout と server crash のフォールバックを検証する。

### Phase 4: UI と設定へ統合

1. TUI で `cloud` / `local` backend を選択可能にする。
2. ローカルモデルが未導入なら選択不可と理由を表示する。
3. target language 設定は既存の English / Japanese を共有する。
4. 通知で load、ready、failure を区別する。
5. ローカル選択中にクラウドへ無断送信しない。

### Phase 5: 投機処理を最適化

1. 単一 GPU request の再利用を実装する。
2. 発話再開時の cancel を検証する。
3. 通常レーンとの二重生成が起きないことをログで確認する。
4. end-to-paste の改善量を再測定する。

## 他のオフライン候補を第一候補にしない理由

NLLB-200、MADLAD-400、SeamlessM4T などにも価値はある。しかし今回の
優先順位は「対応言語数」や「小型化」ではなく、中国語の口語的な
SenseVoice 出力を自然で忠実な日本語へ変換する品質である。

従来型の多言語翻訳モデルは速度や再現性で有利な場合がある一方、
ユーザーが過去に試したオフラインモデルでは自然さと期待品質を
満たさなかった。TranslateGemma は新しく公開された翻訳専用モデルで、
中国語→日本語を学習ペアとして明記し、12B/27B の容量も本機で検証可能
な範囲にある。そのため、まずこれを厳密に A/B テストするのが最短で
確実性の高い手順である。

これは他モデルが絶対に劣るという結論ではない。TranslateGemma が
採用ゲートを満たさなかった場合に限り、次候補を同じデータセットと
評価基準で調べる。

## セキュリティとリポジトリ管理

ローカルモデル経路では API key は不要である。モデルファイルは巨大で
あり、ライセンス同意や再配布条件もあるため Git へ格納しない。

Git に入れてよいもの:

- adapter のソースコード。
- prompt profile。
- モデル名、checksum、取得元を記した manifest。
- 秘密情報を除去した評価 fixture。
- 集計済み benchmark 結果。

Git に入れないもの:

- モデル weight / GGUF。
- OpenCode や provider の API key。
- 実際の個人会話を含む音声・文字起こし。
- server log に残った原文。
- machine 固有の秘密情報。

モデル取得時は Gemma の利用規約と配布元のライセンス表示を確認する。

## 未確定事項

次は調査資料だけでは確定できず、実機テストが必要である。

- Honeykrisp Vulkan 上での 12B / 27B の実際の token/s。
- Vulkan backend の安定性とデスクトップ描画への影響。
- 最適な GPU offload、batch、context、thread 数。
- Q4、Q6_K、Q8 の中国語→日本語における品質差。
- SenseVoice の誤認識を含む中国語での 12B と 27B の差。
- 投機生成の cancel が end-to-paste をどれだけ改善するか。
- 27B が常駐した状態で他のデスクトップ処理に与えるメモリ圧力。

この未確定事項を「おそらく速い」「メモリに収まるから使える」と
推測で埋めず、Phase 1 と Phase 2 の数値で判断する。

## 参考資料

一次資料のみを使用した。

- [Google: TranslateGemma — a new suite of open translation models](https://blog.google/innovation-and-ai/technology/developers-tools/translategemma/)
- [TranslateGemma Technical Report (arXiv:2601.09012)](https://arxiv.org/pdf/2601.09012)
- [Google TranslateGemma 12B model card](https://huggingface.co/google/translategemma-12b-it)
- [Ollama TranslateGemma library and prompt guide](https://ollama.com/library/translategemma)
- [llama.cpp official repository](https://github.com/ggml-org/llama.cpp)
- [Ollama official GPU documentation](https://github.com/ollama/ollama/blob/main/docs/gpu.mdx)

## 判断記録

現時点の判断:

- 本命品質候補: TranslateGemma 27B。
- 最初に動かす比較候補: TranslateGemma 12B。
- 低品質でも軽量という理由だけで 4B を採用しない。
- 現在の CPU-only の可能性が高い Ollama 構成で速度を判断しない。
- まず llama.cpp/Vulkan または Vulkan 対応 Ollama の実動を確認する。
- クラウド経路を残したまま、独立したローカル backend として検証する。
- 実データのブラインド評価と採用ゲートを通るまで製品既定値にしない。
