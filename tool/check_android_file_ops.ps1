param(
    [Parameter(Mandatory = $true)][string]$NdkRoot,
    [string]$WslDistribution = 'Debian'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $NdkRoot 'toolchains/llvm/prebuilt/windows-x86_64/bin/x86_64-linux-android23-clang.cmd'
$output = Join-Path $project '.dart_tool/android-file-ops-probe'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$binary = Join-Path $output 'probe'
& $compiler -static -std=c11 -Wall -Wextra -Werror "-I$project/third_party/cmp_file_ops/src" "$PSScriptRoot/android_file_ops_probe.c" -o $binary
if ($LASTEXITCODE -ne 0) { throw 'Android native file-ops probe compilation failed.' }
$linuxBinary = (& wsl.exe -d $WslDistribution --exec wslpath -a $binary).Trim()
if ($LASTEXITCODE -ne 0 -or -not $linuxBinary) { throw 'Could not map the probe path into WSL.' }
& wsl.exe -d $WslDistribution --exec $linuxBinary
if ($LASTEXITCODE -ne 0) { throw 'Android native file-ops probe failed.' }
