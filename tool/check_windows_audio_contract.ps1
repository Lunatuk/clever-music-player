param(
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [switch]$UpdateFixture
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $FlutterRoot) {
    $FlutterRoot = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
}
$headers = Join-Path $FlutterRoot 'bin/cache/artifacts/engine/windows-x64/cpp_client_wrapper/include'
if (-not (Test-Path -LiteralPath (Join-Path $headers 'flutter/encodable_value.h'))) {
    throw 'Flutter Windows headers are missing. Run flutter precache --windows first.'
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'Visual Studio C++ build tools were not found.' }
$devCmd = Join-Path $installation 'Common7/Tools/VsDevCmd.bat'
# Capture the developer environment internally; do not print environment values.
$compilerEnvironment = & cmd.exe /d /s /c "`"$devCmd`" -arch=x64 -host_arch=x64 >nul && set"
if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the MSVC environment.' }
foreach ($entry in $compilerEnvironment) {
    if ($entry -match '^(Path|INCLUDE|LIB|LIBPATH)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
$outputDirectory = Join-Path $projectRoot '.dart_tool/windows-audio-contract'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$executable = Join-Path $outputDirectory 'payload.exe'
$source = Join-Path $PSScriptRoot 'windows_player_data_fixture.cpp'
$pluginHeaders = Join-Path $projectRoot 'third_party/just_audio_windows/windows'
& cl.exe /nologo /std:c++17 /EHsc /utf-8 "/I$headers" "/I$pluginHeaders" $source "/Fo$outputDirectory/payload.obj" "/Fe$executable"
if ($LASTEXITCODE -ne 0) { throw 'Native audio contract compilation failed.' }
$actual = (& $executable).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Native audio contract execution failed.' }
$fixture = Join-Path $projectRoot 'test/fixtures/windows_player_settings_event.json'
if ($UpdateFixture) {
    [IO.File]::WriteAllText($fixture, "$actual`n", [Text.UTF8Encoding]::new($false))
}
$expected = [IO.File]::ReadAllText($fixture).Trim()
if ($actual -ne $expected) { throw 'The checked-in Dart fixture differs from the native plugin payload.' }
Write-Output 'Native Windows player payload matches the protocol fixture.'
