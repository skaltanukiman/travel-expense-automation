@echo off

REM このbatが置かれているフォルダに移動
cd /d "%~dp0"

echo ========================================
echo JR九州 領収書DL → 交通費精算書生成
echo ========================================
echo.

echo 対象月を入力してください。
echo 例: 2026-05
echo 空のままEnterで月指定なし
echo.
set /p MONTH=対象月:

:ASK_KEEP_INPUT
echo.
echo inputs 内の既存PDFを残しますか？
echo Y: 残す
echo N: 削除する
echo 空Enter: 削除する
echo.

REM 前回入力値が残らないようにクリアする
set "KEEP_INPUT="

set /p KEEP_INPUT=入力してください [Y/N]: 

REM 正しい入力値の場合は、先の処理にgotoで進む
if "%KEEP_INPUT%"=="" goto RUN_DELETE
if /i "%KEEP_INPUT%"=="Y" goto RUN_KEEP
if /i "%KEEP_INPUT%"=="N" goto RUN_DELETE

REM 入力値が不正な場合は、再度入力を求める
echo.
echo Y または N を入力してください。
goto ASK_KEEP_INPUT

:RUN_KEEP
echo.
echo 既存PDFを残して処理を開始します。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0travel-expense-automation.ps1" -Month "%MONTH%" -KeepExistingInputPdf
goto CHECK_RESULT

:RUN_DELETE
echo.
echo 既存PDFを削除して処理を開始します。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0travel-expense-automation.ps1" -Month "%MONTH%"
goto CHECK_RESULT

:CHECK_RESULT
if errorlevel 1 (
    echo.
    echo 処理中にエラーが発生しました。
    pause
)