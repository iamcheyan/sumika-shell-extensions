# 音声を聞きながら先行翻訳する仕組み

この文書は、Voice extension の「録音中に翻訳処理を先行させる」
第二層最適化について、実際のコードに沿って説明するものです。

## 最初に：これはストリーミング文字起こしではない

現在使っている SenseVoice は `OfflineRecognizer` です。そのため、
音声を100msずつモデルへ流し込み、確定文字を連続生成する方式では
ありません。

実際の方式は次のとおりです。

1. `parecord` が録音中のWAVファイルへ音声を書き続ける。
2. 別プロセスが成長中のWAVを100ms間隔で観察する。
3. 発話後の無音を500ms検出した時点で、その時点までの音声を
   一時WAVへスナップショットする。
4. スナップショット全体をSenseVoiceで一度だけ文字起こしする。
5. 得られた中国語を候補として、録音終了前に翻訳APIを呼び始める。
6. 発話が再開されたら、その候補を破棄する。
7. 録音終了後、通常どおり最終WAVを文字起こしする。
8. 候補元の中国語と最終中国語が完全一致した場合だけ、先行翻訳を
   採用できる。

したがって「聞きながら文字起こし」は、厳密には
「録音中の無音区間でオフライン文字起こしを先行実行する」です。
不安定な途中文字列を直接入力先へ貼り付けることはありません。

## 関係するファイル

| ファイル | 役割 |
|---|---|
| `VoiceInput.qml` | 録音・最終文字起こし・候補照合・貼り付けの状態管理 |
| `bin/omarchy-voice-record` | `parecord` の開始・停止とWAV/PID管理 |
| `bin/sumika-voice-record` | ライブラリ環境を整えて録音実体を呼ぶラッパー |
| `bin/sumika-voice-transcribe` | Voice venvのPythonで認識実体を呼ぶラッパー |
| `bin/omarchy-voice-transcribe` | 長寿命SenseVoice daemonとオフライン認識 |
| `bin/sumika-voice-speculate` | 成長中WAV監視、VAD、スナップショット、候補管理 |
| `bin/sumika-voice-translate` | OpenCode設定読込、翻訳daemon、2本のHTTPレーン |

実際の実行ファイルの関係は次のようになります。

```text
VoiceInput.qml
 ├─ sumika-voice-record
 │   └─ omarchy-voice-record
 │       └─ parecord
 ├─ sumika-voice-transcribe
 │   └─ omarchy-voice-transcribe
 │       └─ /tmp/sumika-voice.sock
 ├─ sumika-voice-speculate
 │   ├─ sumika-voice-transcribe
 │   └─ sumika-voice-translate translate-speculative
 └─ sumika-voice-translate translate
     └─ translation daemon
```

## 全体の時系列

### 候補が録音終了前に完成する場合

```text
ユーザー          録音/VAD             SenseVoice       翻訳daemon        QML
   │                  │                     │                 │              │
   │ 発話             │ WAVへ追記           │                 │              │
   │─────────────────>│                     │                 │              │
   │ 発話終了         │                     │                 │              │
   │                  │ 500ms無音検出        │                 │              │
   │                  │ スナップショット ───>│                 │              │
   │                  │<──── 仮中国語 ───────│                 │              │
   │                  │ 仮中国語を通知 ─────────────────────────────────────>│
   │                  │ translate-speculative ────────────────>│              │
   │                  │<──────────── 仮翻訳完了 ───────────────│              │
   │ 録音終了         │                     │                 │              │
   │─────────────────>│ 最終WAV ───────────>│                 │              │
   │                  │<──── 最終中国語 ─────│                 │              │
   │                  │                     │                 │  完全一致確認 │
   │                  │                     │                 │<─────────────│
   │                  │                     │                 │   貼り付け    │
```

この理想ケースでは、録音終了後に残る主な処理は最終SenseVoice認識と
完全一致確認だけです。

### 候補翻訳がまだ実行中の場合

```text
投機レーン:  ─────────────── 翻訳中 ────────────────┐
                                                    ├─ 先に成功した結果を採用
録音終了 → 最終認識 → 通常レーンを即開始 ──────────┘
```

QMLは投機翻訳を待ってから通常翻訳を始めるのではありません。
最終中国語が出た時点で投機が未完了なら、従来の通常翻訳も直ちに
開始します。これをヘッジリクエストとして扱い、先に成功した結果だけを
貼り付けます。

## 録音処理

`bin/omarchy-voice-record` は次の形式で録音します。

```text
format:      signed 16-bit little endian
sample rate: 16000 Hz
channels:    mono
container:   WAV
latency:     10 ms
```

既定パスは次のとおりです。

```text
/tmp/sumika-voice-rec.wav
/tmp/sumika-voice-rec.pid
```

録音中はWAVファイルが成長し続けます。停止時は `parecord` へ最初に
`SIGINT` を送り、終了しなければ `SIGTERM` へフォールバックします。
これによりWAVヘッダーを可能な限り正常に確定させます。

## 成長中WAVの読み取り

担当は `bin/sumika-voice-speculate` です。

録音中のWAVはデータサイズがまだ確定していない可能性があります。
そのため通常の `wave.open()` で直接継続監視せず、RIFFチャンクを
自前で読みます。

1. `RIFF` と `WAVE` シグネチャを確認する。
2. チャンクを順番に走査する。
3. `data` チャンクの開始位置を見つける。
4. 現時点でファイルに存在するPCMだけを読み出す。
5. 16-bitサンプル境界に合わない末尾1バイトは無視する。

候補認識を行う際は、読み出したPCMを新しい一時WAVへ書き直します。
この一時WAVはチャンネル数、サンプル幅、レート、フレーム数が確定した
通常のWAVなので、既存の文字起こし処理へ安全に渡せます。

一時ファイル名は次の形式で作られ、認識後に削除されます。

```text
/tmp/sumika-voice-speculative-*.wav
```

## 無音検出

VADは外部モデルではなく、PCMのRMSエネルギーで判定します。

現在の定数は `bin/sumika-voice-speculate` 冒頭にあります。

| 定数 | 値 | 意味 |
|---|---:|---|
| `WINDOW_MS` | 100ms | エネルギー計算単位 |
| `MIN_AUDIO_MS` | 800ms | これより短い録音では候補を作らない |
| `SILENCE_WINDOWS` | 5 | 500ms連続で静かな場合に候補化 |
| `MIN_SPEECH_RMS` | 12 | 発話を観測したとみなす最低RMS |
| `ABSOLUTE_SILENCE_RMS` | 8 | 無音閾値の最低値 |
| `SILENCE_RATIO` | 0.28 | 最大発話RMSに対する無音比率 |
| `POLL_SECONDS` | 0.1秒 | WAV監視間隔 |

無音閾値は固定値だけではありません。

```text
silence_limit = max(8, 観測済み最大RMS × 0.28)
```

これにより、マイク感度が高い環境と低い環境の両方にある程度追従します。

RMSは新しく増えた100ms窓だけ計算します。録音全体のRMSを100msごとに
最初から再計算しないため、長時間録音でも計算量が録音時間に対して
ほぼ線形になります。

## 発話再開の検出

500msの無音は文章の終端とは限りません。文中で考えているだけかも
しれないため、候補作成後もWAV監視を続けます。

再開判定の閾値は次のとおりです。

```text
resume_threshold =
  max(12, 観測済み最大RMS × 0.28 × 1.25)
```

候補スナップショット以降に追加されたPCMがこの閾値を超えた場合：

1. 実行中の投機翻訳クライアントを終了する。
2. QMLへ `invalidated` イベントを送る。
3. 候補元中国語と候補翻訳を破棄する。
4. 次の500ms無音を待つ。

投機APIがすでに応答済みでも、録音プロセスが生きている間は結果を
すぐQMLへ確定通知しません。発話再開がないことを録音終了まで監視し、
再開されなかった場合だけ `result` を送ります。

## SenseVoice候補認識

候補WAVも最終WAVも、同じ `sumika-voice-transcribe` を使用します。
したがって候補だけ別モデルや別正規化を使うことはありません。

SenseVoice daemon側では次の前処理を行います。

1. `ffmpeg` で16kHz・monoへ正規化。
2. `volume=20dB` を適用。
3. 最小録音時間とピーク振幅を確認。
4. `sherpa_onnx.OfflineRecognizer` で認識。
5. `<|zh|>` などのSenseVoiceタグを除去。

同じモデル・同じ前処理を使うことで、候補元と最終結果が一致する
可能性を高めています。

## 候補イベント

`sumika-voice-speculate` は標準出力へJSON Linesを出します。

候補元中国語が得られた時：

```json
{
  "event": "source",
  "source": "候補の中国語",
  "audioMs": 4200,
  "transcribeMs": 240,
  "translationStartedAtMs": 1785418902804
}
```

発話再開で破棄した時：

```json
{
  "event": "invalidated",
  "source": "破棄された中国語"
}
```

候補翻訳が成立した時：

```json
{
  "event": "result",
  "source": "候補の中国語",
  "text": "翻訳結果",
  "audioMs": 4200,
  "transcribeMs": 240,
  "translateMs": 1800,
  "apiSeconds": 1.72,
  "translationStartedAtMs": 1785418902804
}
```

録音終了前に候補を作れなかった場合や、候補処理を正常に中止した場合は
`aborted` を出します。これはユーザーへ表示する翻訳エラーではなく、
通常経路をそのまま使うための内部状態です。

## 翻訳daemonの2レーン

`bin/sumika-voice-translate` は1つのUnix Socket daemon内に2つの
論理レーンを持ちます。

| レーン | daemon action | 用途 |
|---|---|---|
| `primary` | `translate`, `benchmark` | 従来の確定翻訳 |
| `speculative` | `speculate` | 録音中の候補翻訳 |

各レーンは独立した次の状態を持ちます。

- HTTP/HTTPS Keep-Alive接続
- 排他ロック
- 接続切断時の再接続

OpenCodeのProvider、モデル、API Key、目標言語の解決結果は共通で
キャッシュします。設定ファイルのmtimeまたはサイズが変わると
自動的に再読込します。

監視対象は次の3ファイルです。

```text
~/.config/sumika-shell/voice/config.json
~/.config/opencode/opencode.json
~/.local/share/opencode/auth.json
```

レーンを分けた理由は、投機候補を破棄した後もサーバー側API処理が
短時間継続する場合があるためです。同じ接続とロックを使うと、
破棄済み候補が最終翻訳を待たせる可能性があります。独立レーンなら
通常翻訳は直ちに開始できます。

daemonの現在のプロトコルバージョンは `2` です。コード更新後に古い
daemonを検出した場合は自動的に停止・再起動します。

## QML側の完全一致判定

`VoiceInput.qml` の `handleFinalTranslationSource(text)` が最終判断を
行います。

### 候補翻訳が完成済み

```text
speculativeSource === finalSource
かつ
speculativeOutput が空ではない
```

この場合だけ候補翻訳を採用します。

### 候補元は一致しているが翻訳中

```text
speculativeSource === finalSource
かつ
speculationProc.running
```

通常翻訳を直ちに開始し、投機レーンとの競争にします。通常経路を
意図的に遅らせる待機時間はありません。

### 候補元が一致しない

投機プロセスを停止し、従来どおり最終中国語を通常レーンへ送ります。

比較は類似度ではなく文字列の完全一致です。句読点、数字、文字の
いずれか1つでも異なる場合は候補を採用しません。

## 最初に成功した結果だけを貼り付ける

QMLの状態が `"translating"` の間だけ、通常翻訳の `onExited` は結果を
採用します。

投機結果が先に成功すると：

1. `acceptTranslation(..., true)` が実行される。
2. 状態が `"success"` へ変わる。
3. 後から通常翻訳が完了しても、状態が `"translating"` ではないため
   その結果を再度貼り付けない。

通常結果が先に成功すると：

1. `acceptTranslation(..., false)` が実行される。
2. 投機監視プロセスを停止する。
3. 状態が `"success"` へ変わる。

このため、ヘッジ中に翻訳結果が2回返っても貼り付けは1回だけです。

## エラーとフォールバック

| 状況 | 挙動 |
|---|---|
| 500ms無音を検出できない | 投機なしで通常経路 |
| 候補SenseVoiceが空 | 投機を中止して通常経路 |
| 発話が再開 | 候補を破棄して監視継続 |
| 候補元と最終中国語が不一致 | 通常経路 |
| 投機APIが失敗 | 通常経路は独立して実行可能 |
| 通常APIが先に成功 | 通常結果を貼り付け |
| 投機APIが先に成功し完全一致 | 投機結果を貼り付け |
| 両APIが失敗 | 中国語認識結果をクリップボードへ退避 |
| Escapeで録音キャンセル | 投機プロセスも停止 |

重要なのは、投機処理が「正しい最終中国語」を置き換えないことです。
候補が利用できないすべてのケースで、以前から存在する
録音終了後の最終文字起こし・翻訳経路が残っています。

## 設定

投機翻訳は既定で有効です。

```json
{
  "translation": {
    "model": "provider/model",
    "targetLanguage": "Japanese",
    "binding": "HANGUL",
    "speculativeEnabled": true
  }
}
```

無効化するときは次のようにします。

```json
{
  "translation": {
    "speculativeEnabled": false
  }
}
```

`false` の場合、QMLは `sumika-voice-speculate` を起動せず、完全に
従来経路だけを使います。設定変更後はSumikaを再読み込みするか、
Voice設定を再読込してください。

## レイテンシ計測

翻訳が確定すると、QMLは次の形式でログを出します。

```text
[VoiceInput] translation metrics: {...}
```

確認方法：

```sh
rg "translation metrics" /tmp/sumika-bar.log | tail
```

主なフィールド：

| フィールド | 意味 |
|---|---|
| `mode` | 採用結果が `speculative` か `normal` か |
| `recordingToPasteMs` | 録音開始から貼り付けまで |
| `releaseToPasteMs` | 録音停止完了から貼り付けまで |
| `finalTranscribeMs` | 最終SenseVoice認識時間 |
| `translationMs` | 採用レーンの翻訳時間 |
| `speculativeAudioMs` | 候補スナップショットの音声長 |
| `speculativeTranscribeMs` | 候補SenseVoice認識時間 |
| `speculativeLeadMs` | 録音停止より何ms早く翻訳を開始したか |

APIだけを比較する場合：

```sh
printf '%s' '这是一个测试。' |
  sumika-voice-translate benchmark | jq

printf '%s' '这是一个测试。' |
  sumika-voice-translate translate-speculative | jq
```

`translate-speculative` は内部診断用コマンドです。通常の入力処理では
`sumika-voice-speculate` が呼び出します。

## セキュリティ

- 翻訳daemonのSocketはモード `0600`。
- API Keyは翻訳daemonがOpenCode設定またはauthファイルから読む。
- API KeyをVoice設定へ複製しない。
- API KeyをUnix Socketのリクエストへ含めない。
- API Keyをログやメトリクスへ出力しない。
- Socketへ送るのは中国語本文とactionだけ。
- 一時WAVは候補認識後に削除する。

## 既知の制約とコスト

1. これは真のストリーミングASRではないため、500ms無音がなければ
   先行処理できません。
2. 文中の長い間が候補化されることがあります。ただし発話再開時に
   無効化され、最終完全一致でも保護されます。
3. 最終認識時に投機APIが未完了なら、ヘッジとして通常APIも呼ぶため、
   一時的にAPIリクエストが2本になります。
4. Providerの応答時間が不安定な場合、投機が常に勝つとは限りません。
5. 十分な無音を置かずに録音を終了すると、効果はほぼありません。
6. 一時WAV認識のため、候補作成時にSenseVoice推論を追加で1回実行します。

この実装が優先しているのは「常に速く見せること」ではなく、
「速くできるケースだけ前倒しし、正しさと従来経路を維持すること」です。

## 推奨テスト

### 1. 通常の短文

短文を話し、約1秒無音にしてから録音を終了します。
`mode: speculative` になる可能性があります。

### 2. 無音なし

話し終わった直後に録音を終了します。通常経路が動き、
`mode: normal` になることを確認します。

### 3. 文中で停止して再開

文章の途中で1秒止まり、その後続きを話します。途中候補は
`invalidated` され、最終全文と異なる候補が貼り付けられないことを
確認します。

### 4. 投機無効

`speculativeEnabled` を `false` にして、常に通常経路になることを
確認します。

### 5. daemon状態

```sh
sumika-voice-translate daemon-status
```

期待値：

```json
{
  "running": true,
  "protocol": 2
}
```
