param(
    [string]$ModelSimDirectory = 'D:\ModelSim\altera\14.1\modelsim_ase\win32aloem'
)

$ErrorActionPreference = 'Stop'
$simDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $simDir
$hdlDir = Join-Path $projectRoot '02_FPGA_PROJECT\src\user_source\hdl_source'
$mDir = $ModelSimDirectory

foreach ($toolName in @('vlib.exe', 'vlog.exe', 'vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $mDir $toolName))) {
        throw "ModelSim tool not found: $toolName. Set -ModelSimDirectory to the ModelSim executable directory."
    }
}

$tempWork = Join-Path $env:TEMP ("v27_game_tb_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempWork | Out-Null

try {
    & (Join-Path $mDir "vlib.exe") (Join-Path $tempWork "work") | Out-Null
    Copy-Item (Join-Path $hdlDir "*.hex") $tempWork
    & (Join-Path $mDir "vlog.exe") -work (Join-Path $tempWork "work") `
        "+incdir+$hdlDir" `
        (Join-Path $hdlDir "contest_game_rom.v") `
        (Join-Path $hdlDir "contest_game.v") `
        (Join-Path $simDir "tb_game_v27.v")

    if ($LASTEXITCODE -ne 0) { throw "Compilation failed" }

    Push-Location $tempWork
    try {
        $out = & (Join-Path $mDir "vsim.exe") -c -lib (Join-Path $tempWork "work") tb_game_v27 -do "run -all; quit -f"
        $out | ForEach-Object { Write-Host $_ }
    } finally {
        Pop-Location
    }

    if (!($out -match "ALL 12 V27 GAME UPGRADE TESTS PASSED SUCCESSFULLY!")) {
        throw "Simulation test failed!"
    }
    Write-Host "TB_GAME_V27_PASS"
} finally {
    Remove-Item -LiteralPath $tempWork -Recurse -Force -ErrorAction SilentlyContinue
}
