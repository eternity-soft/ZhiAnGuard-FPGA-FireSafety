param([string]$ModelSimBin='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$rtl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source\contest_status_osd.v'
$tb=Join-Path $PSScriptRoot 'tb_contest_status_osd_clock_scroll.v'
$work=Join-Path ([IO.Path]::GetTempPath()) ('v09_osd_'+[guid]::NewGuid().ToString('N'))
$log=Join-Path $PSScriptRoot 'osd_clock_scroll_modelsim.log'
New-Item -ItemType Directory -Path $work | Out-Null
& (Join-Path $ModelSimBin 'vlib.exe') (Join-Path $work 'work') | Out-Null
$compile=@(& (Join-Path $ModelSimBin 'vlog.exe') -work (Join-Path $work 'work') $rtl $tb 2>&1 | ForEach-Object{$_.ToString()})
if($LASTEXITCODE-ne 0){throw 'V10 OSD compile failed.'}
$lines=@(& (Join-Path $ModelSimBin 'vsim.exe') -c -lib (Join-Path $work 'work') tb_contest_status_osd_clock_scroll -do 'run -all; quit -f' 2>&1 | ForEach-Object{$_.ToString()})
[IO.File]::WriteAllLines($log,$lines,[Text.UTF8Encoding]::new($false))
if($LASTEXITCODE-ne 0 -or ($lines | Where-Object{$_ -match '^#?\s*FAIL\b'}) -or
   !($lines | Where-Object{$_ -like '*PASS tb_contest_status_osd_clock_scroll*'})){
    throw 'V10 OSD simulation failed; inspect osd_clock_scroll_modelsim.log.'
}
Write-Host ($lines | Where-Object{$_ -like '*PASS tb_contest_status_osd_clock_scroll*'})
