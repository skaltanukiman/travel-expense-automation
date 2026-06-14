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