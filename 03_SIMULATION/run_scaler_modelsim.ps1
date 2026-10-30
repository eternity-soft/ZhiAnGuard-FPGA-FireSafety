param(
    [string]$ToolDirectory='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem',
    [string]$BuildDirectory='',
    [string]$LogPath=''
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$BuildDirectory){$BuildDirectory=Join-Path ([IO.Path]::GetTempPath()) ('v11_quality_modelsim_'+[guid]::NewGuid().ToString('N'))}
if(!$LogPath){$LogPath=Join-Path $root '05_BUILD_REPORTS\V11_quality_scaler_modelsim.log'}
$vlib=Join-Path $ToolDirectory 'vlib.exe'
$vlog=Join-Path $ToolDirectory 'vlog.exe'
$vsim=Join-Path $ToolDirectory 'vsim.exe'
foreach($tool in @($vlib,$vlog,$vsim)){if(!(Test-Path -LiteralPath $tool)){throw "Missing ModelSim tool: $tool"}}
New-Item -ItemType Directory -Force -Path $BuildDirectory,(Split-Path -Parent $LogPath) | Out-Null
$work=Join-Path $BuildDirectory 'work'
& $vlib $work | Out-Null
$hdl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source'
$rtl=@('contest_bmp_meta_parser.v','contest_bmp_scan_header.v','contest_image_scaler.v',
       'contest_scaler_bridge.v','contest_scaler_cdc.v','SD\bmp_read.v','SD\contest_sd_card_bmp.v') | ForEach-Object{Join-Path $hdl $_}
$tbs=Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.v' | ForEach-Object{$_.FullName}
$tests=@('tb_contest_scaler_cdc','tb_bmp_read_dynamic','tb_bmp_scan_header','tb_v08_bridge_range',
         'tb_contest_bmp_meta_parser','tb_contest_image_scaler_quality','tb_v08_chain')
$lines=[Collections.Generic.List[string]]::new()
function Record([string]$line){$lines.Add($line);Write-Host $line}
try {
    Record 'V11 QualityScaler: ModelSim functional regression'
    $compile=@(& $vlog -work $work -lint @rtl @tbs 2>&1 | ForEach-Object{$_.ToString()})
    foreach($line in $compile){Record $line}
    if($LASTEXITCODE-ne 0){throw 'ModelSim compile failed'}
    foreach($test in $tests){
        Record ("RUN $test")
        $result=@(& $vsim -c -lib $work $test -do 'run -all; quit -f' 2>&1 | ForEach-Object{$_.ToString()})
        foreach($line in $result){Record $line}
        if($LASTEXITCODE-ne 0 -or ($result | Where-Object{$_ -match '^#?\s*(FAIL|FATAL|ERROR)\b'})){
            throw "ModelSim test failed: $test"
        }
        if(!($result | Where-Object{$_ -match ('PASS '+[regex]::Escape($test)+'\b')})){
            throw "Missing PASS marker: $test"
        }
    }
    Record ('SOURCE SHA256: '+(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $hdl 'SD\bmp_read.v')).Hash+'  bmp_read.v')
    Record ('SOURCE SHA256: '+(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $hdl 'anlogic_topic1_hdmi_media_top.v')).Hash+'  anlogic_topic1_hdmi_media_top.v')
    Record 'ALL 7 V11 QUALITY SCALER MODELSIM TESTS PASS'
} catch {
    Record ('RUN FAILED: '+$_.Exception.Message)
    throw
} finally {
    [IO.File]::WriteAllLines($LogPath,$lines,[Text.UTF8Encoding]::new($false))
}
