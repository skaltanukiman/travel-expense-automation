# Travel Expense Automation

交通費精算作業をまとめて実行するための自動化スクリプトです。

## 概要

本リポジトリは、毎月の交通費精算作業を簡略化するための自動化用リポジトリです。

通常は `run.bat` をダブルクリックして実行します。

このスクリプトでは、以下の一連の作業をまとめて実行します。

1. JR九州の領収書PDFを取得する
2. 取得した領収書PDFを交通費精算書生成用の入力フォルダへ移動する
3. 領収書PDFをもとに交通費精算書Excelを生成する

## 前提条件

以下の3つのフォルダが、同じ親フォルダ配下に配置されている必要があります。

```text
親フォルダ/
├─ travel-expense-automation/
├─ jr-kyusyu-receipt-dl/
└─ travel-expense-generator/
```

## 使い方

`travel-expense-automation` フォルダ内の `run.bat` をダブルクリックします。

```text
run.bat
```

実行すると、領収書PDFの取得から交通費精算書Excelの生成までが順番に実行されます。


### 起動時の入力

`run.bat` は次の順で入力を受け付けます。

1. 対象月（例: `2026-09`、空Enterで領収書から推測）
2. Excel転記から除外する日（例: `23`、複数なら `13,23,25`、空Enterで除外なし）
3. inputs内の既存PDFを残すか（Y: 残す、N／空Enter: 従来どおり入替・処理後にfilesbackへ移動）

除外日は `13, 23, 25` のように空白を含んでも入力できます。batの `-ExcludeDays` パラメータからPowerShellへ渡し、PowerShellは引数配列を使ってgeneratorの `--exclude-days` に渡します。1～31の整数、重複の除去、対象月の日数（閏年を含む）の検証はgeneratorが行います。

直接PowerShellから実行する場合:

```powershell
.\travel-expense-automation.ps1 -Month "2026-09" -ExcludeDays "23"
.\travel-expense-automation.ps1 -Month "2026-09" -ExcludeDays "13, 23, 25" -KeepExistingInputPdf
.\travel-expense-automation.ps1 -ExcludeDays "13,23,25"
.\travel-expense-automation.ps1 -Month "2026-09"
.\travel-expense-automation.ps1
```

除外日はExcelの精算対象だけに適用します。同日のJR往復と `eachReceiptDate` のバス等も除外されます。JR九州からのPDF取得は従来どおりです。成功時は除外したPDFも含めて従来のfilesback処理を行い、`-KeepExistingInputPdf` 指定時はinputsに残します。

全件除外・入力エラーなどでgeneratorが終了コード1を返した場合、空Excelを生成せず、automationも後処理へ進まず停止します。この場合、PDFはinputsに残り、既存の出力Excelは移動しません。

### 開発・検証

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/arguments.test.ps1
```

PowerShellの構文、月／除外日の有無4パターン、空白・不正値の受け渡し、generator失敗時の停止を検証します。また、実際のrun.batを一時フォルダで起動し、Y／N／空EnterそれぞれのPowerShell引数を検証します。ダウンロード、実PDFの移動、実Excelの移動は行いません。

## 処理内容

`run.bat` では、以下の処理を行います。

```text
jr-kyusyu-receipt-dl を実行
        ↓
領収書PDFを取得
        ↓
取得したPDFを travel-expense-generator の inputs フォルダへ移動
        ↓
travel-expense-generator を実行
        ↓
交通費精算書Excelを生成
```

## フォルダ構成

想定しているフォルダ構成は次のとおりです。

```text
親フォルダ/
├─ travel-expense-automation/
│  └─ run.bat
│
├─ jr-kyusyu-receipt-dl/
│  └─ downloads/
│
└─ travel-expense-generator/
   ├─ inputs/
   └─ outputs/
```

## 注意事項

* 各ツールの初期設定は事前に完了している必要があります。
* JR九州へのログインや予約一覧画面の表示など、手動操作が必要な部分があります。

## 関連リポジトリ

このリポジトリは、以下のツールを呼び出して一連の交通費精算作業を自動化します。

* `jr-kyusyu-receipt-dl`
* `travel-expense-generator`

## 更新予定
* 実行時のプロンプト入力の最適化