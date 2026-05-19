#requires -RunAsAdministrator
#requires -Version 7.0

if (-not ($Env:WT_SESSION)) {
    Throw "Windows Terminal (wt) is required."
}

if (Test-Path $Profile) {
    Move-Item -Path $Profile -Destination ($Profile + ".bak") -Force
} else {
    New-Item -Path $Profile -Force | Out-Null
}

# Disable pwsh telemetry
[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT','1','Machine')

# TARGET YOUR REPOSITORY FOR THE PROFILE FILE
Invoke-WebRequest -Uri https://github.com/DevyLG/powershell-profile/raw/main/Microsoft.PowerShell_profile.ps1 -OutFile $Profile
Invoke-WebRequest -Uri https://github.com/JanDeDobbeleer/oh-my-posh/raw/main/themes/cobalt2.omp.json -OutFile (Split-Path $Profile)

Install-Module -Name Terminal-Icons -Force -Repository PSGallery -Scope CurrentUser

# Install dependencies cleanly via winget
winget install JanDeDobbeleer.OhMyPosh ajeetdsouza.zoxide DEVCOM.JetBrainsMonoNerdFont --source winget --silent
Write-Host "Successfully Installed DevyLG's Custom PowerShell Profile." -ForegroundColor Green