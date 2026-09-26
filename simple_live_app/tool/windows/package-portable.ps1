[CmdletBinding()]
param(
  [string]$ReleaseDirectory = "$PSScriptRoot/../../build/windows/x64/runner/Release",
  [string]$OutputDirectory = "$PSScriptRoot/../../build/dist/windows-portable",
  [string]$LauncherExecutable = ""
)
$ErrorActionPreference = 'Stop'
$release = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
foreach ($required in @('simple_live_app.exe', 'flutter_windows.dll', 'data/flutter_assets', 'data/icudtl.dat')) {
  if (-not (Test-Path -LiteralPath (Join-Path $release $required))) { throw "Incomplete Flutter release: $required" }
}
if (-not $LauncherExecutable) {
  $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
  $msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild/**/Bin/MSBuild.exe' | Select-Object -First 1
  if (-not $msbuild) { throw 'Visual Studio MSBuild with C++ desktop tools is required.' }
  & $msbuild "$PSScriptRoot/launcher.vcxproj" /p:Configuration=Release /p:Platform=x64 /nologo /verbosity:minimal
  if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed.' }
  $LauncherExecutable = "$PSScriptRoot/../../build/launcher/Simple Live.exe"
}
$launcher = (Resolve-Path -LiteralPath $LauncherExecutable).Path
$out = [IO.Path]::GetFullPath($OutputDirectory)
# Guard against a mistyped output deleting the source/build or a user's directory.
if ($out.TrimEnd('\', '/') -eq $release.TrimEnd('\', '/') -or $release.StartsWith($out.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($release.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Output must not contain the Flutter release directory.'
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$bundle = Join-Path $out 'SimpleLive'
if (Test-Path -LiteralPath $bundle) {
  if (-not (Test-Path -LiteralPath (Join-Path $bundle '.simple-live-portable'))) { throw 'Refusing to replace an unrecognized directory.' }
  Remove-Item -LiteralPath $bundle -Recurse -Force
}
$runtime = Join-Path $bundle 'runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
Get-ChildItem -LiteralPath $release -Force | Copy-Item -Destination $runtime -Recurse -Force
Copy-Item -LiteralPath $launcher -Destination (Join-Path $bundle 'Simple Live.exe')
Copy-Item -LiteralPath "$PSScriptRoot/portable-readme.txt" -Destination (Join-Path $bundle '使用说明.txt')
Set-Content -LiteralPath (Join-Path $bundle '.simple-live-portable') -Value 'Simple Live portable v1' -Encoding utf8
# The marker is hidden on Windows and is used only for safe package regeneration.
(Get-Item -LiteralPath (Join-Path $bundle '.simple-live-portable')).Attributes = 'Hidden'
# Include both the display version and build number in downloaded packages.
$pubspec = Get-Content -LiteralPath "$PSScriptRoot/../../pubspec.yaml" -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$') { throw 'Missing app version.' }
$packageVersion = $Matches[1]
Add-Content -LiteralPath (Join-Path $bundle '使用说明.txt') -Value "`n版本：$packageVersion" -Encoding utf8
$zip = Join-Path $out "SimpleLive-$packageVersion-Windows-Portable.zip"
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -Force
Write-Output $zip
