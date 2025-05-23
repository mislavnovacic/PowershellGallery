# Define target folder and installer details
$targetDir = "C:\WinAppSDKInstaller"
$installerUrl = "https://aka.ms/windowsappsdk/1.4/1.4.240802001/windowsappruntimeinstall-x64.exe"
$installerPath = Join-Path $targetDir "windowsappruntimeinstall-x64.exe"

# Create the directory if it doesn't exist
if (-Not (Test-Path -Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# Download the installer
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

# Install silently
Start-Process -FilePath $installerPath #-ArgumentList "/quiet /norestart" -Wait -NoNewWindow

# Optional: Clean up
Remove-Item $installerPath -Force