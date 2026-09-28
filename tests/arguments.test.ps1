# Run with: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/arguments.test.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$encoding = [System.Text.Encoding]::GetEncoding(932)
$source = [System.IO.File]::ReadAllText((Join-Path $repo 'travel-expense-automation.ps1'), $encoding)
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }

function Assert-Equal($actual, $expected, [string]$message) {
    if (($actual | ConvertTo-Json -Compress) -cne ($expected | ConvertTo-Json -Compress)) {
        throw "$message Expected: $($expected | ConvertTo-Json -Compress); Actual: $($actual | ConvertTo-Json -Compress)"
    }
}

# Load only the functions under test; never execute the downloader or PDF movement.
foreach ($name in @('Invoke-InDirectory', 'Run-ExpenseGenerator')) {
    $functionAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($null -eq $functionAst) { throw "Missing function: $name" }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
function Write-Section { param([string]$Message) }
function npm.cmd {
    $script:capturedArgs = @($args)
    $global:LASTEXITCODE = $script:mockExitCode
}
$GeneratorRepo = $repo
$cases = @(
    @{ Month = '2026-09'; Days = '13, 23, 25'; Expected = @('run', 'generate', '--', '--month', '2026-09', '--exclude-days', '13, 23, 25') },
    @{ Month = '2026-09'; Days = ''; Expected = @('run', 'generate', '--', '--month', '2026-09') },
    @{ Month = ''; Days = '13, 23, 25'; Expected = @('run', 'generate', '--', '--exclude-days', '13, 23, 25') },
    @{ Month = ''; Days = ''; Expected = @('run', 'generate') },
    @{ Month = ''; Days = '  '; Expected = @('run', 'generate') },
    @{ Month = ''; Days = '23a'; Expected = @('run', 'generate', '--', '--exclude-days', '23a') }
)
$script:mockExitCode = 0
foreach ($case in $cases) {
    $Month = $case.Month
    $ExcludeDays = $case.Days
    Run-ExpenseGenerator
    Assert-Equal $script:capturedArgs $case.Expected 'Generator arguments'
}
$script:mockExitCode = 1
$before = (Get-Location).Path
$failed = $false
try { Run-ExpenseGenerator } catch { $failed = $true }
Assert-Equal $failed $true 'Generator failure must stop processing'
Assert-Equal (Get-Location).Path $before 'Working directory must be restored'
Write-Host 'PASS: PowerShell syntax, 6 generator argument cases, failure propagation'

function Send-BatchInput($process, [string]$prompt, [string]$value) {
    $buffer = New-Object char[] 1
    $output = ''
    while (-not $output.EndsWith($prompt)) {
        $read = $process.StandardOutput.ReadAsync($buffer, 0, 1)
        if (-not $read.Wait(10000)) { $process.Kill(); throw "Prompt timed out: $prompt" }
        if ($read.Result -eq 0) { throw "Prompt missing: $prompt; output: $output" }
        $output += $buffer[0]
    }
    $process.StandardInput.WriteLine($value)
    $process.StandardInput.Flush()
}
# Execute the actual batch UI in an isolated directory with a harmless PowerShell receiver.
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('travel-expense-automation-test-' + [guid]::NewGuid())
[System.IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $repo 'run.bat') -Destination $testRoot
    $stub = 'param([string]$Month = "", [string]$ExcludeDays = "", [switch]$KeepExistingInputPdf)' + "`r`n" +
        '@{ Month = $Month; Days = $ExcludeDays; Keep = [bool]$KeepExistingInputPdf } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot "received.json") -Encoding UTF8'
    [System.IO.File]::WriteAllText((Join-Path $testRoot 'travel-expense-automation.ps1'), $stub)
    $batText = [System.IO.File]::ReadAllText((Join-Path $repo 'run.bat'), $encoding)
    if (-not ($batText.IndexOf('set /p MONTH=') -lt $batText.IndexOf('set /p EXCLUDE_DAYS=') -and
        $batText.IndexOf('set /p EXCLUDE_DAYS=') -lt $batText.IndexOf(':ASK_KEEP_INPUT'))) {
        throw 'Unexpected prompt order'
    }
    $caseIndex = 0
    foreach ($case in $cases[0..3]) {
        foreach ($keep in @('Y', 'N', '')) {
            $receivedPath = Join-Path $testRoot 'received.json'
            if (Test-Path -LiteralPath $receivedPath) { Remove-Item -LiteralPath $receivedPath }
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $env:ComSpec
            $startInfo.Arguments = '/d /c run.bat'
            $startInfo.WorkingDirectory = $testRoot
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.StandardOutputEncoding = $encoding
            $startInfo.RedirectStandardError = $true
            # Check that pressing Enter clears inherited values as well.
            $startInfo.EnvironmentVariables['MONTH'] = '1999-01'
            $startInfo.EnvironmentVariables['EXCLUDE_DAYS'] = '31'
            $process = [System.Diagnostics.Process]::Start($startInfo)
            try {
                $stderrTask = $process.StandardError.ReadToEndAsync()
                # cmd set /p can consume multiple buffered lines from redirected stdin.
                # Wait for each real prompt, just as an interactive user would.
                Send-BatchInput $process '対象月:' $case.Month
                Send-BatchInput $process '除外日:' $case.Days
                Send-BatchInput $process '[Y/N]: ' $keep
                $process.StandardInput.Close()
                $stdoutTask = $process.StandardOutput.ReadToEndAsync()
                if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Batch test timed out' }
                if (-not (Test-Path -LiteralPath $receivedPath)) {
                    throw "Batch receiver missing: $($stdoutTask.Result) $($stderrTask.Result)"
                }
                $received = Get-Content -LiteralPath $receivedPath -Raw -Encoding UTF8 | ConvertFrom-Json
                Assert-Equal $received.Month $case.Month 'Batch Month'
                Assert-Equal $received.Days $case.Days 'Batch ExcludeDays'
                Assert-Equal $received.Keep ($keep -eq 'Y') 'Batch KeepExistingInputPdf'
                $caseIndex++
            } finally { $process.Dispose() }
        }
    }
    Write-Host "PASS: $caseIndex batch-to-PowerShell cases (4 combinations x Y/N/Enter)"
} finally {
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    $allowedPrefix = Join-Path ([System.IO.Path]::GetTempPath()) 'travel-expense-automation-test-'
    if (-not $resolved.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unexpected test cleanup path: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}