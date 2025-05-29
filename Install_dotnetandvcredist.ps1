# File: update-avd-image.ps1

$storageAccountName = "mislavfsx"
$fileShareName = "installfiles"
$storageKey = "X3VUa/Xk7Dh4MsXj9UUR+cN2uc9AOluI3ECrxMxmaIWYpvGGWChw0Dftc/6A8feRw5AsD8hK1/7v+AStV1IDmQ=="  # Replace with actual key
$driveLetter = "Z:"
$zipFileName = "SAP_ICC_Validation.zip"
$tempPath = "C:\Temp"
$localZipPath = Join-Path -Path $tempPath -ChildPath $zipFileName

# Create temp folder if it doesn't exist
if (-Not (Test-Path $tempPath)) {
    New-Item -ItemType Directory -Path $tempPath | Out-Null
}

# Mount Azure File Share
cmd.exe /c "net use $driveLetter \\$storageAccountName.file.core.windows.net\$fileShareName /user:$storageAccountName $storageKey /persistent:no"

# Copy ZIP file locally
Copy-Item -Path "$driveLetter\$zipFileName" -Destination $localZipPath -Force

# Unmount file share
cmd.exe /c "net use $driveLetter /delete /yes"

# Extract ZIP
Expand-Archive -Path $localZipPath -DestinationPath $tempPath -Force

# Install all executables
$executables = @(
    "dotnet-sdk-8.0.410-win-x64.exe",
    "vc_redist.x64.exe",
    "vc_redist.x86.exe"
)

foreach ($exe in $executables) {
    $exePath = Join-Path -Path $tempPath -ChildPath $exe
    if (Test-Path $exePath) {
        Write-Host "Installing $exe..."
        Start-Process -FilePath $exePath -ArgumentList "/quiet", "/norestart" -Wait
    } else {
        Write-Warning "$exe not found in $tempPath"
    }
}

# Cleanup
Remove-Item -Path $tempPath -Recurse -Force
