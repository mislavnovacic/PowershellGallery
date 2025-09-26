# Wrapper-Install-NotepadPP.ps1
$main = 'https://raw.githubusercontent.com/mislavnovacic/PowershellGallery/refs/heads/main/InstallNotepadplusplus.ps1'
$tmp = Join-Path $env:TEMP 'Install-NotepadPP.ps1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Invoke-WebRequest -Uri $main -OutFile $tmp -UseBasicParsing
# Pin a version to avoid winget
powershell.exe -ExecutionPolicy Bypass -File $tmp -Version 8.7.6 -Verbose