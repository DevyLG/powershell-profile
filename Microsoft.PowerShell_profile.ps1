### DevyLG's Custom PowerShell Profile
### Cleaned & Optimized

$repo_root = "https://raw.githubusercontent.com/DevyLG"

# Helper function for cross-edition compatibility
function Get-ProfileDir {
    if ($PROFILE) {
        return Split-Path -Parent $PROFILE
    }
    $myDocs = [Environment]::GetFolderPath("MyDocuments")
    if ($PSVersionTable.PSEdition -eq "Core") {
        return Join-Path -Path $myDocs -ChildPath "PowerShell"
    } else {
        return Join-Path -Path $myDocs -ChildPath "WindowsPowerShell"
    }
}

$profileDir = Get-ProfileDir
$timeFilePath = Join-Path -Path $profileDir -ChildPath "LastExecutionTime.txt"

# Admin Check & Telemetry Opt-out
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [System.EnvironmentVariableTarget]::Machine)
}

# Import Modules and External Profiles
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
}
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if ($env:ChocolateyInstall -and (Test-Path $ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

# Check for Profile Updates
function Update-Profile {
    $tempFile = Join-Path -Path $env:TEMP -ChildPath "Microsoft.PowerShell_profile.ps1"
    try {
        # The ?t=$(Get-Random) tricks GitHub into bypassing its 5-minute cache
        $url = "$repo_root/powershell-profile/main/Microsoft.PowerShell_profile.ps1?t=$(Get-Random)"
        $oldhash = Get-FileHash $PROFILE
        Invoke-RestMethod -Uri $url -OutFile $tempFile
        $newhash = Get-FileHash $tempFile
        
        if ($newhash.Hash -ne $oldhash.Hash) {
            Copy-Item -Path $tempFile -Destination $PROFILE -Force
            Write-Host "Profile has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        } else {
            Write-Host "Profile is up to date." -ForegroundColor Green
        }
        # Update last execution time and clear alert
        Set-Content -Path $timeFilePath -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force
        Remove-Item (Join-Path -Path $env:TEMP -ChildPath "profile_update_available.txt") -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Error "Unable to check for updates: $_"
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

# Asynchronous Daily Update Checker (Non-blocking)
function Start-BackgroundUpdateCheck {
    if ([Console]::IsOutputRedirected) { return }
    
    $alertFile = Join-Path -Path $env:TEMP -ChildPath "profile_update_available.txt"
    if (Test-Path $alertFile) {
        Write-Host "$($PSStyle.Foreground.Cyan)💡 A new profile update is available on GitHub. Run $($PSStyle.Foreground.Yellow)'Update-Profile'$($PSStyle.Foreground.Cyan) to apply.$($PSStyle.Reset)"
    }
    
    $lastCheck = if (Test-Path $timeFilePath) { (Get-Item $timeFilePath).LastWriteTime } else { [DateTime]::MinValue }
    if ((Get-Date) - $lastCheck -gt (New-TimeSpan -Days 1)) {
        Set-Content -Path $timeFilePath -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force
        
        $jobScript = {
            param($urlRoot, $profilePath, $alertPath)
            try {
                $checkUrl = "$urlRoot/powershell-profile/main/Microsoft.PowerShell_profile.ps1?t=$(Get-Random)"
                $remoteRaw = (Invoke-RestMethod -Uri $checkUrl -TimeoutSec 4)
                if ($remoteRaw) {
                    $remoteBytes = [System.Text.Encoding]::UTF8.GetBytes($remoteRaw)
                    $remoteHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($remoteBytes)).Replace("-", "")
                    $localHash = (Get-FileHash -Path $profilePath -Algorithm SHA256).Hash
                    if ($remoteHash -ne $localHash) {
                        Set-Content -Path $alertPath -Value "update" -Force
                    }
                }
            } catch {}
        }
        
        if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            Start-ThreadJob -ScriptBlock $jobScript -ArgumentList $repo_root, $PROFILE, $alertFile | Out-Null
        }
    }
}
Start-BackgroundUpdateCheck

# Prompt Customization
function prompt {
    if ($isAdmin) { "[" + (Get-Location) + "] # " } else { "[" + (Get-Location) + "] $ " }
}
$adminSuffix = if ($isAdmin) { " [ADMIN]" } else { "" }
$Host.UI.RawUI.WindowTitle = "PowerShell {0}$adminSuffix" -f $PSVersionTable.PSVersion.ToString()

# Utility Functions
function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

# Editor Configuration
$EDITOR = if (Test-CommandExists nvim) { 'nvim' }
elseif (Test-CommandExists pvim) { 'pvim' }
elseif (Test-CommandExists vim) { 'vim' }
elseif (Test-CommandExists vi) { 'vi' }
elseif (Test-CommandExists code) { 'code' }
elseif (Test-CommandExists codium) { 'codium' }
elseif (Test-CommandExists notepad++) { 'notepad++' }
elseif (Test-CommandExists sublime_text) { 'sublime_text' }
else { 'notepad' }
Set-Alias -Name vim -Value $EDITOR

# Quick Access to Editing the Profile
function Edit-Profile { & $EDITOR $PROFILE }
Set-Alias -Name ep -Value Edit-Profile

function Invoke-Profile {
    if ($PSVersionTable.PSEdition -eq "Desktop") {
        Write-Host "Note: Some Oh My Posh/PSReadLine errors are expected in PowerShell 5. The profile still works fine." -ForegroundColor Yellow
    }
    & $PROFILE
}

function touch($file) {
    if (Test-Path $file) {
        (Get-Item $file).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $file -Force | Out-Null
    }
}

function ff {
    param([Parameter(Mandatory=$true, Position=0)][string]$name)
    Get-ChildItem -Recurse -Filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output $_.FullName
    }
}

# Network Utilities
function pubip { (Invoke-WebRequest http://ifconfig.me/ip).Content }
function flushdns { Clear-DnsClientCache; Write-Host "DNS has been flushed" }

# Open WinUtil
function winutil { Invoke-Expression (Invoke-RestMethod https://christitus.com/win) }
function winutildev { Invoke-Expression (Invoke-RestMethod https://christitus.com/windev) }

# System Utilities
function admin {
    $cwd = (Get-Location).ProviderPath
    $currentShell = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }

    if (Get-Command wt -ErrorAction SilentlyContinue) {
        if ($args.Count -gt 0) {
            $argList = $args -join ' '
            Start-Process wt -Verb runAs -ArgumentList @('-d', $cwd, $currentShell, '-NoExit', '-Command', $argList)
        } else {
            Start-Process wt -Verb runAs -ArgumentList @('-d', $cwd, $currentShell, '-NoExit')
        }
    } else {
        # Fallback for systems without Windows Terminal
        if ($args.Count -gt 0) {
            $argList = @('-NoExit', '-Command', ($args -join ' '))
            Start-Process $currentShell -WorkingDirectory $cwd -Verb runAs -ArgumentList $argList
        } else {
            Start-Process $currentShell -WorkingDirectory $cwd -Verb runAs -ArgumentList '-NoExit'
        }
    }
}
Set-Alias -Name su -Value admin

function uptime {
    try {
        if ($PSVersionTable.PSEdition -eq "Core") {
            $bootTime = Get-Uptime -Since
        } else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($os -and $os.LastBootUpTime) {
                $bootTime = $os.LastBootUpTime
            } else {
                $lastBoot = (Get-WmiObject win32_operatingsystem).LastBootUpTime
                $bootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($lastBoot)
            }
        }

        $formattedBootTime = $bootTime.ToString("dddd, MMMM dd, yyyy HH:mm:ss")
        Write-Host "System started on: $formattedBootTime" -ForegroundColor DarkGray

        $uptime = (Get-Date) - $bootTime
        Write-Host ("Uptime: {0} days, {1} hours, {2} minutes, {3} seconds" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor Blue
    } catch {
        Write-Error "An error occurred while retrieving system uptime: $_"
    }
}

function unzip {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$file,
        [Parameter(Position=1)]
        [string]$destination = $pwd
    )
    if (-not (Test-Path $file)) {
        Write-Error "Archive file '$file' not found."
        return
    }
    $fullFile = (Resolve-Path -Path $file).Path
    Write-Host "Extracting $file to $destination..." -ForegroundColor Cyan
    Expand-Archive -Path $fullFile -DestinationPath $destination -Force
}

function grep($regex, $dir) {
    if ( $dir ) { Get-ChildItem $dir | select-string $regex; return }
    $input | select-string $regex
}

function df { get-volume }
function sed($file, $find, $replace) { (Get-Content $file).replace("$find", $replace) | Set-Content $file }
function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }
function export {
    param([string]$name, [string]$value)
    if ($name -match '^([^=]+)=(.*)$') {
        $name = $matches[1]
        $value = $matches[2]
    }
    Set-Item -Force -Path "env:$name" -Value $value
}
function pkill($name) { Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force }
function pgrep($name) { Get-Process $name }
function head { param($Path, $n = 10) Get-Content $Path -Head $n }
function tail { param($Path, $n = 10, [switch]$f = $false) Get-Content $Path -Tail $n -Wait:$f }
function nf { param($name) New-Item -ItemType "file" -Path . -Name $name }
function mkcd { param($dir) mkdir $dir -Force; Set-Location $dir }

function trash($path) {
    if (-not (Test-Path -Path $path)) {
        Write-Host "Error: Item '$path' does not exist." -ForegroundColor Red
        return
    }
    $fullPath = (Resolve-Path -Path $path).Path
    $item = Get-Item $fullPath
    if ($item.PSIsContainer) { $parentPath = $item.Parent.FullName } else { $parentPath = $item.DirectoryName }
    $shell = New-Object -ComObject 'Shell.Application'
    $folder = $shell.NameSpace($parentPath)
    if ($folder) {
        $shellItem = $folder.ParseName($item.Name)
        if ($shellItem) {
            $shellItem.InvokeVerb('delete')
            Write-Host "Item '$fullPath' has been moved to the Recycle Bin." -ForegroundColor Green
            return
        }
    }
    Write-Warning "Could not move '$fullPath' to Recycle Bin."
}

### Custom Shortcuts & Workflows ###

# CubeCoders AMP Instant Manager
function amp { & ampinstmgr.exe @args }


# Navigation
function docs {
    $docsPath = if ([Environment]::GetFolderPath("MyDocuments")) { [Environment]::GetFolderPath("MyDocuments") } else { "$HOME\Documents" }
    Set-Location -Path $docsPath
}

function dtop {
    $dtopPath = if ([Environment]::GetFolderPath("Desktop")) { [Environment]::GetFolderPath("Desktop") } else { "$HOME\Desktop" }
    Set-Location -Path $dtopPath
}

function gitstuff { 
    $desktopPath = if ([Environment]::GetFolderPath("Desktop")) { [Environment]::GetFolderPath("Desktop") } else { "$HOME\Desktop" }
    $gitPath = Join-Path -Path $desktopPath -ChildPath "GitStuff"
    if (Test-Path $gitPath) { Set-Location -Path $gitPath } else { Set-Location -Path $desktopPath }
}

function ampdir {
    if (Test-Path "E:\AMPDatabase\Instances") {
        Set-Location -Path "E:\AMPDatabase\Instances"
    } else {
        Write-Warning "Directory 'E:\AMPDatabase\Instances' not found."
    }
}

# Explorer opener (macOS/Linux style 'open .')
function open {
    param([string]$path = ".")
    Invoke-Item $path
}
Set-Alias -Name o -Value open

# Python Virtual Environments
function mkvenv { 
    Write-Host "Creating virtual environment..." -ForegroundColor Cyan
    python -m venv .venv
    if (Test-Path ".\.venv\Scripts\Activate.ps1") {
        . .\.venv\Scripts\Activate.ps1
    }
}

function venv { 
    if (Test-Path ".\.venv\Scripts\Activate.ps1") {
        . .\.venv\Scripts\Activate.ps1
    } elseif (Test-Path ".\venv\Scripts\Activate.ps1") {
        . .\venv\Scripts\Activate.ps1
    } else {
        Write-Host "❌ No virtual environment found in this folder (.venv or venv). Run 'mkvenv' first to create one." -ForegroundColor Red
    }
}

function pyclean {
    Write-Host "Scanning for Python cache files..." -ForegroundColor DarkGray
    $items = Get-ChildItem -Recurse -Include __pycache__,*.pyc,*.pyo -ErrorAction SilentlyContinue
    if ($items) {
        $count = $items.Count
        $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "🧹 Cleaned $count Python cache items." -ForegroundColor Green
    } else {
        Write-Host "✨ Already clean (no pycache found)." -ForegroundColor DarkGray
    }
}

function mkproj {
    param(
        [Parameter(Mandatory=$true, HelpMessage="Please provide a name for your project")]
        [string]$projectName
    )
    
    Write-Host "🚀 Initializing new Python project: $projectName..." -ForegroundColor Cyan
    
    # Create and enter the directory
    New-Item -ItemType Directory -Name $projectName -Force | Out-Null
    Set-Location $projectName
    
    # Create the virtual environment
    Write-Host "Building .venv..." -ForegroundColor DarkGray
    python -m venv .venv
    
    # Create a standard boilerplate main.py file
    Write-Host "Generating main.py..." -ForegroundColor DarkGray
    $template = @"
def main():
    print("Hello from $projectName!")

if __name__ == '__main__':
    main()
"@
    $template | Out-File -FilePath "main.py" -Encoding UTF8
    
    # Activate the environment in the current terminal
    if (Test-Path ".\.venv\Scripts\Activate.ps1") {
        . .\.venv\Scripts\Activate.ps1
    }
    
    # Open the folder in VS Code (or your default editor)
    Write-Host "Done! Opening editor." -ForegroundColor Green
    if (Get-Command "code" -ErrorAction SilentlyContinue) {
        code .
    } elseif ($EDITOR -eq "notepad") {
        notepad main.py
    } else {
        & $EDITOR .
    }
}


# Port Hog Finder & Terminator
function whoson {
    param(
        [Parameter(Mandatory=$true, HelpMessage="Enter the port number to check")]
        [int]$port
    )
    
    Write-Host "Scanning for processes on port $port..." -ForegroundColor Cyan
    
    # Check both TCP and UDP connections
    $tcp = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    $udp = Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue
    $connections = @($tcp; $udp) | Where-Object { $null -ne $_ }
    
    if ($connections.Count -eq 0) {
        Write-Host "No active processes found holding port $port." -ForegroundColor Green
        return
    }
    
    # Deduplicate processes in case of multiple bindings (IPv4/IPv6)
    $uniquePids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($procId in $uniquePids) {
        $process = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $processName = if ($process) { $process.ProcessName } else { "System/RequiresAdmin" }
        
        Write-Host "PID: " -NoNewline
        Write-Host "$($procId.ToString().PadRight(6))" -ForegroundColor Yellow -NoNewline
        Write-Host " | Process: " -NoNewline
        Write-Host "$processName" -ForegroundColor Green
    }
}

function killport {
    param(
        [Parameter(Mandatory=$true, HelpMessage="Enter the port number to kill")]
        [int]$port
    )
    $tcp = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    $udp = Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue
    $connections = @($tcp; $udp) | Where-Object { $null -ne $_ }
    
    if ($connections.Count -eq 0) {
        Write-Host "No active processes found holding port $port." -ForegroundColor Yellow
        return
    }
    
    $uniquePids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($procId in $uniquePids) {
        $process = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $processName = if ($process) { $process.ProcessName } else { "PID $procId" }
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Write-Host "🛑 Terminated $processName (PID: $procId) on port $port." -ForegroundColor Red
    }
}


# Simplified Process Management
function k9 { 
    param([Parameter(Mandatory=$true, Position=0)][string]$name)
    Stop-Process -Name $name -Force -ErrorAction SilentlyContinue 
}

# Enhanced Listing
function la { Get-ChildItem | Format-Table -AutoSize }
function ll { Get-ChildItem -Force | Format-Table -AutoSize }

# Git Shortcuts
function gs { git status }
function ga { git add . }
function gc {
    $msg = $args -join ' '
    if ([string]::IsNullOrWhiteSpace($msg)) {
        Write-Error "Commit message cannot be empty."
        return
    }
    git commit -m $msg
}
function gp { git push }
function gpush { git push }
function gpull { git pull }
function g { __zoxide_z github }
function gcl { git clone @args }
function gcom {
    $msg = $args -join ' '
    if ([string]::IsNullOrWhiteSpace($msg)) {
        Write-Error "Commit message cannot be empty."
        return
    }
    git add .
    git commit -m $msg
}
function lazyg {
    $msg = $args -join ' '
    if ([string]::IsNullOrWhiteSpace($msg)) {
        Write-Error "Commit message cannot be empty."
        return
    }
    git add .
    git commit -m $msg
    git push
}
function gd { git diff }
function gds { git diff --staged }
function glog { git log --oneline --graph --decorate -n 15 }
function gundo {
    git reset --soft HEAD~1
    Write-Host "↩️ Last commit undone. Changes kept staged." -ForegroundColor Cyan
}

# Clean Network Snapshot
function netinfo {
    Write-Host "Fetching network information..." -ForegroundColor DarkGray
    
    # Grab Public IP with a quick timeout so it doesn't hang if offline
    try { 
        $publicIp = (Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 3) 
    } catch { 
        $publicIp = "Unavailable" 
    }
    
    # Find the active network adapter that actually has an internet connection
    $activeNet = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
    
    if ($activeNet) {
        $localIp = $activeNet.IPv4Address.IPAddress
        $gateway = $activeNet.IPv4DefaultGateway.NextHop
        $dns = ($activeNet.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ", "
        $adapter = $activeNet.InterfaceAlias
    } else {
        $localIp = "Disconnected"
        $gateway = "Disconnected"
        $dns = "Disconnected"
        $adapter = "None"
    }

    # Print cleanly formatted output
    Write-Host "====================================" -ForegroundColor DarkGray
    Write-Host " Adapter:   " -NoNewline -ForegroundColor Gray; Write-Host $adapter -ForegroundColor White
    Write-Host " Local IP:  " -NoNewline -ForegroundColor Gray; Write-Host $localIp -ForegroundColor Green
    Write-Host " Gateway:   " -NoNewline -ForegroundColor Gray; Write-Host $gateway -ForegroundColor Yellow
    Write-Host " DNS:       " -NoNewline -ForegroundColor Gray; Write-Host $dns -ForegroundColor Cyan
    Write-Host " Public IP: " -NoNewline -ForegroundColor Gray; Write-Host $publicIp -ForegroundColor Magenta
    Write-Host "====================================" -ForegroundColor DarkGray
}

# Tech Bench Diagnostic Grabber
function Get-PCReport {
    Write-Host "Gathering PC diagnostics..." -ForegroundColor Cyan
    
    # Define the desktop path and file name with a timestamp
    $desktopPath = if ([Environment]::GetFolderPath("Desktop")) { [Environment]::GetFolderPath("Desktop") } else { "$HOME\Desktop" }
    $reportPath = Join-Path $desktopPath "PC_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    
    try {
        # Query hardware directly from the system
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $mobo = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        $ram = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        $disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
        $license = Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue
        
        # Calculate Total RAM
        $totalRamGB = 0
        if ($ram) { $totalRamGB = [math]::Round(($ram | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2) }
        
        # Build the text file content
        $report = @()
        $report += "========================================"
        $report += "          PC DIAGNOSTIC REPORT          "
        $report += "========================================"
        $report += "Date Generated: $(Get-Date)"
        $report += "OS Version: $($os.Caption) ($($os.OSArchitecture))"
        
        $oemKey = if (![string]::IsNullOrWhiteSpace($license.OA3xOriginalProductKey)) { $license.OA3xOriginalProductKey } else { "Not found in BIOS/UEFI" }
        $report += "OEM BIOS Key: $oemKey"
        
        $report += "`n[ MOTHERBOARD & CPU ]"
        $report += "Motherboard: $($mobo.Manufacturer) $($mobo.Product)"
        $report += "CPU: $($cpu.Name)"
        $report += "Total RAM: $totalRamGB GB"
        
        $report += "`n[ GRAPHICS ]"
        foreach ($g in $gpu) {
            $report += "GPU: $($g.Name)"
        }
        
        $report += "`n[ STORAGE DRIVES ]"
        foreach ($d in $disks) {
            $sizeGB = [math]::Round($d.Size / 1GB, 2)
            $report += "Drive: $($d.Model) ($sizeGB GB) - Status: $($d.Status)"
        }
        $report += "========================================"
        
        # Save to desktop and open it instantly
        $report | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Host "✅ Diagnostic report saved to Desktop!" -ForegroundColor Green
        
        # Automatically open the text file so you can read it right away
        Invoke-Item $reportPath

    } catch {
        Write-Error "Failed to gather some system information. Ensure you are running this on a compatible Windows machine."
    }
}


# Clipboard
function cpy { 
    if ($input) {
        $input | Out-String | Set-Clipboard
    } else {
        ($args -join ' ') | Set-Clipboard
    }
}
function pst { Get-Clipboard }
function sysinfo { Get-ComputerInfo }

# Environment PATH Viewer
function show-path { $env:PATH -split ';' | Where-Object { $_ } }

# File Hash Verification
function sha256 {
    param([Parameter(Mandatory=$true, Position=0)][string]$path)
    if (-not (Test-Path -Path $path)) {
        Write-Error "File '$path' not found."
        return
    }
    (Get-FileHash -Path $path -Algorithm SHA256).Hash
}

# Live Weather
function weather {
    param([string]$location = "Olathe")
    try {
        $data = (Invoke-RestMethod -Uri "https://wttr.in/${location}?format=3" -TimeoutSec 3).Trim()
        Write-Host $data -ForegroundColor Cyan
    } catch {
        Write-Warning "Unable to retrieve weather for '$location'."
    }
}
Set-Alias -Name wttr -Value weather

# Container & WSL Utilities
function dps {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    } else {
        Write-Error "Docker command not found."
    }
}
function wsl-restart {
    if ($isAdmin) {
        Write-Host "Restarting WSL service (LxssManager)..." -ForegroundColor Cyan
        Restart-Service -Name "LxssManager" -Force
        Write-Host "WSL has been restarted successfully." -ForegroundColor Green
    } else {
        Write-Warning "Restarting WSL requires administrator privileges. Re-run command in an elevated prompt."
    }
}

# PSReadLine Configuration
function Set-PSReadLineOptionsCompat {
    param([hashtable]$Options)
    $SafeOptions = $Options.Clone()
    if ($PSVersionTable.PSEdition -ne "Core" -or [Console]::IsOutputRedirected) {
        $SafeOptions.Remove('PredictionSource')
        $SafeOptions.Remove('PredictionViewStyle')
    }
    try {
        Set-PSReadLineOption @SafeOptions
    } catch {}
}

$PSReadLineOptions = @{
    EditMode = 'Windows'
    HistoryNoDuplicates = $true
    HistorySearchCursorMovesToEnd = $true
    Colors = @{
        Command = '#87CEEB'; Parameter = '#98FB98'; Operator = '#FFB6C1'; Variable = '#DDA0DD'
        String = '#FFDAB9'; Number = '#B0E0E6'; Type = '#F0E68C'; Comment = '#D3D3D3'
        Keyword = '#8367c7'; Error = '#FF6347'
    }
    PredictionSource = 'History'
    PredictionViewStyle = 'ListView'
    BellStyle = 'None'
}
Set-PSReadLineOptionsCompat -Options $PSReadLineOptions

Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
Set-PSReadLineKeyHandler -Chord 'Ctrl+w' -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Chord 'Alt+d' -Function DeleteWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

Set-PSReadLineOption -AddToHistoryHandler {
    param($line)
    $sensitive = @('password', 'secret', 'token', 'apikey', 'connectionstring')
    $hasSensitive = $sensitive | Where-Object { $line -match $_ }
    return ($null -eq $hasSensitive)
}

function Set-PredictionSource {
    if (-not [Console]::IsOutputRedirected -and $PSVersionTable.PSEdition -eq "Core") {
        try {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        } catch {}
    }
    try {
        Set-PSReadLineOption -MaximumHistoryCount 10000
    } catch {}
}
Set-PredictionSource

$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    # Only complete top-level subcommands (first argument after command)
    if ($commandAst.CommandElements.Count -le 2) {
        $customCompletions = @{
            'git' = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout')
            'npm' = @('install', 'start', 'run', 'test', 'build')
            'deno' = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'info', 'doc', 'upgrade')
        }
        $command = $commandAst.CommandElements[0].Value
        if ($customCompletions.ContainsKey($command)) {
            $customCompletions[$command] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}
Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock $scriptblock

$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        dotnet complete --position $cursorPosition $commandAst.ToString() | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock $scriptblock

# Oh My Posh initialization
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $localThemePath = Join-Path (Get-ProfileDir) "cobalt2.omp.json"
    if (-not (Test-Path $localThemePath)) {
        $themeUrl = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/cobalt2.omp.json"
        try {
            Invoke-RestMethod -Uri $themeUrl -OutFile $localThemePath
        } catch {
            Write-Warning "Failed to download theme file. Falling back to remote theme. Error: $_"
        }
    }
    if (Test-Path $localThemePath) {
        oh-my-posh init pwsh --config $localThemePath | Invoke-Expression
    } else {
        oh-my-posh init pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/cobalt2.omp.json | Invoke-Expression
    }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd z powershell | Out-String) })
} else {
    Write-Host "zoxide command not found. Attempting to install via winget..."
    try {
        winget install -e --id ajeetdsouza.zoxide --silent --accept-source-agreements --accept-package-agreements
        Invoke-Expression (& { (zoxide init --cmd z powershell | Out-String) })
    } catch {
        Write-Error "Failed to install zoxide. Error: $_"
    }
}

# Help Function
function Show-Help {
    $helpText = @"
$($PSStyle.Foreground.Cyan)PowerShell Profile Help$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)Edit-Profile$($PSStyle.Reset) - Opens the current user's profile for editing.
$($PSStyle.Foreground.Green)Update-Profile$($PSStyle.Reset) - Pulls the latest config from your GitHub.

$($PSStyle.Foreground.Cyan)Server & Process Management$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)amp$($PSStyle.Reset) <cmd> - Runs AMP Instant Manager (e.g., 'amp status').
$($PSStyle.Foreground.Green)whoson$($PSStyle.Reset) <port> - Finds the exact Process ID and program locking a network port.
$($PSStyle.Foreground.Green)killport$($PSStyle.Reset) <port> - Forcefully terminates the process occupying a specific port.
$($PSStyle.Foreground.Green)k9$($PSStyle.Reset) <name> - Forcefully terminates a process by name.

$($PSStyle.Foreground.Cyan)Python Workflows$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)mkproj$($PSStyle.Reset) <name> - Bootstraps a new Python project, creates .venv, and opens editor.
$($PSStyle.Foreground.Green)mkvenv$($PSStyle.Reset) - Creates a new Python .venv folder and activates it instantly.
$($PSStyle.Foreground.Green)venv$($PSStyle.Reset) - Activates an existing Python .venv in the current directory.
$($PSStyle.Foreground.Green)pyclean$($PSStyle.Reset) - Recursively purges all __pycache__ and .pyc files.

$($PSStyle.Foreground.Cyan)Navigation & File Tools$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)gitstuff$($PSStyle.Reset) - Jumps to your Git repositories folder on Desktop.
$($PSStyle.Foreground.Green)ampdir$($PSStyle.Reset) - Jumps to AMP Instances directory (E:\AMPDatabase\Instances).
$($PSStyle.Foreground.Green)docs$($PSStyle.Reset) - Jumps to Documents.
$($PSStyle.Foreground.Green)dtop$($PSStyle.Reset) - Jumps to Desktop.
$($PSStyle.Foreground.Green)open$($PSStyle.Reset) / $($PSStyle.Foreground.Green)o$($PSStyle.Reset) [path] - Opens current or target folder in Windows File Explorer.
$($PSStyle.Foreground.Green)trash$($PSStyle.Reset) <path> - Safely moves file/folder to the Recycle Bin.
$($PSStyle.Foreground.Green)la$($PSStyle.Reset) / $($PSStyle.Foreground.Green)ll$($PSStyle.Reset) - Enhanced file listings.
$($PSStyle.Foreground.Green)mkcd$($PSStyle.Reset) <dir> - Creates and enters directory.
$($PSStyle.Foreground.Green)nf$($PSStyle.Reset) <name> - Creates a new file.

$($PSStyle.Foreground.Cyan)Git Shortcuts$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)gs$($PSStyle.Reset) - git status
$($PSStyle.Foreground.Green)ga$($PSStyle.Reset) - git add .
$($PSStyle.Foreground.Green)gc$($PSStyle.Reset) <msg> - git commit -m
$($PSStyle.Foreground.Green)gcom$($PSStyle.Reset) <msg> - Adds all changes and commits.
$($PSStyle.Foreground.Green)gp$($PSStyle.Reset) / $($PSStyle.Foreground.Green)gpush$($PSStyle.Reset) - git push
$($PSStyle.Foreground.Green)gpull$($PSStyle.Reset) - git pull
$($PSStyle.Foreground.Green)gd$($PSStyle.Reset) - git diff (current uncommitted changes)
$($PSStyle.Foreground.Green)gds$($PSStyle.Reset) - git diff --staged (staged changes)
$($PSStyle.Foreground.Green)glog$($PSStyle.Reset) - Clean one-line visual git log graph.
$($PSStyle.Foreground.Green)gundo$($PSStyle.Reset) - Undoes last commit, keeping all changes staged.
$($PSStyle.Foreground.Green)lazyg$($PSStyle.Reset) <msg> - Adds, commits, and pushes in one command.
$($PSStyle.Foreground.Green)gcl$($PSStyle.Reset) <repo> - git clone

$($PSStyle.Foreground.Cyan)System & Diagnostic Tools$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)Get-PCReport$($PSStyle.Reset) - Generates a full hardware diagnostic text file on Desktop.
$($PSStyle.Foreground.Green)netinfo$($PSStyle.Reset) - Displays a clean summary of your active network connection.
$($PSStyle.Foreground.Green)weather$($PSStyle.Reset) / $($PSStyle.Foreground.Green)wttr$($PSStyle.Reset) [loc] - Shows quick live weather (defaults to Olathe).
$($PSStyle.Foreground.Green)sha256$($PSStyle.Reset) <file> - Computes SHA-256 hash of a file.
$($PSStyle.Foreground.Green)pubip$($PSStyle.Reset) - Displays public IP address.
$($PSStyle.Foreground.Green)flushdns$($PSStyle.Reset) - Clears DNS cache.
$($PSStyle.Foreground.Green)cpy$($PSStyle.Reset) <text> - Copies text to clipboard (also accepts piped input).
$($PSStyle.Foreground.Green)pst$($PSStyle.Reset) - Retrieves text from clipboard.
$($PSStyle.Foreground.Green)df$($PSStyle.Reset) - Displays disk volume info.
$($PSStyle.Foreground.Green)dps$($PSStyle.Reset) - Displays compact list of running Docker containers.
$($PSStyle.Foreground.Green)uptime$($PSStyle.Reset) - Displays system start time and uptime duration.
$($PSStyle.Foreground.Green)show-path$($PSStyle.Reset) - Displays system PATH line-by-line.
$($PSStyle.Foreground.Green)winutil$($PSStyle.Reset) - Runs CTT WinUtil.
$($PSStyle.Foreground.Green)wsl-restart$($PSStyle.Reset) - Restarts WSL service (requires admin).
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
"@
    Write-Host $helpText
}

$cttCustomPath = Join-Path -Path $profileDir -ChildPath 'CTTcustom.ps1'
if (Test-Path $cttCustomPath) {
    . $cttCustomPath
}

Write-Host "$($PSStyle.Foreground.Yellow)Use 'Show-Help' to display custom commands$($PSStyle.Reset)"