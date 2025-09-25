<#
.SYNOPSIS
  Disables the MediaPlayback optional feature on Windows 10/11.

.DESCRIPTION
  - Checks if MediaPlayback is enabled.
  - Disables it if present.
  - Supports -WhatIf for safety.

.EXAMPLE
  .\Disable-MediaPlayback.ps1
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param()

$featureName = "MediaPlayback"

Write-Host "Checking feature: $featureName..." -ForegroundColor Cyan

try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
} catch {
    Write-Error "Feature '$featureName' not found on this system."
    exit 1
}

if ($feature.State -eq "Enabled") {
    if ($PSCmdlet.ShouldProcess($featureName, "Disable")) {
        Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -ErrorAction Stop
        Write-Host "Feature '$featureName' has been disabled." -ForegroundColor Green
    }
} else {
    Write-Host "Feature '$featureName' is already $($feature.State)." -ForegroundColor Yellow
}