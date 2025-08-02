# Backup and Reset Configuration Script for Windows 11


# $ProgressPreference = 'SilentlyContinue'

enum Filter {
    Whitelist
    Blacklist
    Regex
}

$BackupItems = @{
    custom  = @{ 
        Name   = "Custom Programs"
        Source = "C:\custom"
        Filter = @{ 
            Type  = [Filter]::Blacklist
            Paths = @() 
        } 
    }
    ShareX  = @{ 
        Name   = "ShareX Settings"
        Source = "C:\Users\$env:USERNAME\Documents\ShareX"
        Filter = @{ 
            Type  = [Filter]::Whitelist
            Paths = @("ApplicationConfig.json", "HotkeysConfig.json") 
        } 
    }
    Portal2 = @{ 
        Name   = "Portal 2 Config + Sar"; 
        Source = "C:\Program Files (x86)\Steam\steamapps\common\Portal 2\portal2"
        Filter = @{ 
            Type  = [Filter]::Whitelist
            Paths = @("cfg", "sar.dll") 
        } 
    }
    CS2     = @{ 
        Name   = "CS:2 Config"
        Source = "C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg"
        Filter = @{ 
            Type  = [Filter]::Whitelist
            Paths = @("usercfg", "ae.cfg", "autoexec.cfg", "ez.cfg") 
        } 
    }
    OBS     = @{ 
        Name   = "OBS Studio Settings"
        Source = "$env:APPDATA\obs-studio"
        Filter = @{ 
            Type  = [Filter]::Whitelist
            Paths = @("basic", "global.ini", "service.json", "plugin_config") 
        } 
    }
    WinRar  = @{
        Name   = "Winrar Activation"
        Source = "C:\Program Files\WinRAR"
        Filter = @{ 
            Type  = [Filter]::Whitelist
            Paths = @("rarreg.key") 
        } 
    }
}


$packages = [ordered]@{
    main          = @("Discord.Discord", "RARLab.WinRAR", "ShareX.ShareX", "Brave.Brave", "Valve.Steam", "Bitwarden.Bitwarden", "SublimeHQ.SublimeText.4", "Flow-Launcher.Flow-Launcher", "AutoHotkey.AutoHotkey", "Gyan.FFmpeg")
    code          = @("Microsoft.VisualStudio.2022.Community.Preview", "Git.Git", "ajeetdsouza.zoxide", "Microsoft.VisualStudioCode", "DEVCOM.Lua", "Python.Python.3.13", "yt-dlp.yt-dlp", "Microsoft.PowerShell")
    customization = @("winaero.tweaker", "Vendicated.Vencord", "JanDeDobbeleer.OhMyPosh", "Microsoft.PowerToys", "LianLi.LConnect3", "OpenRGB.OpenRGB")
    streaming     = @("PrivateInternetAccess.PrivateInternetAccess", "Stremio.Stremio")
    recording     = @("OBSProject.OBSStudio", "univrsal.input-overlay")
    faceit        = @("FACEITLTD.FACEITClient", "FACEITLTD.FACEITAC")
}

function Show-YesNoPrompt { 
    param (
        [bool]$Default = $true
    )

    $done = $false
    while (-not $done) {
        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
        switch ($Key) {
            89 { $done = $true; return $true }
            78 { $done = $true; return $false }
            13 { $done = $true; return $Default }
        }
    }
}


function Show-MultiSelectMenu {
    param (
        [Parameter(Mandatory)][string[]]$Items,
        [string]$Prompt = "Select options:",
        [bool]$DefaultSelected = $false
    )

    $Selected = @($DefaultSelected) * $Items.Count
    $CurrentIndex = 0
    $done = $false

    while (-not $done) {
        Clear-Host
        Write-Host "$Prompt" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($CurrentIndex -eq $i) {
                Write-Host "> [$(if ($Selected[$i]) {"X"} else {" "})] $($Items[$i])" -ForegroundColor Yellow
            } else {
                Write-Host "  [$(if ($Selected[$i]) {"X"} else {" "})] $($Items[$i])"
            }
        }

        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
        switch ($Key) {
            27 { $done = $true }
            38 { $CurrentIndex = ($CurrentIndex - 1) % $Items.Count; if ($CurrentIndex -lt 0) { $CurrentIndex = $Items.Count - 1 } }
            40 { $CurrentIndex = ($CurrentIndex + 1) % $Items.Count }
            32 { $Selected[$CurrentIndex] = -not $Selected[$CurrentIndex] }
            13 { $done = $true }
        }
    }

    return $Items | Where-Object { $Selected[$Items.IndexOf($_)] }
}

function Show-SingleSelectMenu {
    param (
        [Parameter(Mandatory)] $Items,
        [string] $Prompt = "Select an option:"
    )

    $CurrentIndex = 0
    $done = $false

    while (-not $done) {
        Clear-Host
        Write-Host "$Prompt" -ForegroundColor Cyan

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $optionNumber = $i + 1
            if ($i -eq $CurrentIndex) {
                Write-Host "> [$optionNumber] $($item)" -ForegroundColor Yellow
            } elseif ($optionNumber -gt 9) {
                Write-Host "  [X] $($item)" -ForegroundColor DarkGray
            } else {
                Write-Host "  [$optionNumber] $($item)"
            }
        }

        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
        if ($Key -ge 49 -and $Key -le 57) {
            $inputIndex = [int]$Key - 49
            if ($inputIndex -lt $Items.Count) {
                $CurrentIndex = $inputIndex
                $done = $true
            }
        }

        switch ($Key) {
            13 { $done = $true }
            38 { $CurrentIndex = ($CurrentIndex - 1 + $Items.Count) % $Items.Count }
            40 { $CurrentIndex = ($CurrentIndex + 1) % $Items.Count }
        }
    }

    return $Items[$CurrentIndex]
}

function Copy-FilteredContent {
    param (
        [string]$Source,
        [string]$Destination,
        [hashtable]$Filter
    )

    $filterType = $Filter.Type
    $paths = $Filter.Paths
    $files = Get-ChildItem -Path $Source -Recurse -Force -File

    foreach ($file in $files) {
        $relPath = $file.FullName.Substring($Source.Length).TrimStart("\\")
        switch ($filterType) {
            "Whitelist" {
                if ($paths -contains $relPath.Split('\')[0] -or $paths -contains $relPath) {
                    $destPath = Join-Path $Destination $relPath
                    New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
                    Copy-Item $file.FullName -Destination $destPath -Force
                }
            }
            "Blacklist" {
                if (-not ($paths -contains $relPath.Split('\')[0] -or $paths -contains $relPath)) {
                    $destPath = Join-Path $Destination $relPath
                    New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
                    Copy-Item $file.FullName -Destination $destPath -Force
                }
            }
            "Regex" {
                foreach ($pattern in $paths) {
                    if ($relPath -match $pattern) {
                        $destPath = Join-Path $Destination $relPath
                        New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
                        Copy-Item $file.FullName -Destination $destPath -Force
                        break
                    }
                }
            }
        }
    }
}

function Restore-FilteredContent {
    param (
        [string]$Key,
        [hashtable]$Item
    )

    $backupPath = "C:\backup\$Key"
    $sourcePath = $Item.Source
    if (-not (Test-Path $backupPath)) {
        Write-Warning "No backup found for $Key"
        return
    }

    $files = Get-ChildItem $backupPath -Recurse -File
    foreach ($file in $files) {
        $relPath = $file.FullName.Substring($backupPath.Length).TrimStart("\\")
        $dest = Join-Path $sourcePath $relPath
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Move-Item -Path $file.FullName -Destination $dest -Force
    }
}

function Install-Packages {
    param (
        [string[]]$Ids
    )

    foreach ($id in $Ids) {
        Write-Host "Installing: $id" -ForegroundColor Cyan
        Start-Process "winget" -ArgumentList @("install", "--id", $id, "--accept-source-agreements", "--accept-package-agreements", "-e") -Wait -NoNewWindow
    }
}


# Main Menu Loop
while ($true) {
    $action = Show-SingleSelectMenu -Items @("Backup", "Restore", "Install Packages", "List Packages", "Fix Winget", "Exit") -Prompt "======= Backup Manager ======="

    switch ($action) {
        "Backup" {
            $targets = Show-MultiSelectMenu -Items $BackupItems.Keys -Prompt "Select items to backup"
            foreach ($key in $targets) {
                $item = $BackupItems[$key]
                $dest = "C:\backup\$key"
                if ($dest.StartsWith("C:\backup\", [System.StringComparison]::InvariantCultureIgnoreCase)) {
                    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    Copy-FilteredContent -Source $item.Source -Destination $dest -Filter $item.Filter
                    Write-Host "Backed up: $key -> $dest"
                } else {
                    Write-Warning "Invalid destination path: $dest"
                }
            }
            Pause
        }
        "Restore" {
            $existingBackups = Get-ChildItem -Path "C:\backup" -Directory |
            Where-Object { $BackupItems.ContainsKey($_.Name) } |
            Select-Object -ExpandProperty Name

            if (-not $existingBackups) {
                Write-Host "No backups found in C:\backup" -ForegroundColor Red
                Pause
                continue
            }

            $keys = Show-MultiSelectMenu -Items $existingBackups -Prompt "Select items to restore"
            foreach ($key in $keys) {
                Restore-FilteredContent -Key $key -Item $BackupItems[$key]
                Write-Host "Restored: $key"
            }
            Pause
        }
        "Install Packages" {


            $selectedGroups = Show-MultiSelectMenu -Items $Packages.Keys -Prompt "Select package groups to install"

            $toInstall = @{}
            foreach ($group in $selectedGroups) {
                $toInstall[$group] = $Packages[$group]
            }

            if ($toInstall.Count -eq 0) {
                Write-Host "No packages selected." -ForegroundColor Red
                Pause
                continue
            }

            Clear-Host
            Write-Host "Install the following packages? (Y/n)" -ForegroundColor Cyan
            Write-Host ""

            foreach ($group in $Packages.Keys) {
                if (-not $toInstall.ContainsKey($group)) { continue }

                $capitalized = ($group.Substring(0, 1).ToUpper()) + $group.Substring(1)
                Write-Host "${capitalized}:" -ForegroundColor Yellow
                foreach ($pkg in $toInstall[$group]) {
                    Write-Host $pkg -ForegroundColor Gray
                }
                Write-Host ""
            }


            $confirmed = Show-YesNoPrompt
            if ($confirmed) {
                $flatList = @()
                foreach ($groupList in $toInstall.Values) {
                    $flatList += $groupList
                }
                Install-Packages -Ids $flatList
            } else {
                Write-Host "Installation cancelled."
            }

            Pause
        }
        "List Packages" {
            Clear-Host
            Write-Host "Available packages by category:`n" -ForegroundColor Cyan

            foreach ($group in $Packages.Keys) {
                $capitalized = ($group.Substring(0, 1).ToUpper()) + $group.Substring(1)
                Write-Host "${capitalized}:" -ForegroundColor Yellow
                foreach ($pkg in $Packages[$group]) {
                    Write-Host $pkg -ForegroundColor Gray
                }
                Write-Host ""
            }

            Pause
        }
        "Fix Winget" {
            Install-WinUtilChoco
            Start-Process -FilePath "choco" -ArgumentList "install winget -y --force" -NoNewWindow -Wait
        }
        "Exit" {
            break
        }
    }
}

function Install-WinUtilChoco {

    <#

    .SYNOPSIS
        Installs Chocolatey if it is not already installed

    #>

    try {

        # Install logic taken from https://chocolatey.org/install#individual
        Write-Host "Seems Chocolatey is not installed, installing now."
        Set-ExecutionPolicy Bypass -Scope Process -Force;
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    } catch {
        Write-Host "===========================================" -ForegroundColor Red
        Write-Host "--     Chocolatey failed to install     ---" -ForegroundColor Red
        Write-Host "===========================================" -ForegroundColor Red
    }

}
