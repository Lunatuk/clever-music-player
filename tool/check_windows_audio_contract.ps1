param(
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [switch]$UpdateFixture,
    [string]$NativeReleaseDirectory
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
$actualError = (& $executable error).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Native audio error contract execution failed.' }
$errorFixture = Join-Path $projectRoot 'test/fixtures/windows_player_error_event.json'
if ($UpdateFixture) {
    [IO.File]::WriteAllText($errorFixture, "$actualError`n", [Text.UTF8Encoding]::new($false))
}
if ($actualError -ne [IO.File]::ReadAllText($errorFixture).Trim()) {
    throw 'The checked-in Dart error fixture differs from the native plugin payload.'
}
Write-Output 'Native Windows player payload matches the protocol fixture.'
Write-Output 'Native Windows error payload matches the protocol fixture.'
$actualSnapshot = (& $executable snapshot).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Native playback snapshot execution failed.' }
$snapshotFixture = Join-Path $projectRoot 'test/fixtures/windows_native_playback_snapshot.json'
if ($UpdateFixture) {
    [IO.File]::WriteAllText($snapshotFixture, "$actualSnapshot`n", [Text.UTF8Encoding]::new($false))
}
if ($actualSnapshot -ne [IO.File]::ReadAllText($snapshotFixture).Trim()) {
    throw 'The checked-in snapshot fixture differs from the native plugin payload.'
}
Write-Output 'Native Windows playback snapshot matches the protocol fixture.'
$uriSource = Join-Path $PSScriptRoot 'windows_uri_test.cpp'
$uriExecutable = Join-Path $outputDirectory 'uri_test.exe'
& cl.exe /nologo /std:c++17 /EHsc /utf-8 "/I$pluginHeaders" $uriSource "/Fo$outputDirectory/uri_test.obj" "/Fe$uriExecutable"
if ($LASTEXITCODE -ne 0) { throw 'Native Windows URI test compilation failed.' }
& $uriExecutable
if ($LASTEXITCODE -ne 0) { throw 'Native Windows URI tests failed.' }
if ($NativeReleaseDirectory) {
    $release = (Resolve-Path -LiteralPath $NativeReleaseDirectory).Path
    $wrapper = Join-Path $release '../../flutter/Release/flutter_wrapper_plugin.lib'
    if (-not (Test-Path -LiteralPath $wrapper)) {
        throw 'Build a Windows release first; its Flutter wrapper library is required.'
    }
    $engine = Join-Path $FlutterRoot 'bin/cache/artifacts/engine/windows-x64'
    $probeSource = Join-Path $PSScriptRoot 'windows_native_playback_probe.cpp'
    $probeExecutable = Join-Path $outputDirectory 'native_probe.exe'
    & cl.exe /nologo /std:c++17 /EHsc /O2 /MD /utf-8 "/I$engine" "/I$headers" "/I$pluginHeaders" $probeSource "/Fo$outputDirectory/native_probe.obj" "/Fe$probeExecutable" /link $wrapper "$engine/flutter_windows.dll.lib" ole32.lib runtimeobject.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native playback probe compilation failed.' }
    & python (Join-Path $PSScriptRoot 'check_windows_native_playback.py') --executable $probeExecutable --release-directory $release --output "$outputDirectory/native_playback_results.json"
    if ($LASTEXITCODE -ne 0) { throw 'Native Windows playback tests failed.' }
}
