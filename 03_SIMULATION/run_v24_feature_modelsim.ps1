param(
    [string]$ToolDirectory='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem',
    [string]$BuildDirectory=''
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$BuildDirectory){
    $BuildDirectory=Join-Path ([IO.Path]::GetTempPath()) ('v24_feature_'+[guid]::NewGuid().ToString('N'))
}
$hdl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source'
$work=Join-Path $BuildDirectory 'work'
New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null
& (Join-Path $ToolDirectory 'vlib.exe') $work | Out-Null
$sources=@(
    (Join-Path $hdl 'contest_audio_meter.v'),
    (Join-Path $hdl 'contest_fire_audio_linkage_engine.v'),
    (Join-Path $hdl 'contest_status_osd.v'),
    (Join-Path $hdl 'contest_edge_detect.v'),
    (Join-Path $hdl 'contest_pixel_anomaly_watchdog.v'),
    (Join-Path $PSScriptRoot 'reference_fire_audio_engine.v'),
    (Join-Path $PSScriptRoot 'tb_audio_meter.v'),
    (Join-Path $PSScriptRoot 'tb_audio_meter_equivalence.v'),
    (Join-Path $PSScriptRoot 'tb_audio_meter_osd.v'),
    (Join-Path $PSScriptRoot 'tb_edge_detect.v'),
    (Join-Path $PSScriptRoot 'tb_watchdog.v')
)
& (Join-Path $ToolDirectory 'vlog.exe') -work $work @sources
if($LASTEXITCODE-ne 0){throw 'V24 feature compile failed'}
foreach($tb in @('tb_audio_meter','tb_audio_meter_equivalence','tb_audio_meter_osd','tb_edge_detect','tb_watchdog')){
    Write-Host ('RUN '+$tb)
    & (Join-Path $ToolDirectory 'vsim.exe') -c -lib $work $tb -do 'run -all; quit -f'
    if($LASTEXITCODE-ne 0){throw ('V24 feature test failed: '+$tb)}
}
Write-Host 'V24_FEATURE_MODELSIM_PASS'
