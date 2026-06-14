# ==================================================
# JR九州領収書DL → PDF移動 → 交通費精算書生成
# ==================================================

param (
    # 複数月PDFが混在する場合だけ指定する
    # 例: .\travel-expense-automation.ps1 -Month "2026-05"
    [string]$Month = "",

    # inputs 内の既存PDFを残したい場合は指定する
    # 例: .\travel-expense-automation.ps1 -KeepExistingInputPdf
    [switch]$KeepExistingInputPdf
)

$ErrorActionPreference = "Stop"

# このps1ファイルが置かれているフォルダ
$AutomationDir = $PSScriptRoot

# このps1ファイルが置かれているフォルダの親フォルダを取得
$BaseDir = Split-Path -Path $AutomationDir -Parent

# 実行するスクリプトのリポジトリパスを定義
$JrRepo = Join-Path -Path $BaseDir -ChildPath "jr-kyusyu-receipt-dl"
$GeneratorRepo = Join-Path -Path $BaseDir -ChildPath "travel-expense-generator"

# jr-kyusyu-receipt-dl 側の downloads フォルダへのパスを定義
$PdfSourceDir = Join-Path -Path $JrRepo -ChildPath "downloads"

# travel-expense-generator 側の入力フォルダ
$InputDir = Join-Path -Path $GeneratorRepo -ChildPath "inputs"

# Downloads内の無関係なPDFまで移動しないため、領収書系PDFだけに絞る
$PdfFilePattern = "*領収書_JR*.pdf"

<#
.SYNOPSIS
区切り用の見出しをコンソールに表示する。

.PARAMETER Message
コンソールに表示する見出しメッセージ。
#>
function Write-Section {
    param([string]$Message)

    Write-Host ""
    Write-Host "========================================"
    Write-Host $Message
    Write-Host "========================================"
    Write-Host ""
}

<#
.SYNOPSIS
指定したディレクトリに一時的に移動して処理を実行し、実行後は元のディレクトリに戻る。

.PARAMETER Directory
処理を実行したい対象ディレクトリのパス。

.PARAMETER Script
対象ディレクトリ内で実行する処理。
例: { npm.cmd run download }
#>
function Invoke-InDirectory {
    param(
        [string]$Directory,
        [scriptblock]$Script
    )

    Push-Location $Directory
    try {
        & $Script
    } finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
JR九州領収書ダウンロード用プロジェクトを実行し、領収書PDFをダウンロードする。

.DESCRIPTION
jr-kyusyu-receipt-dl のルートディレクトリに移動し、
npm run download を実行する。
処理完了後は、実行前のディレクトリに戻る。
#>
function Run-JrDownload {
    Write-Section "JR九州 領収書PDFダウンロードを開始します"

    if (-not (Test-Path $JrRepo)) {
        throw "jr-kyusyu-receipt-dl フォルダが見つかりません: $JrRepo"
    }

    # JR九州の領収書ダウンロードのルートに移動しスクリプトを実行（実行後元のディレクトリに戻る）
    Invoke-InDirectory $JrRepo {
        npm.cmd run download
    }
}

<#
.SYNOPSIS
ダウンロード済みの領収書PDFを travel-expense-generator の inputs フォルダへ移動する。

.DESCRIPTION
PDF移動元フォルダから領収書PDFを取得し、
travel-expense-generator の inputs フォルダへ移動する。
$KeepExistingInputPdf が指定されていない場合は、
移動前に inputs 内の既存PDFを削除する。
#>
function Move-PdfsToInputs {
    Write-Section "PDFを inputs フォルダへ移動します"

    if (-not (Test-Path $PdfSourceDir)) {
        throw "PDF移動元フォルダが見つかりません: $PdfSourceDir"
    }

    # inputs フォルダが存在しない場合は作成する
    if (-not (Test-Path $InputDir)) {
        New-Item -ItemType Directory -Path $InputDir | Out-Null
    }

    # 指定がない場合は、inputs 内の既存PDFを削除してから新しいPDFを配置する
    if (-not $KeepExistingInputPdf) {
        Write-Host "inputs 内の既存PDFを削除します。"
        Get-ChildItem -Path $InputDir -Filter "*.pdf" -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    # PDF移動元フォルダから領収書PDFだけを取得
    $PdfFiles = Get-ChildItem -Path $PdfSourceDir -Filter $PdfFilePattern -File

    if ($PdfFiles.Count -eq 0) {
        throw "移動対象のPDFが見つかりませんでした。確認先: $PdfSourceDir / 条件: $PdfFilePattern"
    }

    # 取得したPDFを inputs フォルダへ移動する
    foreach ($Pdf in $PdfFiles) {
        Write-Host "move: $($Pdf.Name)"
        Move-Item -Path $Pdf.FullName -Destination $InputDir -Force
    }

    Write-Host ""
    Write-Host "$($PdfFiles.Count) 件のPDFを移動しました。"
}

<#
.SYNOPSIS
travel-expense-generator を実行し、交通費精算書を生成する。

.DESCRIPTION
travel-expense-generator のルートディレクトリに移動し、
inputs フォルダ内のPDFを元に交通費精算書を生成する。
$Month が指定されている場合は、対象月を指定して実行する。
#>
function Run-ExpenseGenerator {
    Write-Section "交通費精算書の生成を開始します"

    if (-not (Test-Path $GeneratorRepo)) {
        throw "travel-expense-generator フォルダが見つかりません: $GeneratorRepo"
    }

    Invoke-InDirectory $GeneratorRepo {
        if ([string]::IsNullOrWhiteSpace($Month)) {
            npm.cmd run generate
        } else {
            npm.cmd run generate -- --month $Month
        }
    }
}

try {
    # 1. JR九州サイトから領収書PDFをダウンロードする
    Run-JrDownload

    # 2. ダウンロードしたPDFを travel-expense-generator の inputs フォルダへ移動する
    Move-PdfsToInputs

    # 3. inputs フォルダ内のPDFを元に交通費精算書を生成する
    Run-ExpenseGenerator

    Write-Section "すべての処理が完了しました"
}
catch {
    Write-Host ""
    Write-Host "[ERROR] 処理に失敗しました。"
    Write-Host $_.Exception.Message
    Write-Host ""
    exit 1
}
finally {
    Read-Host "Enterキーを押すと閉じます"
}