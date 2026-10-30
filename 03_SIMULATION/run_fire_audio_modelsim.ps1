param([string]$ModelSimBin='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sim=$PSScriptRoot
$rtl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source\contest_fire_audio_linkage_engine.v'
$tb=Join-Path $sim 'tb_contest_fire_audio_linkage_engine.v'
$work=Join-Path $sim 'work_fire_audio'
Push-Location $sim
try {
    if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
    & (Join-Path $ModelSimBin 'vlib.exe') $work
    & (Join-Path $ModelSimBin 'vmap.exe') work $work
    & (Join-Path $ModelSimBin 'vlog.exe') -work work $rtl $tb
    if($LASTEXITCODE-ne 0){throw 'V07 fire audio compile failed.'}
    $lines=@(& (Join-Path $ModelSimBin 'vsim.exe') -c work.tb_contest_fire_audio_linkage_engine -do 'run -all; quit -f' 2>&1 | ForEach-Object{$_.ToString()})
    [IO.File]::WriteAllLines((Join-Path $sim 'fire_audio_modelsim.log'),$lines,[Text.UTF8Encoding]::new($false))
    if($LASTEXITCODE-ne 0 -or !($lines | Where-Object{$_ -like '*V08_FIRE_AUDIO_INHERIT_PASS*'})){
        throw 'V08 inherited fire audio simulation failed; inspect fire_audio_modelsim.log.'
    }
    Write-Host ($lines | Where-Object{$_ -like '*V08_FIRE_AUDIO_INHERIT_PASS*'})
} finally {
    Pop-Location
}
