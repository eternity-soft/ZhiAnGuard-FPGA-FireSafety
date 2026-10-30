param(
    [string]$ToolDirectory='D:\Anlogic\bin',
    [string]$BuildDirectory=(Join-Path $env:TEMP ('V27_BUILD_'+[guid]::NewGuid().ToString('N').Substring(0,8)))
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$project=Join-Path $root '02_FPGA_PROJECT'
$tool=Join-Path $ToolDirectory 'td_commands_prompt.exe'
if(!(Test-Path -LiteralPath $tool)){throw 'TD command tool not found; set -ToolDirectory.'}
if(Test-Path -LiteralPath $BuildDirectory){
    throw 'Build directory already exists; choose a new empty path with -BuildDirectory.'
}

$projectFiles=@(Get-ChildItem -LiteralPath $project -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]td_project[\\/]log[\\/]' -and
    $_.FullName -notmatch '_Runs[\\/]'
})
$hashes=@{}
foreach($f in $projectFiles){
    $hashes[$f.FullName]=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
}
New-Item -ItemType Directory -Path $BuildDirectory -Force | Out-Null
$buildProject=Join-Path $BuildDirectory '02_FPGA_PROJECT'
New-Item -ItemType Directory -Path $buildProject -Force | Out-Null
foreach($f in $projectFiles){
    $relative=$f.FullName.Substring($project.Length+1)
    $copyTo=Join-Path $buildProject $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $copyTo) -Force | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $copyTo
}
$script=Join-Path $BuildDirectory '02_FPGA_PROJECT\src\td_project\build_v27.tcl'
$started=[DateTime]::UtcNow
$lines=@(& $tool ($script.Replace('\','/')) 2>&1 | ForEach-Object{$_.ToString()})
$code=$LASTEXITCODE
$logs=Join-Path $root '05_BUILD_REPORTS'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
[IO.File]::WriteAllLines((Join-Path $logs 'td_build.log'),$lines,[Text.UTF8Encoding]::new($false))
if($code-ne 0 -or !($lines -contains 'V27_BUILD_PASS') -or ($lines | Where-Object{$_ -like 'V27_BUILD_FAILED*'})){
    throw ('TD build failed; inspect '+(Join-Path $logs 'td_build.log'))
}
$out=Join-Path (Split-Path -Parent $script) 'v27_build'
$bit=Join-Path $out 'V27_FIRE_ALL_IN_ONE.bit'
if(!(Test-Path -LiteralPath $bit) -or (Get-Item -LiteralPath $bit).LastWriteTimeUtc-lt $started){
    throw 'No newly generated V27 bitstream.'
}
foreach($f in $hashes.Keys){
    if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash-ne $hashes[$f]){
        throw ('Source changed during build: '+$f)
    }
}
$program=Join-Path $root '04_PROGRAM_FILES'
New-Item -ItemType Directory -Path $program -Force | Out-Null
$finalBit=Join-Path $program 'V27_FIRE_ALL_IN_ONE.bit'
Copy-Item -LiteralPath $bit -Destination $finalBit
foreach($f in Get-ChildItem -LiteralPath $out -File){
    if($f.Extension-in @('.area','.timing','.status','.ts')){Copy-Item -LiteralPath $f.FullName -Destination $logs}
}
$manifest=[Collections.Generic.List[string]]::new()
foreach($f in ($hashes.Keys | Sort-Object)){
    $manifest.Add($hashes[$f]+'  '+$f.Substring($root.Length+1))
}
$manifest.Add((Get-FileHash -LiteralPath $finalBit -Algorithm SHA256).Hash+'  04_PROGRAM_FILES\V27_FIRE_ALL_IN_ONE.bit')
[IO.File]::WriteAllLines((Join-Path $logs 'build_input_bit_SHA256.txt'),$manifest,[Text.UTF8Encoding]::new($false))
Write-Host 'V27 Fire Safety All-in-One bitstream generated successfully!'
Get-Content -LiteralPath (Join-Path $logs 'V27_flow.status') | Select-Object -First 12
