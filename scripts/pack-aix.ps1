param(
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$versionFile = Join-Path $projectRoot 'VERSION'
$version = if (Test-Path -LiteralPath $versionFile) {
  (Get-Content -LiteralPath $versionFile -Raw).Trim()
} else {
  'dev'
}

$versionDirName = [string]::Concat([char[]](0x7248, 0x672C, 0x7BA1, 0x7406))
$outDir = Join-Path $projectRoot $versionDirName
$outFile = Join-Path $outDir "SkyMate-v$version.aix"
$tempRoot = [System.IO.Path]::GetTempPath()
$stageRoot = Join-Path $tempRoot "skymate-aix-pack-$version"
$stageFullPath = [System.IO.Path]::GetFullPath($stageRoot)
$tempFullPath = [System.IO.Path]::GetFullPath($tempRoot)

if (-not $stageFullPath.StartsWith($tempFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to use staging path outside temp: $stageFullPath"
}

if ($Clean -and (Test-Path -LiteralPath $outFile)) {
  Remove-Item -LiteralPath $outFile -Force
}

if (Test-Path -LiteralPath $stageRoot) {
  Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stageRoot | Out-Null
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$files = @('VERSION', 'app.js', 'app.json', 'manifest.json')
foreach ($file in $files) {
  Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination (Join-Path $stageRoot $file) -Force
}

Copy-Item -LiteralPath (Join-Path $projectRoot 'pages') -Destination (Join-Path $stageRoot 'pages') -Recurse -Force

$zipFile = "$outFile.zip"
if (Test-Path -LiteralPath $outFile) {
  Remove-Item -LiteralPath $outFile -Force
}
if (Test-Path -LiteralPath $zipFile) {
  Remove-Item -LiteralPath $zipFile -Force
}

Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipFile -Force
Move-Item -LiteralPath $zipFile -Destination $outFile -Force
Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Host "Packed $outFile"
