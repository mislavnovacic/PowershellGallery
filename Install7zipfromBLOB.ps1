$ErrorActionPreference = 'Stop'
# Enforce TLS 1.2 just in case
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1) Download your PSADT bundle
$ZipUrl  = 'https://avdmgmdeployapps.blob.core.windows.net/deployapps/7Zip_direct.zip?sp=r&st=2025-09-29T08:25:07Z&se=2030-09-29T16:40:07Z&spr=https&sv=2024-11-04&sr=b&sig=PeB1gZ47g2NF%2B7F%2BB9UyCVYA0C%2B%2BW4tUUBNoYOk9d3U%3D'
$Stage   = 'C:\AIB\Stage\7zip'
$ZipPath = Join-Path $Stage '7Zip_PSADT.zip'
New-Item -Path $Stage -ItemType Directory -Force | Out-Null

# Sanity (order-agnostic; don't fail on &sv=...)
if ($ZipUrl -notmatch '(?:\?|&)sr=b(?:&|$)' -or
    $ZipUrl -notmatch '(?:\?|&)sp=r(?:&|$)' -or
    $ZipUrl -notmatch '(?:\?|&)sv=[^&]+')
{
  throw "ZipUrl must be a blob SAS with read permission (sr=b, sp=r) and include sv=."
}

# HEAD first so we fail fast on a bad token
Invoke-WebRequest -Uri $ZipUrl -Method Head -UseBasicParsing | Out-Null

# Download + unzip
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
Expand-Archive -LiteralPath $ZipPath -DestinationPath $Stage -Force

# Find PSADT entry point even if the zip adds a folder
$deploy = Get-ChildItem -Path $Stage -Filter 'Deploy-Application.ps1' -Recurse -File | Select-Object -First 1
if (-not $deploy) { throw "Deploy-Application.ps1 not found under $Stage" }

# Run PSADT and bubble up its exit code
$argList = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File', $deploy.FullName, '-DeploymentType','Install','-DeployMode','NonInteractive')
$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "PSADT failed with exit code $($proc.ExitCode)." }

# Cleanup
Remove-Item $Stage -Recurse -Force
