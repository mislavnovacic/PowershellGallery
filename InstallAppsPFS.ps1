# AIB customization: download, unzip, and install multiple PSADT apps from Blob SAS URLs (fully non‑interactive)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# Stable working root for AIB
$StageRoot = 'C:\AIB\Stage'
if (-not (Test-Path $StageRoot)) { New-Item -Path $StageRoot -ItemType Directory -Force | Out-Null }

function Invoke-AppInstallFromSas {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ZipUrl
  )

  # 1) Download your PSADT bundle (your original flow, generalized)
  $Stage   = Join-Path $StageRoot $Name
  $ZipPath = Join-Path $Stage ("{0}_PSADT.zip" -f $Name)
  New-Item -Path $Stage -ItemType Directory -Force | Out-Null

  # Sanity (order-agnostic; don't fail on &sv=...)
  if ($ZipUrl -notmatch '(?:\?|&)sr=b(?:&|$)' -or 
      $ZipUrl -notmatch '(?:\?|&)sp=[^&]*r[^&]*(?:&|$)' -or 
      $ZipUrl -notmatch '(?:\?|&)sv=[^&]+')
  {
    throw "[$Name] ZipUrl must be a blob SAS with read permission (sr=b, sp includes r) and include sv=."
  }

  # Fail fast on a bad token
  Invoke-WebRequest -Uri $ZipUrl -Method Head -UseBasicParsing | Out-Null

  # Download + unzip
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $Stage -Force

  # Find PSADT entry point even if the zip adds a folder
  $deploy = Get-ChildItem -Path $Stage -Filter 'Deploy-Application.ps1' -Recurse -File | Select-Object -First 1
  if (-not $deploy) { throw "[$Name] Deploy-Application.ps1 not found under $Stage" }

  # Run PSADT with zero UI: hide console window + PowerShell -NonInteractive + PSADT -DeployMode NonInteractive
  $argList = @(
    '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
    '-File', $deploy.FullName,
    '-DeploymentType','Install','-DeployMode','NonInteractive'
  )

  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -WorkingDirectory $deploy.Directory.FullName -Wait -PassThru
  if ($proc.ExitCode -ne 0) { throw "[$Name] PSADT failed with exit code $($proc.ExitCode)." }

  # Cleanup
  Remove-Item $Stage -Recurse -Force
}

# --- Add your apps here ---
$Apps = @(
  @{ Name = '7zip'; ZipUrl = 'https://avdmgmdeployapps.blob.core.windows.net/deployapps/7Zip.zip?sp=r&st=2025-10-03T06:34:11Z&se=2030-10-03T14:49:11Z&spr=https&sv=2024-11-04&sr=b&sig=HwWKhi7eFydYsStsle7QmS1J3xEkygYiETaEaO8QGok%3D' }
  @{ Name = 'NotepadPlusPlus'; ZipUrl = 'https://avdmgmdeployapps.blob.core.windows.net/scripts/InstallAppsPFS.ps1?sp=r&st=2025-10-03T13:26:28Z&se=2030-10-03T21:41:28Z&spr=https&sv=2024-11-04&sr=b&sig=KrXJH1Yta4ulsf4Jcse2%2BGngI1y%2FsvNYaJJ8jOgJeDs%3D' }
  # ,@{ Name = 'AnotherApp';      ZipUrl = 'https://<account>.blob.core.windows.net/deployapps/Another.zip?<SAS>' }
)

foreach ($app in $Apps) {
  Invoke-AppInstallFromSas -Name $app.Name -ZipUrl $app.ZipUrl
}
