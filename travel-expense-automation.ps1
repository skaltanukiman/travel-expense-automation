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

#### パス定義 ####

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

# このps1ファイルが置かれているフォルダの下に、処理に使用したファイルを保存するためのフォルダを定義
$FilesbackDir = Join-Path -Path $AutomationDir -ChildPath "filesback"

##############

#### ファイル抽出条件 ####

# Downloads内の無関係なPDFまで移動しないため、領収書系PDFだけに絞る
$PdfFilePattern = "*領収書_JR*.pdf"

########################

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
    inputs フォルダ内のPDFを filesback フォルダへ移動します。

    .DESCRIPTION
    処理済みのPDFファイルを inputs フォルダから filesback フォルダへ移動します。

    $KeepExistingInputPdf が true の場合は、PDFを移動せずに処理を終了します。
    filesback フォルダが存在しない場合は作成し、その配下に現在日時のフォルダを作成して、
    そこをバックアップ先として使用します。

    $InputDir から $PdfFilePattern に一致するPDFファイルを取得し、
    取得したPDFを filesback 配下の現在日時フォルダへ移動します。

    移動元の inputs フォルダが存在しない場合、または移動対象PDFが存在しない場合はエラーを発生させます。
#>
function InputsPdf-To-Filesback {
    # 指定がない場合は、inputs 内の処理済みPDFをバックアップフォルダに移動する
    if ($KeepExistingInputPdf) {
        Write-Section "pdf 移動はスキップします。inputs 内の既存PDFを残す設定になっています。"
        return
    }

    Write-Section "inputs フォルダのPDFを filesback フォルダへ移動します"

    if (-not (Test-Path $InputDir)) {
        throw "inputs フォルダが見つかりません: $InputDir"
    }

    # filesback フォルダが存在しない場合は作成する
    if (-not (Test-Path $FilesbackDir)) {
        New-Item -ItemType Directory -Path $FilesbackDir | Out-Null
    }

    # filesback フォルダの下に、現在日時のフォルダを作成してバックアップ先とする
    $backupPath = New-CurrentDateTimeDirectory $FilesbackDir

    # PDF移動元フォルダから領収書PDFだけを取得
    $pdfFiles = Get-ChildItem -Path $InputDir -Filter $PdfFilePattern -File

    if ($pdfFiles.Count -eq 0) {
        throw "移動対象のPDFが見つかりませんでした。確認先: $InputDir / 条件: $PdfFilePattern"
    }

    # 取得したPDFを filesback の現在日時フォルダへ移動する
    foreach ($pdf in $pdfFiles) {
        Write-Host "move-filesback: $($pdf.Name)"
        Move-Item -Path $pdf.FullName -Destination $backupPath -Force
    }

    Write-Host ""
    Write-Host "$($pdfFiles.Count) 件のPDFをfilesbackに移動しました。"
}

<#
    .SYNOPSIS
    指定されたパス配下に、現在日時のフォルダを作成します。

    .DESCRIPTION
    引数で受け取った親フォルダパスの配下に、
    yyyyMMdd_HHmmss 形式の現在日時フォルダを作成します。
    作成したフォルダのパスを戻り値として返します。

    .PARAMETER path
    現在日時フォルダを作成する親フォルダのパス。

    .OUTPUTS
    string
    作成した現在日時フォルダのパス。
#>
function New-CurrentDateTimeDirectory {
    param(
        [string]$path
    )

    # 現在日時のフォルダ名を作成
    $folderName = Get-Date -Format "yyyyMMdd_HHmmss"

    # 渡されたパス + 現在日時フォルダ
    $createdPath = Join-Path -Path $path -ChildPath $folderName

    # フォルダが無ければ作成
    if (-not (Test-Path -Path $createdPath)) {
        New-Item -ItemType Directory -Path $createdPath | Out-Null
    }

    # 作成したフォルダパスを返す
    return $createdPath
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

    Write-Section "すべての主処理が完了しました"

    Write-Section "後処理を開始します"

    # 4. inputs フォルダ内のPDFをfilesbackに移動する
    InputsPdf-To-Filesback
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