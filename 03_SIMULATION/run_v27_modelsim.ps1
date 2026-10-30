param(
    [string]$ToolDirectory='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem',
    [string]$BuildDirectory=''
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$BuildDirectory){
    $BuildDirectory=Join-Path ([IO.Path]::GetTempPath()) ('v27_sim_'+[guid]::NewGuid().ToString('N'))
}
$hdl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source'
$work=Join-Path $BuildDirectory 'work'
New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null

# Copy hex files into simulation directory so $readmemh finds them
Get-ChildItem -Path $hdl -Filter "*.hex" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $BuildDirectory $_.Name) -Force
}

& (Join-Path $ToolDirectory 'vlib.exe') $work | Out-Null
$sources=@(
    (Join-Path $hdl 'contest_dynamic_flame.v'),
    (Join-Path $hdl 'contest_quiz_rom.v'),
    (Join-Path $hdl 'contest_quiz.v'),
    (Join-Path $hdl 'contest_drill_rom.v'),
    (Join-Path $hdl 'contest_drill.v'),
    (Join-Path $hdl 'contest_game_rom.v'),
    (Join-Path $hdl 'contest_game.v'),
    (Join-Path $PSScriptRoot 'tb_v27_all_in_one.v')
)

Write-Host "Compiling V27 modules with ModelSim vlog..."
& (Join-Path $ToolDirectory 'vlog.exe') -work $work ("+incdir+" + $hdl) @sources
if($LASTEXITCODE-ne 0){throw 'V27 compile failed'}

Write-Host "Running V27 simulation..."
Set-Location $BuildDirectory
& (Join-Path $ToolDirectory 'vsim.exe') -c -lib $work tb_v27_all_in_one -do 'run -all; quit -f'
if($LASTEXITCODE-ne 0){throw 'V27 simulation failed'}

Write-Host 'V27_MODELSIM_PASS'
