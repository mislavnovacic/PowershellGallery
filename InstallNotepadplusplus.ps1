<#
.SYNOPSIS
  Installs Notepad++ silently on a local or remote Windows machine. Suitable for image build customization (AVD multi-session, AIB, MDT, etc.).

.DESCRIPTION
  - Installs a specific Notepad++ version via direct download from GitHub releases OR via winget.
  - Works locally (default) or over PowerShell Remoting (WinRM) to a target computer.
  - Idempotent: skips if the requested version is already installed (unless -Force).
  - Enterprise-friendly: can disable the built-in updater.

.PARAMETER Version
  Optional. Example: 8.7.6. If omitted and -UseWinget is provided, the latest available via winget is installed.
  If omitted and -UseWinget is NOT provided, the script will still try winget as a fallback.

.PARAMETER UseWinget
  Prefer winget for installation. Falls back to direct download if winget is unavailable.

.PARAMETER ComputerName
  Target computer. Default: localhost. For remote installs, PowerShell Remoting must be enabled on the target.

.PARAMETER Credential
  PSCredential for remote session. Not required for localhost. For remote, provide an account that is local admin.

.PARAMETER InstallDir
  Optional install directory. Default: C:\Program Files\Notepad++ (x64) or C:\Program Files (x86)\Notepad++ (x86).

.PARAMETER DisableAutoUpdate
  Disables Notepad++ auto-update (removes/renames updater components). Default: On.

.PARAMETER Checksum
  Optional SHA256 checksum for the installer. If provided, the script validates the hash.

.PARAMETER Force
  Reinstall even if the same version is already present.

.EXAMPLE
  .\Install-NotepadPP.ps1 -UseWinget -Verbose

.EXAMPLE
  .\Install-NotepadPP.ps1 -Version 8.7.6 -DisableAutoUpdate -Verbose

.EXAMPLE
  $cred = Get-Credential
  .\Install-NotepadPP.ps1 -ComputerName AVDHOST-01 -Credential $cred -Version 8.7.6 -Verbose

.NOTES
  Run elevated. For Azure Image Builder, invoke with: powershell.exe -ExecutionPolicy Bypass -File Install-NotepadPP.ps1 -UseWinget
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
param(
    [Parameter()][string]$Version,
    [Parameter()][switch]$UseWinget,
    [Parameter()][string]$ComputerName = 'localhost',
    [Parameter()][System.Management.Automation.PSCredential]$Credential,
    [Parameter()][string]$InstallDir,
    [Parameter()][switch]$DisableAutoUpdate = $true,
    [Parameter()][string]$Checksum,
    [Parameter()][switch]$Force
)

#region Helpers
function Test-IsAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

function Get-OsArch {
    (Get-CimInstance Win32_OperatingSystem).OSArchitecture -match '64' | Out-Null
    if ($?) { return 'x64' } else { return 'x86' }
}

function Test-WingetAvailable {
    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    return (Get-Command winget.exe -ErrorAction SilentlyContinue) -ne $null
}

function Get-InstalledNotepadPPVersion {
    $candidates = @(
        "$Env:ProgramFiles\Notepad++\notepad++.exe",
        "$Env:ProgramFiles(x86)\Notepad++\notepad++.exe"
    ) | Where-Object { Test-Path $_ }
    foreach ($exe in $candidates) {
        try {
            return (Get-Item $exe).VersionInfo.ProductVersion
        } catch {}
    }
    return $null
}

function Install-NotepadPP-Direct {
    param(
        [Parameter(Mandatory)] [string] $Version,
        [string] $InstallDir,
        [switch] $DisableAutoUpdate,
        [string] $Checksum
    )

    $arch = Get-OsArch
    if (-not $InstallDir) {
        $InstallDir = if ($arch -eq 'x64') { "$Env:ProgramFiles\Notepad++" } else { "$Env:ProgramFiles(x86)\Notepad++" }
    }

    $base = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v$Version"
    $file = if ($arch -eq 'x64') { "npp.$Version.Installer.x64.exe" } else { "npp.$Version.Installer.exe" }
    $uri  = "$base/$file"

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("npp_installer_" + [IO.Path]::GetRandomFileName() + ".exe")
    Write-Verbose "Downloading Notepad++ $Version ($arch) from $uri ..."

    try {
        # Ensure TLS 1.2+
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {}

    Invoke-WebRequest -Uri $uri -OutFile $temp -UseBasicParsing -ErrorAction Stop

    if ($Checksum) {
        Write-Verbose "Validating SHA256 checksum ..."
        $actual = (Get-FileHash -Algorithm SHA256 -Path $temp).Hash.ToLower()
        if ($actual -ne $Checksum.ToLower()) {
            throw "Checksum mismatch. Expected $Checksum, got $actual"
        }
    }

    $sig = Get-AuthenticodeSignature -FilePath $temp
    if ($sig.Status -ne 'Valid') {
        Write-Warning "Installer signature status: $($sig.Status) ($($sig.StatusMessage)). Proceeding anyway."
    }

    $args = @('/S')
    if ($InstallDir) { $args += @("/D=$InstallDir") } # NSIS: /D must be last argument, unquoted

    Write-Verbose "Installing to '$InstallDir' ..."
    $p = Start-Process -FilePath $temp -ArgumentList ($args -join ' ') -PassThru -Wait
    if ($p.ExitCode -ne 0) {
        throw "Installer exited with code $($p.ExitCode)"
    }

    if ($DisableAutoUpdate) {
        try {
            $upd = Join-Path $InstallDir 'updater'
            if (Test-Path $upd) {
                Rename-Item -Path $upd -NewName ('updater.disabled_' + (Get-Date -Format yyyyMMddHHmmss)) -ErrorAction Stop
                Write-Verbose "Disabled updater by renaming '$upd'."
            }
        } catch { Write-Warning $_ }
    }

    Remove-Item $temp -Force -ErrorAction SilentlyContinue
}

function Install-NotepadPP-Winget {
    param(
        [string] $Version,
        [switch] $DisableAutoUpdate
    )
    $wingetArgs = @('install','--id','Notepad++.Notepad++','-e','--silent','--accept-package-agreements','--accept-source-agreements')
    if ($Version) { $wingetArgs += @('--version', $Version) }

    Write-Verbose ("winget " + ($wingetArgs -join ' '))
    $p = Start-Process -FilePath 'winget.exe' -ArgumentList $wingetArgs -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "winget exited with code $($p.ExitCode)" }

    if ($DisableAutoUpdate) {
        $exe = "$Env:ProgramFiles\Notepad++\notepad++.exe"
        $dir = Split-Path -Parent $exe
        $upd = Join-Path $dir 'updater'
        if (Test-Path $upd) { Rename-Item $upd -NewName ('updater.disabled_' + (Get-Date -Format yyyyMMddHHmmss)) -ErrorAction SilentlyContinue }
    }
}

function Invoke-Locally {
    param(
        [string] $Version,
        [switch] $UseWinget,
        [string] $InstallDir,
        [switch] $DisableAutoUpdate,
        [string] $Checksum,
        [switch] $Force
    )

    if (-not (Test-IsAdmin)) { throw 'Please run this script elevated (as Administrator).'}

    $current = Get-InstalledNotepadPPVersion
    if ($current -and $Version -and -not $Force) {
        if ($current -eq $Version) {
            Write-Verbose "Notepad++ $current already installed. Skipping (use -Force to reinstall)."
            return
        }
    }

    $didWinget = $false
    if ($UseWinget -or -not $Version) {
        if (Test-WingetAvailable) {
            try {
                Install-NotepadPP-Winget -Version $Version -DisableAutoUpdate:$DisableAutoUpdate
                $didWinget = $true
            } catch {
                Write-Warning "winget install failed: $_"
            }
        } else {
            Write-Verbose "winget not available; falling back to direct download."
        }
    }

    if (-not $didWinget) {
        if (-not $Version) { throw 'Version is required when winget is unavailable. Provide -Version (e.g., 8.7.6) or enable -UseWinget.' }
        Install-NotepadPP-Direct -Version $Version -InstallDir $InstallDir -DisableAutoUpdate:$DisableAutoUpdate -Checksum $Checksum
    }

    $installed = Get-InstalledNotepadPPVersion
    if (-not $installed) { throw 'Notepad++ installation did not complete as expected.' }
    Write-Host "Notepad++ installed. Version: $installed" -ForegroundColor Green
}

function Invoke-Remote {
    param(
        [string] $ComputerName,
        [System.Management.Automation.PSCredential] $Credential,
        [string] $Version,
        [switch] $UseWinget,
        [string] $InstallDir,
        [switch] $DisableAutoUpdate,
        [string] $Checksum,
        [switch] $Force
    )

    $sessParams = @{ ComputerName = $ComputerName }
    if ($Credential) { $sessParams.Credential = $Credential }
    $s = New-PSSession @sessParams
    try {
        $script = {
            param($Version,$UseWinget,$InstallDir,$DisableAutoUpdate,$Checksum,$Force)
            & $using:PSCommandPath -Version $Version -UseWinget:$UseWinget -InstallDir $InstallDir -DisableAutoUpdate:$DisableAutoUpdate -Checksum $Checksum -Force:$Force -ComputerName 'localhost'
        }
        Invoke-Command -Session $s -ScriptBlock $script -ArgumentList $Version,$UseWinget,$InstallDir,$DisableAutoUpdate,$Checksum,$Force
    } finally { if ($s) { Remove-PSSession $s } }
}
#endregion

# Start transcript for logging (ignored if cannot write)
try {
    $logPath = Join-Path $env:TEMP ("Install-NotepadPP_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")
    Start-Transcript -Path $logPath -ErrorAction SilentlyContinue | Out-Null
} catch {}

try {
    if ($ComputerName -eq 'localhost' -or $ComputerName -eq $env:COMPUTERNAME) {
        Invoke-Locally -Version $Version -UseWinget:$UseWinget -InstallDir $InstallDir -DisableAutoUpdate:$DisableAutoUpdate -Checksum $Checksum -Force:$Force
    } else {
        Invoke-Remote -ComputerName $ComputerName -Credential $Credential -Version $Version -UseWinget:$UseWinget -InstallDir $InstallDir -DisableAutoUpdate:$DisableAutoUpdate -Checksum $Checksum -Force:$Force
    }
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
