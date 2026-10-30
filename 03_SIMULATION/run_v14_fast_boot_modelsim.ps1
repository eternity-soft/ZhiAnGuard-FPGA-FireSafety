$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$hdl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source'
$work=Join-Path $env:TEMP ('v14_fast_boot_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    & vlib (Join-Path $work 'work') | Out-Null
    & vlog -work (Join-Path $work 'work') -lint `
        (Join-Path $hdl 'contest_bmp_meta_parser.v') `
        (Join-Path $hdl 'contest_bmp_scan_header.v') `
        (Join-Path $hdl 'SD\bmp_read.v') `
        (Join-Path $PSScriptRoot 'tb_fat32_fast_start.v')
    if($LASTEXITCODE-ne 0){throw 'ModelSim compile failed'}
    $lines=@(& vsim -c -lib (Join-Path $work 'work') tb_fat32_fast_start -do 'run -all; quit -f' 2>&1 | ForEach-Object{$_.ToString()})
    $lines | ForEach-Object{Write-Host $_}
    if(!($lines -match 'PASS tb_fat32_fast_start') -or ($lines -match '^# FAIL')){throw 'Fast-boot simulation failed'}
} finally {
    if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
}
