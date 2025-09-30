New-Item -Type Directory -Path 'C:\ImageBuilder' -Force
Invoke-WebRequest -Uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile 'C:\ImageBuilder\azcopy.zip'
Expand-Archive -Path 'C:\ImageBuilder\azcopy.zip' -DestinationPath 'C:\ImageBuilder' -Force
$azcopyFolder = Get-ChildItem -Path 'C:\ImageBuilder' -Directory | Where-Object { $_.Name -like 'azcopy_windows_amd64_*' }
Copy-Item -Path "$($azcopyFolder.FullName)\azcopy.exe" -Destination 'C:\ImageBuilder' -Force
Remove-Item -Path 'C:\ImageBuilder\azcopy.zip' -Force
