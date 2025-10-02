# File: scripts/Install-PackagesFromBlobs-Baked.ps1
<#
.SYNOPSIS
  Download, extract, and install packaged apps (PSAppDeployToolkit) from Azure Blob SAS URLs.
.DESCRIPTION
  Uses baked-in defaults so you can run with no arguments; you can still override.
  Replace the placeholder URLs below with your real SAS URLs.
.EXAMPLE
  # Run with baked defaults (after replacing placeholders):
  .\Install-PackagesFromBlobs-Baked.ps1
.EXAMPLE
  # Override on the fly:
  .\Install-PackagesFromBlobs-Baked.ps1 -SasUrls @(
    "https://<acct>.blob.core.windows.net/<container>/Notepadplusplus.zip?<SAS>",
    "https://<acct>.blob.core.windows.net/<container>/7zip.zip?<SAS>"
  )
#>

[CmdletBinding()]
param(
  # >>> Replace these two placeholders once and forget:
  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string[]]$SasUrls = @(
    "https://avdmgmdeployapps.blob.core.windows.net/deployapps/Notepadplusplus.zip?sp=r&st=2025-10-02T20:02:14Z&se=2030-10-03T04:17:14Z&spr=https&sv=2024-11-04&sr=b&sig=m3PYnVS0HBuv2mpZDbF6rstThvxPtPG3wL4ietP2zJI%3D",
    "https://avdmgmdeployapps.blob.core.windows.net/deployapps/Treesizepro_5.4.2.zip?sp=r&st=2025-10-02T20:02:43Z&se=2030-10-03T04:17:43Z&spr=https&sv=2024-11-04&sr=b&sig=MgdFa7b1MfH3ZMrmSTWw7Idmbj8YQ0xfCII84SXkzqI%3D"
    "https://avdmgmdeployapps.blob.core.windows.net/deployapps/7Zip.zip?sp=r&st=2025-10-02T20:04:16Z&se=2030-10-03T04:19:16Z&spr=https&sv=2024-11-04&sr=b&sig=4scUq5nzoLfXsdzQvG%2F9kRE%2Fvwf%2Fi7GJLLAE0Y5kKGU%3D"
  ),

  [Parameter(Mandatory = $false)]
  [string]$TempRoot = 'C:\temp'
)

$ErrorActionPreference = 'Stop'

# Admin required (why: installers write to Program Files/registry)
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { throw "Run this script in an elevated PowerShell session." }

# TLS 1.2 (why: Azure endpoints)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Ensure temp root
if (-not (Test-Path -LiteralPath $TempRoot)) { New-Item -ItemType Directory -Path $TempRoot | Out-Null }

# Start transcript (why: audit trail)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath   = Join-Path $TempRoot "install-$timestamp.log"
$transcriptStarted = $false
try {
  try { Start-Transcript -Path $logPath -Force -ErrorAction Stop | Out-Null; $transcriptStarted = $true } catch { Write-Warning "Transcript not started: $($_.Exception.Message)" }

  function Expand-Zip {
    [CmdletBinding()]
    param(
      [Parameter(Mandatory = $true)][string]$ZipPath,
      [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Get-Command -Name Expand-Archive -ErrorAction SilentlyContinue) {
      Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
    } else {
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
      [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
    }
  }

  function Get-FilenameFromUrl {
    param([Parameter(Mandatory = $true)][string]$Url)
    $noQuery = $Url.Split('?')[0]
    $name = [IO.Path]::GetFileName($noQuery)
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "package_$([guid]::NewGuid().ToString('N')).zip" }
    if (-not $name.ToLower().EndsWith('.zip')) { $name = "$name.zip" }
    return $name
  }

  function Invoke-Download {
    param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$OutFile)
    $invokeParams = @{ Uri = $Uri; OutFile = $OutFile }
    if ($PSVersionTable.PSVersion.Major -lt 6) { $invokeParams.UseBasicParsing = $true } # why: legacy IE dependency
    Invoke-WebRequest @invokeParams
  }

  function Install-FromZipFolder {
    param([Parameter(Mandatory = $true)][string]$FolderPath)
    $exe = Get-ChildItem -Path $FolderPath -Filter 'Deploy-Application.exe' -Recurse -File | Select-Object -First 1
    if (-not $exe) { throw "Deploy-Application.exe not found under $FolderPath" }
    $args = @('-DeploymentType','Install','-DeployMode','Silent')
    $proc = Start-Process -FilePath $exe.FullName -ArgumentList $args -WorkingDirectory $exe.DirectoryName -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -ne 0) { throw "Installer exited with code $($proc.ExitCode) for $($exe.FullName)" }
  }

  if (-not $SasUrls -or $SasUrls.Count -eq 0) { throw "No SAS URLs provided. Update defaults in the param block or pass -SasUrls @('...','...')." }

  $allSucceeded = $true

  foreach ($sas in $SasUrls) {
    Write-Host "Processing: $sas"
    $zipName   = Get-FilenameFromUrl -Url $sas
    $zipPath   = Join-Path $TempRoot $zipName
    $extractTo = Join-Path $TempRoot ([IO.Path]::GetFileNameWithoutExtension($zipName))

    if (Test-Path -LiteralPath $zipPath)   { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $extractTo) { Remove-Item -LiteralPath $extractTo -Recurse -Force }

    Write-Host "Downloading to $zipPath ..."
    Invoke-Download -Uri $sas -OutFile $zipPath

    Write-Host "Extracting to $extractTo ..."
    Expand-Zip -ZipPath $zipPath -Destination $extractTo

    Write-Host "Installing from $extractTo ..."
    Install-FromZipFolder -FolderPath $extractTo

    Write-Host "Completed: $zipName"
  }

} catch {
  Write-Error $_
  $allSucceeded = $false
} finally {
  if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch { Write-Warning "Stop-Transcript failed: $($_.Exception.Message)" } }

  if ($allSucceeded) {
    Write-Host "All packages installed successfully. Cleaning up $TempRoot ..."
    try { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction Stop } catch { Write-Warning "Cleanup failed: $($_.Exception.Message). Remove $TempRoot manually." }
  } else {
    Write-Warning "One or more installs failed. Log: $logPath"
    Write-Warning "Keeping $TempRoot for troubleshooting."
  }
}
