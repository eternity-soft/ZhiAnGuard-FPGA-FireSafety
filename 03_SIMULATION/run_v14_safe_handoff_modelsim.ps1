param(
    [string]$ToolDirectory='D:\ModelSim\altera\14.1\modelsim_ase\win32aloem',
    [string]$BuildDirectory='',
    [string]$LogPath=''
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$BuildDirectory){$BuildDirectory=Join-Path ([IO.Path]::GetTempPath()) ('v14_safe_handoff_'+[guid]::NewGuid().ToString('N'))}
if(!$LogPath){$LogPath=Join-Path $root '05_BUILD_REPORTS\V14_safe_handoff_modelsim.log'}
$vlib=Join-Path $ToolDirectory 'vlib.exe'
$vlog=Join-Path $ToolDirectory 'vlog.exe'
$vsim=Join-Path $ToolDirectory 'vsim.exe'
foreach($tool in @($vlib,$vlog,$vsim)){if(!(Test-Path -LiteralPath $tool)){throw "Missing ModelSim tool: $tool"}}
New-Item -ItemType Directory -Force -Path $BuildDirectory,(Split-Path -Parent $LogPath) | Out-Null
$hdl=Join-Path $root '02_FPGA_PROJECT\src\user_source\hdl_source'
$tests=@(
    @{Name='tb_smooth_cache';Files=@((Join-Path $hdl 'SD\contest_sd_card_bmp.v'),(Join-Path $hdl 'SD\frame_fifo_read.v'),(Join-Path $hdl 'my_fade.v'),(Join-Path $PSScriptRoot 'tb_smooth_cache.v'))},
    @{Name='tb_cache_addresses';Files=@((Join-Path $hdl 'SD\my_frame_fifo_write.v'),(Join-Path $PSScriptRoot 'tb_cache_addresses.v'))},
    @{Name='tb_fade_modes';Files=@((Join-Path $hdl 'my_fade.v'),(Join-Path $PSScriptRoot 'tb_fade_modes.v'))},
    @{Name='tb_contest_image_scaler_quality';Files=@((Join-Path $hdl 'contest_image_scaler.v'),(Join-Path $PSScriptRoot 'tb_contest_image_scaler_quality.v'))}
)
$lines=[Collections.Generic.List[string]]::new()
function Record([string]$line){$lines.Add($line);Write-Host $line}
try {
    Record 'V14 SafeFrameHandoff: ModelSim functional regression'
    foreach($test in $tests){
        $work=Join-Path $BuildDirectory ('work_'+$test.Name)
        & $vlib $work | Out-Null
        Record ('COMPILE '+$test.Name)
        $compile=@(& $vlog -work $work -lint @($test.Files) 2>&1 | ForEach-Object{$_.ToString()})
        foreach($line in $compile){Record $line}
        if($LASTEXITCODE-ne 0){throw ('ModelSim compile failed: '+$test.Name)}
        Record ('RUN '+$test.Name)
        $result=@(& $vsim -c -lib $work $test.Name -do 'run -all; quit -f' 2>&1 | ForEach-Object{$_.ToString()})
        foreach($line in $result){Record $line}
        if($LASTEXITCODE-ne 0 -or ($result | Where-Object{$_ -match '^#?\s*(FAIL|FATAL|ERROR)\b'})){
            throw ('ModelSim test failed: '+$test.Name)
        }
        if(!($result | Where-Object{$_ -match ('PASS '+[regex]::Escape($test.Name)+'\b')})){
            throw ('Missing PASS marker: '+$test.Name)
        }
    }
    Record ('SOURCE SHA256: '+(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $hdl 'SD\contest_sd_card_bmp.v')).Hash+'  contest_sd_card_bmp.v')
    Record ('SOURCE SHA256: '+(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $hdl 'my_fade.v')).Hash+'  my_fade.v')
    Record 'ALL 4 V14 CACHE SAFE-HANDOFF FADE QUALITY MODELSIM TESTS PASS'
} catch {
    Record ('RUN FAILED: '+$_.Exception.Message)
    throw
} finally {
    [IO.File]::WriteAllLines($LogPath,$lines,[Text.UTF8Encoding]::new($false))
}
