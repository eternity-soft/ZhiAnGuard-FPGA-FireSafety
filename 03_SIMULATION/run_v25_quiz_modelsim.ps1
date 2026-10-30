param(
    [string]$ToolDirectory='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem',
    [string]$BuildDirectory=''
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$BuildDirectory){
    $BuildDirectory=Join-Path ([IO.Path]::GetTempPath()) ('v25_quiz_'+[guid]::NewGuid().ToString('N'))
}
$hdl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source'
$work=Join-Path $BuildDirectory 'work'
New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null

# Copy hex files into simulation directory so $readmemh finds them
Copy-Item (Join-Path $hdl 'quiz_text.hex') (Join-Path $BuildDirectory 'quiz_text.hex') -Force
Copy-Item (Join-Path $hdl 'quiz_font.hex') (Join-Path $BuildDirectory 'quiz_font.hex') -Force

& (Join-Path $ToolDirectory 'vlib.exe') $work | Out-Null
$sources=@(
    (Join-Path $hdl 'contest_quiz_rom.v'),
    (Join-Path $hdl 'contest_quiz.v'),
    (Join-Path $PSScriptRoot 'tb_contest_quiz.v')
)

Write-Host "Compiling V25 Quiz modules with ModelSim vlog..."
# Pass +incdir+$hdl so contest_quiz_mini.v is found
& (Join-Path $ToolDirectory 'vlog.exe') -work $work ("+incdir+" + $hdl) @sources
if($LASTEXITCODE-ne 0){throw 'V25 quiz compile failed'}

Write-Host "Running simulation..."
Set-Location $BuildDirectory
& (Join-Path $ToolDirectory 'vsim.exe') -c -lib $work tb_contest_quiz -do 'run -all; quit -f'
if($LASTEXITCODE-ne 0){throw 'V25 quiz simulation failed'}

Write-Host 'V25_QUIZ_MODELSIM_PASS'
