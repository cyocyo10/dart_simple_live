# Windows-native smoke test: a probe runtime verifies cwd, Unicode arguments,
# exit-code forwarding and a second process launched directly from runtime.
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('Simple Live 封装验证 ' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  $release = Join-Path $testRoot 'release'
  New-Item -ItemType Directory -Path "$release/data/flutter_assets" -Force | Out-Null
  Set-Content -LiteralPath "$release/data/icudtl.dat" -Value 'probe'
  Set-Content -LiteralPath "$release/flutter_windows.dll" -Value 'probe'
  $source = Join-Path $testRoot 'probe.cs'
  @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
class Probe {
  static int Main(string[] args) {
    if (args.Length != 3) return 40;
    File.WriteAllLines(args[1] + (args[0] == "--child" ? ".child" : ".parent"),
        new string[] { Environment.CurrentDirectory, args[2] });
    if (args[0] == "--child") return 0;
    var info = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location,
        "--child \"" + args[1] + "\" \"" + args[2] + "\"");
    info.UseShellExecute = false;
    using (var child = Process.Start(info)) {
      child.WaitForExit();
      if (child.ExitCode != 0) return 41;
    }
    return 23;
  }
}
'@ | Set-Content -LiteralPath $source -Encoding utf8
  $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
  & $csc /nologo /target:exe "/out:$release/simple_live_app.exe" $source
  if ($LASTEXITCODE -ne 0) { throw 'Runtime probe compilation failed.' }
  $launcher = "$PSScriptRoot/../../build/launcher/Simple Live.exe"
  & "$PSScriptRoot/package-portable.ps1" -ReleaseDirectory $release -OutputDirectory "$testRoot/output" -LauncherExecutable $launcher
  $bundle = Join-Path $testRoot 'output/SimpleLive'
  $rootEntries = @(Get-ChildItem -LiteralPath $bundle)
  if ($rootEntries.Count -ne 3 -or @(Get-ChildItem -LiteralPath $bundle -Filter '*.exe').Count -ne 1) { throw 'Portable root contains unexpected loose files.' }
  $result = Join-Path $testRoot '探针结果'
  $unicode = '参数 with spaces 中文'
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = Join-Path $bundle 'Simple Live.exe'
  $start.WorkingDirectory = $testRoot # Deliberately unrelated to runtime.
  $start.Arguments = "--probe `"$result`" `"$unicode`""
  $start.UseShellExecute = $false
  $process = [Diagnostics.Process]::Start($start)
  if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Launcher timed out.' }
  if ($process.ExitCode -ne 23) { throw 'Launcher did not forward the runtime exit code.' }
  foreach ($kind in @('parent', 'child')) {
    $lines = Get-Content -LiteralPath "$result.$kind"
    if ($lines[0] -ne (Join-Path $bundle 'runtime') -or $lines[1] -ne $unicode) {
      throw "$kind process did not preserve cwd or Unicode arguments."
    }
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archives = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'output') -Filter 'SimpleLive-*-Windows-Portable.zip')
  if ($archives.Count -ne 1) { throw 'Missing versioned portable ZIP.' }
  $pubspec = Get-Content -LiteralPath "$PSScriptRoot/../../pubspec.yaml" -Raw
  if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$') { throw 'Missing app version.' }
  if ($archives[0].Name -ne "SimpleLive-$($Matches[1])-Windows-Portable.zip") { throw 'Portable ZIP version does not match the app.' }
  $zip = [IO.Compression.ZipFile]::OpenRead($archives[0].FullName)
  try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    if ('Simple Live.exe' -notin $names -or 'runtime/simple_live_app.exe' -notin $names) { throw 'ZIP layout is invalid.' }
  } finally { $zip.Dispose() }
  Write-Output 'PASS: portable layout, Unicode paths/arguments, cwd, child process and exit code.'
} finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
