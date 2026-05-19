### DevyLG's Custom PowerShell Profile
### Cleaned & Optimized

$repo_root = "https://raw.githubusercontent.com/DevyLG"
$updateInterval = 7

# Helper function for cross-edition compatibility
function Get-ProfileDir {
    if ($PSVersionTable.PSEdition -eq "Core") {
        return [Environment]::GetFolderPath("MyDocuments") + "\PowerShell"
    } elseif ($PSVersionTable.PSEdition -eq "Desktop") {
        return [Environment]::GetFolderPath("MyDocuments") + "\WindowsPowerShell"
    } else {
        Write-Error "Unsupported PowerShell edition: $($PSVersionTable.PSEdition)"
        return $null
    }
}

$profileDir = Get-ProfileDir
$timeFilePath = "$profileDir\LastExecutionTime.txt"

# Opt-out of telemetry before doing anything, only if PowerShell is run as admin
if ([bool]([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem) {
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [System.EnvironmentVariableTarget]::Machine)
}

# Initial GitHub.com connectivity check
function Test-GitHubConnection {
    if ($PSVersionTable.PSEdition -eq "Core") {
        return Test-Connection github.com -Count 1 -Quiet -TimeoutSeconds 1
    } else {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $result = $ping.Send("github.com", 1000)
        return ($result.Status -eq "Success")
    }
}
$global:canConnectToGitHub = Test-GitHubConnection

# Import Modules and External Profiles
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module -Name Terminal-Icons
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

# Safely read and parse the last execution date
$lastExecRaw = if (Test-Path $timeFilePath) { (Get-Content -Path $timeFilePath -Raw).Trim() } else { $null }
[Nullable[datetime]]$lastExec = $null
if (-not [string]::IsNullOrWhiteSpace($lastExecRaw)) {
    [datetime]$parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($lastExecRaw, 'yyyy-MM-dd', $null, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        $lastExec = $parsed
    }
}

# Check for Profile Updates
function Update-Profile {
    try {
        $url = "$repo_root/powershell-profile/main/Microsoft.PowerShell_profile.ps1"
        $oldhash = Get-FileHash $PROFILE
        Invoke-RestMethod $url -OutFile "$env:temp/Microsoft.PowerShell_profile.ps1"
        $newhash = Get-FileHash "$env:temp/Microsoft.PowerShell_profile.ps1"
        if ($newhash.Hash -ne $oldhash.Hash) {
            Copy-Item -Path "$env:temp/Microsoft.PowerShell_profile.ps1" -Destination $PROFILE -Force
            Write-Host "Profile has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        } else {
            Write-Host "Profile is up to date." -ForegroundColor Green
        }
    } catch {
        Write-Error "Unable to check for updates: $_"
    } finally {
        Remove-Item "$env:temp/Microsoft.PowerShell_profile.ps1" -ErrorAction SilentlyContinue
    }
}

# Run Update Check automatically based on interval
if (-not (Test-Path $timeFilePath) -or $null -eq $lastExec -or ((Get-Date) - $lastExec).TotalDays -gt $updateInterval) {
    Update-Profile
    $currentTime = Get-Date -Format 'yyyy-MM-dd'
    $currentTime | Out-File -FilePath $timeFilePath
}

# Admin Check and Prompt Customization
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
function Edit-Profile { & $EDITOR $PROFILE.CurrentUserAllHosts }
Set-Alias -Name ep -Value Edit-Profile

function Invoke-Profile {
    if ($PSVersionTable.PSEdition -eq "Desktop") {
        Write-Host "Note: Some Oh My Posh/PSReadLine errors are expected in PowerShell 5. The profile still works fine." -ForegroundColor Yellow
    }
    & $PROFILE
}

function touch($file) { "" | Out-File $file -Encoding ASCII }
function ff($name) {
    Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "$($_.FullName)"
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
    if ($args.Count -gt 0) {
        $argList = $args -join ' '
        Start-Process wt -Verb runAs -ArgumentList @('-d', $cwd, 'pwsh.exe', '-NoExit', '-Command', $argList)
    } else {
        Start-Process wt -Verb runAs -ArgumentList @('-d', $cwd, 'pwsh.exe', '-NoExit')
    }
}
Set-Alias -Name su -Value admin

function uptime {
    try {
        $dateFormat = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern
        $timeFormat = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.LongTimePattern

        if ($PSVersionTable.PSVersion.Major -eq 5) {
            $lastBoot = (Get-WmiObject win32_operatingsystem).LastBootUpTime
            $bootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($lastBoot)
            $lastBoot = $bootTime.ToString("$dateFormat $timeFormat")
        } else {
            $lastBoot = (Get-Uptime -Since).ToString("$dateFormat $timeFormat")
            $bootTime = [System.DateTime]::ParseExact($lastBoot, "$dateFormat $timeFormat", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        $formattedBootTime = $bootTime.ToString("dddd, MMMM dd, yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) + " [$lastBoot]"
        Write-Host "System started on: $formattedBootTime" -ForegroundColor DarkGray

        $uptime = (Get-Date) - $bootTime
        Write-Host ("Uptime: {0} days, {1} hours, {2} minutes, {3} seconds" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor Blue
    } catch {
        Write-Error "An error occurred while retrieving system uptime."
    }
}

function unzip ($file) {
    Write-Output("Extracting", $file, "to", $pwd)
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}

function grep($regex, $dir) {
    if ( $dir ) { Get-ChildItem $dir | select-string $regex; return }
    $input | select-string $regex
}

function df { get-volume }
function sed($file, $find, $replace) { (Get-Content $file).replace("$find", $replace) | Set-Content $file }
function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }
function export($name, $value) { set-item -force -path "env:$name" -value $value; }
function pkill($name) { Get-Process $name -ErrorAction SilentlyContinue | Stop-Process }
function pgrep($name) { Get-Process $name }
function head { param($Path, $n = 10) Get-Content $Path -Head $n }
function tail { param($Path, $n = 10, [switch]$f = $false) Get-Content $Path -Tail $n -Wait:$f }
function nf { param($name) New-Item -ItemType "file" -Path . -Name $name }
function mkcd { param($dir) mkdir $dir -Force; Set-Location $dir }

function trash($path) {
    $fullPath = (Resolve-Path -Path $path).Path
    if (Test-Path $fullPath) {
        $item = Get-Item $fullPath
        if ($item.PSIsContainer) { $parentPath = $item.Parent.FullName } else { $parentPath = $item.DirectoryName }
        $shell = New-Object -ComObject 'Shell.Application'
        $shellItem = $shell.NameSpace($parentPath).ParseName($item.Name)
        if ($item) {
            $shellItem.InvokeVerb('delete')
            Write-Host "Item '$fullPath' has been moved to the Recycle Bin."
        }
    } else {
        Write-Host "Error: Item '$fullPath' does not exist."
    }
}

### Custom Shortcuts & Workflows ###

# Navigation
function docs {
    $docsPath = if ([Environment]::GetFolderPath("MyDocuments")) { [Environment]::GetFolderPath("MyDocuments") } else { "$HOME\Documents" }
    Set-Location -Path $docsPath
}

function dtop {
    $dtopPath = if ([Environment]::GetFolderPath("Desktop")) { [Environment]::GetFolderPath("Desktop") } else { "$HOME\Desktop" }
    Set-Location -Path $dtopPath
}
# Python Virtual Environments
function mkvenv { 
    Write-Host "Creating virtual environment..." -ForegroundColor Cyan
    python -m venv venv
    .\.venv\Scripts\Activate.ps1
}

function venv { 
    if (Test-Path ".\venv\Scripts\Activate.ps1") {
        .\.venv\Scripts\Activate.ps1
    } else {
        Write-Host "❌ No virtual environment found in this folder. Run 'mkvenv' first to create one." -ForegroundColor Red
    }
}


# Simplified Process Management
function k9 { Stop-Process -Name $args[0] }

# Enhanced Listing
function la { Get-ChildItem | Format-Table -AutoSize }
function ll { Get-ChildItem -Force | Format-Table -AutoSize }

# Git Shortcuts
function gs { git status }
function ga { git add . }
function gc { param($m) git commit -m "$m" }
function gpush { git push }
function gpull { git pull }
function g { __zoxide_z github }
function gcl { git clone "$args" }
function gcom { git add .; git commit -m "$args" }
function lazyg { git add .; git commit -m "$args"; git push }

# Clipboard
function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }
function sysinfo { Get-ComputerInfo }

# PSReadLine Configuration
function Set-PSReadLineOptionsCompat {
    param([hashtable]$Options)
    if ($PSVersionTable.PSEdition -eq "Core") {
        Set-PSReadLineOption @Options
    } else {
        $SafeOptions = $Options.Clone()
        $SafeOptions.Remove('PredictionSource')
        $SafeOptions.Remove('PredictionViewStyle')
        Set-PSReadLineOption @SafeOptions
    }
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
    if ($PSVersionTable.PSEdition -eq "Core") {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -MaximumHistoryCount 10000
    } else {
        Set-PSReadLineOption -MaximumHistoryCount 10000
    }
}
Set-PredictionSource

$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
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
Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock $scriptblock

$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    dotnet complete --position $cursorPosition $commandAst.ToString() | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock $scriptblock

# Oh My Posh initialization
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

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd z powershell | Out-String) })
} else {
    Write-Host "zoxide command not found. Attempting to install via winget..."
    try {
        winget install -e --id ajeetdsouza.zoxide
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

$($PSStyle.Foreground.Cyan)Python Workflows$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)mkvenv$($PSStyle.Reset) - Creates a new Python venv folder and activates it instantly.
$($PSStyle.Foreground.Green)venv$($PSStyle.Reset) - Activates an existing Python venv in the current directory.

$($PSStyle.Foreground.Cyan)Git Shortcuts$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)g$($PSStyle.Reset) - Changes to the GitHub directory.
$($PSStyle.Foreground.Green)ga$($PSStyle.Reset) - git add .
$($PSStyle.Foreground.Green)gc$($PSStyle.Reset) <msg> - git commit -m
$($PSStyle.Foreground.Green)gcl$($PSStyle.Reset) <repo> - git clone
$($PSStyle.Foreground.Green)gcom$($PSStyle.Reset) <msg> - Adds all changes and commits.
$($PSStyle.Foreground.Green)gp$($PSStyle.Reset) / $($PSStyle.Foreground.Green)gpush$($PSStyle.Reset) - git push
$($PSStyle.Foreground.Green)gpull$($PSStyle.Reset) - git pull
$($PSStyle.Foreground.Green)gs$($PSStyle.Reset) - git status
$($PSStyle.Foreground.Green)lazyg$($PSStyle.Reset) <msg> - Adds, commits, and pushes in one command.

$($PSStyle.Foreground.Cyan)Shortcuts$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)cpy$($PSStyle.Reset) <text> - Copies text to clipboard.
$($PSStyle.Foreground.Green)pst$($PSStyle.Reset) - Retrieves text from clipboard.
$($PSStyle.Foreground.Green)df$($PSStyle.Reset) - Displays volume info.
$($PSStyle.Foreground.Green)docs$($PSStyle.Reset) - Jumps to Documents.
$($PSStyle.Foreground.Green)dtop$($PSStyle.Reset) - Jumps to Desktop.
$($PSStyle.Foreground.Green)ep$($PSStyle.Reset) - Opens profile for editing.
$($PSStyle.Foreground.Green)flushdns$($PSStyle.Reset) - Clears DNS cache.
$($PSStyle.Foreground.Green)pubip$($PSStyle.Reset) - Gets your public IP.
$($PSStyle.Foreground.Green)k9$($PSStyle.Reset) <name> - Kills process by name.
$($PSStyle.Foreground.Green)la$($PSStyle.Reset) / $($PSStyle.Foreground.Green)ll$($PSStyle.Reset) - Enhanced file listing.
$($PSStyle.Foreground.Green)mkcd$($PSStyle.Reset) <dir> - Creates and enters directory.
$($PSStyle.Foreground.Green)nf$($PSStyle.Reset) <name> - Creates a new file.
$($PSStyle.Foreground.Green)trash$($PSStyle.Reset) <path> - Sends file/folder to Recycle Bin.
$($PSStyle.Foreground.Green)uptime$($PSStyle.Reset) - Shows system uptime.
$($PSStyle.Foreground.Green)winutil$($PSStyle.Reset) - Runs CTT WinUtil.
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
"@
    Write-Host $helpText
}

if (Test-Path "$PSScriptRoot\CTTcustom.ps1") {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'CTTcustom.ps1')
}

Write-Host "$($PSStyle.Foreground.Yellow)Use 'Show-Help' to display custom commands$($PSStyle.Reset)"