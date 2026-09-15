param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [switch]$Package
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $PSScriptRoot 'QuickToggle.Windows/QuickToggle.Windows.csproj'
$output = Join-Path $root "build/windows/$Runtime"
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$revision = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot read source revision.' }
$changes = & git -C $root status --porcelain -- windows VERSION
if ($changes) { $revision += '-dirty' }
New-Item -ItemType Directory -Force -Path $output | Out-Null
& dotnet build $project -c Release -r $Runtime --self-contained false "-p:SourceRevisionId=$revision"
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
$dll = Join-Path $PSScriptRoot "QuickToggle.Windows/bin/Release/net10.0-windows/$Runtime/QuickToggle.dll"
& dotnet $dll --self-test
if ($LASTEXITCODE -ne 0) { throw 'Windows self-tests failed.' }
& dotnet $dll --ui-smoke-test (Join-Path $output 'checks')
if ($LASTEXITCODE -ne 0) { throw 'Windows UI smoke test failed.' }
if (!$Package) { exit 0 }
$publish = Join-Path $output 'publish'
& dotnet publish $project -c Release -r $Runtime --self-contained true -o $publish '-p:PublishSingleFile=true' '-p:IncludeNativeLibrariesForSelfExtract=true' '-p:EnableCompressionInSingleFile=true' "-p:SourceRevisionId=$revision"
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
$executable = Join-Path $publish 'QuickToggle.exe'
$binary = Get-Item $executable
if ($binary.VersionInfo.FileVersion -ne "$version.0") { throw 'Executable version mismatch.' }
if (!$binary.VersionInfo.ProductVersion.Contains($revision)) { throw 'Executable source revision mismatch.' }
# Run the actual self-contained EXE, not just the framework-dependent test build.
$process = Start-Process -FilePath $executable -ArgumentList '--self-test' -PassThru -Wait -NoNewWindow
if ($process.ExitCode -ne 0) { throw 'Packaged executable self-tests failed.' }
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $publish 'LICENSE.txt')
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $publish 'README.md')
$manifest = [ordered]@{
    version = "$version-windows-preview.1"
    sourceRevision = $revision
    runtime = $Runtime
    selfContained = $true
    authenticodeSigned = $false
    executableSha256 = (Get-FileHash $executable -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $publish 'build-manifest.json') -Encoding utf8
$archive = Join-Path $output "QuickToggle-$version-windows-preview.1-$Runtime.zip"
Compress-Archive -Path "$publish/*" -DestinationPath $archive -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
try {
    foreach ($required in @('QuickToggle.exe', 'README.md', 'LICENSE.txt', 'build-manifest.json')) {
        if ($null -eq $zip.GetEntry($required)) { throw "Missing archive entry: $required" }
    }
} finally { $zip.Dispose() }
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([System.IO.Path]::GetFileName($archive))" | Set-Content (Join-Path $output "SHA256SUMS-$Runtime.txt") -Encoding utf8
Write-Output "Verified package: $archive"
