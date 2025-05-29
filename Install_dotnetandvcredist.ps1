# PowerShell script to automate AVD image update with robust dotnet download

$tempDir = "$env:TEMP\avd_update_temp"
$ErrorActionPreference = "Stop"

$files = @(
    @{ Name = "dotnet-sdk-8.0.410-win-x64.exe"; Url = "https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.300/dotnet-sdk-9.0.300-win-x64.exe"; MinSizeMB = 100 },
    @{ Name = "vc_redist.x64.exe"; Url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"; MinSizeMB = 25 },
    @{ Name = "vc_redist.x86.exe"; Url = "https://aka.ms/vs/17/release/vc_redist.x86.exe" }
)

function Safe-Download($url, $path, $minSizeMB, $fileName, $retries = 5) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -TimeoutSec 600
            Start-Sleep -Seconds 2
            $fileInfo = Get-Item $path -ErrorAction Stop
            $expectedSize = $minSizeMB * 1MB
            if ($fileInfo.Length -gt $expectedSize -or ($fileName -like "vc_redist*" -and $fileInfo.Length -gt 25000000)) {
                return
            }
            Write-Host "File size too small: $($fileInfo.Length) bytes. Expected at least $expectedSize bytes. Retrying..."
        } catch {
            Write-Host "Attempt $($i + 1) failed with error: $($_.Exception.Message). Retrying..."
        }
        Remove-Item -Force -ErrorAction SilentlyContinue $path
        Start-Sleep -Seconds 5
    }
    throw "Failed to download $url after $retries attempts."
}

if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
New-Item -ItemType Directory -Path $tempDir | Out-Null

foreach ($file in $files) {
    $targetPath = Join-Path $tempDir $file.Name
    Write-Host "Downloading $($file.Name)..."
    Safe-Download -url $file.Url -path $targetPath -minSizeMB $file.MinSizeMB -fileName $file.Name
}

foreach ($file in $files) {
    $installerPath = Join-Path $tempDir $file.Name
    Write-Host "Installing $($file.Name)..."
    Start-Process -FilePath $installerPath -ArgumentList "/install /quiet /norestart" -Wait -NoNewWindow
}

Write-Host "Cleaning up..."
Remove-Item -Recurse -Force $tempDir
Write-Host "AVD update completed successfully."
