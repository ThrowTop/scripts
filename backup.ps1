# Backup and Reset Configuration Script for Windows 11

# Define the backup and restore configuration table
$BackupItems = @(
    @{ Name = "Custom Programs"; Source = "C:\custom"; Target = "C:\Backup\custom"; 
        Filter = @{ Type = "Blacklist"; Paths = @("media\shadowplay") } },
    @{ Name = "ShareX Settings"; Source = "C:\Users\$env:USERNAME\Documents\ShareX"; Target = "C:\Backup\ShareX"; 
        Filter = @{ Type = "Whitelist"; Paths = @("ApplicationConfig.json", "HotkeysConfig.json") } },
    @{ Name = "Portal 2 Config + Sar"; Source = "C:\Program Files (x86)\Steam\steamapps\common\Portal 2\portal2"; Target = "C:\Backup\Portal2" 
        Filter = @{ Type =  "Whitelist"; Paths = @("cfg", "sar.dll")} },
    @{ Name = "CS:2 Config"; Source = "C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg"; Target = "C:\Backup\CS2" 
        Filter = @{ Type =  "Whitelist"; Paths = @("multi", "usercfg", "ae.cfg", "autoexec.cfg", "ez.cfg")} },
    @{ Name = "PowerShell Profile"; Source = "$PROFILE"; Target = "C:\Backup\PowerShellProfile" }
)

function Show-CheckboxMenu {
    param (
        [Parameter(Mandatory)] $Items,
        [string] $Prompt = "Select items:",
        [bool] $DefaultSelected = $false  
    )

    Import-Module PSReadLine
    $Selected = @($DefaultSelected) * $Items.Count
    $CurrentIndex = 0
    $done = $false
    $cancelled = $false

    while (-not $done) {
        Clear-Host
        Write-Host "$Prompt (Use Arrow keys and Space to select, Enter to confirm, Escape to cancel)" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($CurrentIndex -eq $i) {
                Write-Host "> [$(if ($Selected[$i]) {"X"} else {" "})] $($Items[$i].Name)" -ForegroundColor Yellow
            } else {
                Write-Host "  [$(if ($Selected[$i]) {"X"} else {" "})] $($Items[$i].Name)"
            }
        }

        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
        switch ($Key) {
            27 { $done = $true; $cancelled = $true }  # Escape key
            38 { $CurrentIndex = ($CurrentIndex - 1) % $Items.Count; if ($CurrentIndex -lt 0) { $CurrentIndex = $Items.Count - 1 } }
            40 { $CurrentIndex = ($CurrentIndex + 1) % $Items.Count }
            32 { $Selected[$CurrentIndex] = -not $Selected[$CurrentIndex] }
            13 { $done = $true }
        }
    }

    if ($cancelled) { return $null }
    return $Items | Where-Object { $Selected[$Items.IndexOf($_)] }
}



# Function to apply whitelist or blacklist filters
function Filter-Files {
    param (
        [string] $Source,
        [hashtable] $Filter
    )

    switch ($Filter.Type) {
        "Whitelist" {
            $results = @()
            foreach ($path in $Filter.Paths) {
                $fullPath = Join-Path -Path $Source -ChildPath $path
                if (Test-Path $fullPath) {
                    if ((Get-Item $fullPath) -is [System.IO.DirectoryInfo]) {
                        $results += Get-ChildItem -Path $fullPath -Recurse
                    } else {
                        $results += Get-Item -Path $fullPath
                    }
                }
            }
            return $results
        }
        "Blacklist" {
            return Get-ChildItem -Path $Source -Recurse | Where-Object {
                -not ($Filter.Paths | ForEach-Object {
                    $_.ToLower()
                } -contains $_.FullName.Substring($Source.Length).TrimStart("\").ToLower())
            }
        }
        default { return Get-ChildItem -Path $Source -Recurse }
    }
}

# Create the main menu
function Show-Menu {
    Clear-Host
    Write-Host "Configuration Backup & Reset Script" -ForegroundColor Green
    Write-Host "================================================="
    Write-Host "1. Backup Configuration"
    Write-Host "2. Restore Configuration"
    Write-Host "3. Install Default Programs"
    Write-Host "4. Zip Backup Folder"
    Write-Host "5. Exit"
    Write-Host "================================================="
}

# Backup function
function Backup-Configuration {
    Write-Host "Starting backup..." -ForegroundColor Yellow

    # Allow user to select items to back up
    $SelectedItems = Show-CheckboxMenu -Items $BackupItems -Prompt "Backup this item"
    if ($SelectedItems.Count -eq 0) {
        Write-Host "No items selected for backup." -ForegroundColor Red
        return
    }

    # Ensure backup folder exists
    $BackupFolder = "C:\Backup"
    if (!(Test-Path -Path $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder | Out-Null
    }

    # Iterate through selected items
    foreach ($Item in $SelectedItems) {
        $Source = $Item.Source
        $Target = "$BackupFolder\$(Split-Path -Leaf $Item.Target)"

        # Clean existing backup folder if it exists
        if (Test-Path -Path $Target) {
            Remove-Item -Path $Target -Recurse -Force
            Write-Host "Cleaned existing backup at $Target" -ForegroundColor Yellow
        }

        if (Test-Path -Path $Source) {
            try {
                $Files = if ($Item.ContainsKey("Filter")) {
                    Filter-Files -Source $Source -Filter $Item.Filter
                } else {
                    Get-ChildItem -Path $Source -Recurse
                }

                foreach ($File in $Files) {
                    if ($Item.ContainsKey("Filter") -and $Item.Filter.Type -eq "Whitelist") {
                        # For whitelist, preserve the relative path from the matched item
                        $RelativePath = $File.FullName.Substring($Source.Length).TrimStart("\")
                        $TargetPath = Join-Path -Path $Target -ChildPath $RelativePath
                    } else {
                        # For other cases, preserve the relative path structure
                        $TargetPath = Join-Path -Path $Target -ChildPath $File.FullName.Substring($Source.Length).TrimStart("\")
                    }
                    
                    if (-not (Test-Path -Path (Split-Path $TargetPath -Parent))) {
                        New-Item -ItemType Directory -Path (Split-Path $TargetPath -Parent) -Force | Out-Null
                    }
                    Copy-Item -Path $File.FullName -Destination $TargetPath -ErrorAction Stop
                }
                Write-Host "Backed up $($Item.Name) from $Source to $Target" -ForegroundColor Green
            } catch {
                Write-Host "$($Item.Name): Could not copy some files from $Source. Ignoring in-use files." -ForegroundColor Yellow
            }
        } else {
            Write-Host "$($Item.Name): Source path $Source does not exist!" -ForegroundColor Red
        }
    }

    Write-Host "Backup completed." -ForegroundColor Cyan
}


# Modified Restore-Configuration function
function Restore-Configuration {
    Write-Host "Restoring configuration..." -ForegroundColor Yellow

    $BackupFolder = "C:\Backup"
    $BackupZip = "$BackupFolder.zip"
    $usingZip = $false

    # Check if backup folder exists, if not try the zip
    if (-not (Test-Path -Path $BackupFolder)) {
        if (Test-Path -Path $BackupZip) {
            Expand-Archive -Path $BackupZip -DestinationPath $BackupFolder -Force
            Write-Host "No backup folder found. Extracted ZIP backup to $BackupFolder" -ForegroundColor Cyan
            $usingZip = $true
        } else {
            Write-Host "No backup folder or ZIP file found at $BackupFolder or $BackupZip" -ForegroundColor Red
            return
        }
    } else {
        Write-Host "Using existing backup folder at $BackupFolder" -ForegroundColor Cyan
    }

    $AvailableItems = @()
    foreach ($Item in $BackupItems) {
        if (Test-Path -Path "$BackupFolder\$(Split-Path -Leaf $Item.Target)") {
            $AvailableItems += $Item
        }
    }

    if ($AvailableItems.Count -eq 0) {
        Write-Host "No items available for restore." -ForegroundColor Red
        return
    }

    $SelectedItems = Show-CheckboxMenu -Items $AvailableItems -Prompt "Restore this item"
    if ($null -eq $SelectedItems) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
    if ($SelectedItems.Count -eq 0) {
        Write-Host "No items selected for restore." -ForegroundColor Red
        return
    }

    foreach ($Item in $SelectedItems) {
        $Source = "$BackupFolder\$(Split-Path -Leaf $Item.Target)"
        $Target = $Item.Source

        if (Test-Path -Path $Source) {
            # Get all files from the backup folder
            $Files = Get-ChildItem -Path $Source -File -Recurse
            foreach ($File in $Files) {
                # Get the relative path from the backup folder
                $RelativePath = $File.FullName.Substring($Source.Length).TrimStart("\")
                $DestinationPath = Join-Path -Path $Target -ChildPath $RelativePath
                
                # Create directory if it doesn't exist
                $DestinationDir = Split-Path -Path $DestinationPath -Parent
                if (!(Test-Path -Path $DestinationDir)) {
                    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
                }
                
                Copy-Item -Path $File.FullName -Destination $DestinationPath -Force
            }
            Write-Host "Restored $($Item.Name) from $Source to $Target" -ForegroundColor Green
        } else {
            Write-Host "$($Item.Name): Backup path $Source does not exist!" -ForegroundColor Red
        }
    }

    Write-Host "Restore complete from $(if ($usingZip) { 'ZIP archive' } else { 'backup folder' })." -ForegroundColor Cyan
}

# Zip backup folder
function Zip-BackupFolder {
    $BackupFolder = "C:\Backup"
    $BackupZip = "$BackupFolder.zip"

    if (Test-Path -Path $BackupFolder) {
        Compress-Archive -Path "$BackupFolder\*" -DestinationPath $BackupZip -Force
        Write-Host "Backup folder compressed into $BackupZip" -ForegroundColor Green
    } else {
        Write-Host "Backup folder not found at $BackupFolder" -ForegroundColor Red
    }
}

# Install default programs
function Install-DefaultPrograms {
    Write-Host "Installing default programs using winget..." -ForegroundColor Yellow


    # Yes im aware this is super fucking stupid but i cba remaking menu function
    $Programs = @(
        @{ Name = "Git.Git" },
        @{ Name = "winaero.tweaker" },
        @{ Name = "Microsoft.PowerToys" },
        @{ Name = "ajeetdsouza.zoxide" },
        @{ Name = "ShareX.ShareX" },
        @{ Name = "Brave.Brave" },
        @{ Name = "Valve.Steam" },
        @{ Name = "Flow-Launcher.Flow-Launcher" },
        @{ Name = "PrivateInternetAccess.PrivateInternetAccess" },
        @{ Name = "AutoHotkey.AutoHotkey" }
    )


    $SelectedPrograms = Show-CheckboxMenu -Items $Programs -Prompt "Select programs to install" -DefaultSelected $true
    if ($null -eq $SelectedPrograms) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
    if ($SelectedPrograms.Count -eq 0) {
        Write-Host "No programs selected for installation." -ForegroundColor Yellow
        return
    }

    foreach ($Program in $SelectedPrograms) {
        $ProgramName = $Program.Name  # Access the 'Name' property
        Write-Host "Installing $ProgramName..."
        winget install --id $ProgramName -e --silent
    }


    Write-Host "Program installation complete." -ForegroundColor Cyan
}

$active = $true
# Main menu loop
while ($active) {
    Show-Menu
    $Choice = Read-Host "Enter your choice"


    switch ($Choice) {
        1 { Backup-Configuration }
        2 { Restore-Configuration }
        3 { Install-DefaultPrograms }
        4 { Zip-BackupFolder }
        5 { $active = $false }
        default { Write-Host "Invalid choice, please try again." -ForegroundColor Red }
    }

    Pause
}
