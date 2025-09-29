$URL = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
$DownloadURL = (Invoke-WebRequest -Uri $URL).Content | ConvertFrom-Json | `
    Select-Object -ExpandProperty assets | `
    Where-Object browser_download_url -Match '.msixbundle' | `
    Select-Object -ExpandProperty browser_download_url

Invoke-WebRequest -Uri $DownloadURL -OutFile "Setup.msix"
Add-AppxPackage -Path "Setup.msix"
Remove-Item "Setup.msix"