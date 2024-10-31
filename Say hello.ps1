# Script: JU.ps1

$baseDir = "C:\Users\Andrew.Piper\OneDrive - Sabey Corporation\Documents\Automated_Deployment_Logic"

# Define subdirectories under the base directory
$filesDir = Join-Path -Path $baseDir -ChildPath "Script_Files"  # Main directory for script files
$newInstallDir = Join-Path -Path $baseDir -ChildPath "New_Install_Files"  # Base directory for new installations
$templateDir = Join-Path -Path $newInstallDir -ChildPath "New_Install_Template"  # Template files for new installs
$restoreDir = Join-Path -Path $filesDir -ChildPath "Script_File_Restore"  # Directory for restoring script files
$logDir = Join-Path -Path $filesDir -ChildPath "Script_Logs"  # Directory for logs

# Ensure necessary directories exist
foreach ($dir in @($filesDir, $newInstallDir, $templateDir, $restoreDir, $logDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

# Prompt for the root password once
$securePassword = Read-Host "Enter password for root user" -AsSecureString
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

# ----------------------------- Logging Function -----------------------------

function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$level] $message"

    # Set colors based on the log level
    switch ($level) {
        "ERROR"    { $color = "Red" }
        "WARNING"  { $color = "Yellow" }
        "SUCCESS"  { $color = "Green" }
        "INFO"     { $color = "Cyan" }
        default    { $color = "Gray" }
    }

    # Customize colors: timestamp in white, command in blue, status updates in aqua
    if ($message -match "^[^[]+\] [^[]+\] (.+)$") {
        $command = $matches[1]
        if ($command -match "^[a-zA-Z]") {
            Write-Host "$logMessage" -ForegroundColor $color
        } else {
            Write-Host "[$timestamp] [$level] " -ForegroundColor White -NoNewline
            Write-Host "$command" -ForegroundColor Blue
        }
    } else {
        Write-Host "$logMessage" -ForegroundColor $color
    }

    # Write to log file
    $logFilePath = Join-Path $logDir "JU_$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFilePath -Value $logMessage
}


# ----------------------------- Serial Connection Functions -----------------------------

function Initialize-SerialConnection {
    param (
        [int]$baudRate = 9600,
        [int]$dataBits = 8,
        [string]$parity = "None",
        [string]$stopBits = "One",
        [string]$handshake = "None",
        [int]$waitTime = 5000
    )
    Write-Log -message "Detecting and initializing serial connection..."

    # Detect available COM ports
    $comPorts = [System.IO.Ports.SerialPort]::GetPortNames() | Where-Object { $_ -match '^COM\d+$' } | Sort-Object
    Write-Log -message "Available COM ports detected: $([string]::Join(', ', $comPorts))"

    # If no COM ports are found, log an error and exit
    if ($comPorts.Count -eq 0) {
        Write-Log -message "No COM ports available. Please connect a device and try again." -level "ERROR"
        return $null
    }

    # Use the first available port directly as a string
    $selectedPort = $comPorts

    try {
        # Initialize the serial connection with specific settings
        $serialPort = New-Object System.IO.Ports.SerialPort($selectedPort, $baudRate, $parity, $dataBits, $stopBits)
        $serialPort.Handshake = [System.IO.Ports.Handshake]::None  # Explicitly set Handshake
        $serialPort.ReadTimeout = $waitTime
        $serialPort.WriteTimeout = $waitTime
        $serialPort.Open()
        Start-Sleep -Milliseconds 500
        Write-Log -message "Serial connection established on port $selectedPort."
        return $serialPort
    } catch {
        Write-Log -message "Failed to initialize serial connection: $_" -level "ERROR"
        return $null
    }
}


function Close-SerialConnection {
    param (
        [System.IO.Ports.SerialPort]$serialPort
    )

    # Send exit commands to properly close the session on the switch
    if ($serialPort -and $serialPort.IsOpen) {
        Write-Log -message "Sending exit commands..."
        Send-SerialCommand -serialPort $serialPort -command "exit"
        Send-SerialCommand -serialPort $serialPort -command "exit"
        Send-SerialCommand -serialPort $serialPort -command "exit"
        Send-SerialCommand -serialPort $serialPort -command "exit"
        Start-Sleep -Milliseconds 250

        # Now close the serial connection
        $serialPort.Close()
        Write-Log -message "Serial connection closed."
    }
}

function Send-SerialCommand {
    param (
        [System.IO.Ports.SerialPort]$serialPort,
        [string]$command,
        [int]$waitTime = 250
    )
    # Suppress the actual password in the log and screen output
    if ($command -eq $plainPassword) {
        #Write-Log -message "[Suppressed for security]"
    } else {
        Write-Log -message "$command"
    }

    try {
        $serialPort.WriteLine($command)
        Start-Sleep -Milliseconds $waitTime
    } catch {
        Write-Log -message "Error sending command '$command': $_" -level "ERROR"
        throw $_
    }
}

function Perform-LoginSequence {
    param (
        [System.IO.Ports.SerialPort]$serialPort
    )

    $success = $false
    Write-Log -message "Starting login sequence..."

    do {
        try {
            # Send initial ENTER keystrokes to wake up the console
            $serialPort.WriteLine("")
            $serialPort.WriteLine("")

            # Read the initial response after waking up the console
            $response = $serialPort.ReadExisting()

            # Use switch to handle different response scenarios
            switch ($response) {
                {$_ -match "login:"} {
                    Write-Log -message "Login prompt detected. Sending 'root'..."
                    $serialPort.WriteLine("root")
                    Start-Sleep -Seconds 1

                    # Read the response after sending "root"
                    $response = $serialPort.ReadExisting()
                }
                {$_ -match "Password:"} {
                    Write-Log -message "Password prompt detected. Sending password..."
                    $serialPort.WriteLine($plainPassword)
                    Start-Sleep -Seconds 1

                    # Read the response after sending the password
                    $response = $serialPort.ReadExisting()
                }
                {$_ -match "root@:RE:0%"} {
                    Write-Log -message "Root mode detected. Sending 'cli'..."
                    $serialPort.WriteLine("cli")
                    Start-Sleep -Seconds 1
                }
                {$_ -match "root>"} {
                    Write-Log -message "Entering to CLI mode..."
                    $serialPort.WriteLine("edit")
                    Start-Sleep -Seconds 1
                }
                {$_ -match "root#"} {
                    Write-Log -message "Successfully entered Configuration mode." -level "SUCCESS"
                    $success = $true  # Mark as successful
                }
                default {
                    Write-Log -message "Unexpected response. Retrying the login sequence." -level "WARNING"
                    Start-Sleep -Seconds 1
                }
            }

        } catch {
            Write-Log -message "Error during login sequence: $_" -level "ERROR"
        }
    } until ($success)

    if (-not $success) {
        throw "Login sequence failed."
    }
}

function Execute-ConfigurationCommands {
    param (
        [System.IO.Ports.SerialPort]$serialPort,
        [string]$hostname
    )

    # Run Perform-LoginSequence before proceeding with configuration
    try {
        Perform-LoginSequence -serialPort $serialPort
    } catch {
        Write-Log -message "Login sequence failed; configuration cannot proceed." -level "ERROR"
        return
    }

    # Combined list of commands to be executed sequentially
    $commands = @(
        "delete chassis auto-image-upgrade",
        "set system root-authentication plain-text-password",
        $plainPassword,
        $plainPassword,
        "commit",
        "set system host-name VC-Temp",
        "set virtual-chassis auto-sw-update",
        "set chassis alarm management-ethernet link-down ignore",
        "delete interfaces me0",
        "delete interfaces vme",
        "set interfaces vme unit 0 family inet address 192.168.0.2/30",
        "set system services ssh",
        "set system services ssh root-login allow",
        'set system login message "***************************************************************************\n*                          WARNING NOTICE                                 *\n***************************************************************************\n* This system is the property of SABEY Data Centers. Unauthorized         *\n* access to or use of this system is strictly prohibited. All activities  *\n* on this system are monitored and recorded. By accessing this system,    *\n* you acknowledge that you are authorized to do so and consent to such    *\n* monitoring. Any unauthorized use or access may result in disciplinary   *\n* action, and where applicable, criminal prosecution.                     *\n*                                                                         *\n* If you are not an authorized user, disconnect immediately.              *\n*                                                                         *\n* For support, contact SABEY IT Department.                               *\n***************************************************************************"',
        "commit"
    )

    # Execute all commands sequentially
    foreach ($command in $commands) {
        Send-SerialCommand -serialPort $serialPort -command $command
        if ($command -like "commit*") {
            Start-Sleep -Seconds 5
        }
    }
}

function Get-SwitchVersionInfo {
    param (
        [System.IO.Ports.SerialPort]$serialPort
    )

    # Send the "run show system information" command
    $versionCommand = "run show system information"
    Send-SerialCommand -serialPort $serialPort -command $versionCommand
    Start-Sleep -Milliseconds 1000  # Wait for the command to execute

    # Initialize the variable to hold the response
    $response = ""

    # Read the response from the serial port until all data is captured
    $timeout = [datetime]::Now.AddSeconds(2)  # Set a 3-second timeout
    while ($serialPort.BytesToRead -gt 0 -or [datetime]::Now -lt $timeout) {
        $response += $serialPort.ReadExisting()
        Start-Sleep -Milliseconds 20  # Wait to allow more data to come in
    }

    # DEBUG: Display the raw response to ensure all data was captured
    #Write-Host "Raw Response: $response" -ForegroundColor Yellow

    # Split the response into lines for easier parsing
    $responseLines = $response -split "`r`n"

    # Extract the Model and Junos by matching the lines that contain the information
    $model = $responseLines | Where-Object { $_ -match "Model:" } | ForEach-Object { $_ -replace "Model:\s*", "" }
    $junos = $responseLines | Where-Object { $_ -match "Junos:" } | ForEach-Object { $_ -replace "Junos:\s*", "" }

    # Ensure we have valid values before displaying
    if (-not $model) {
        $model = "Unknown Model"
    }
    if (-not $junos) {
        $junos = "Unknown Junos"
    }

    # Display Model and Junos in blue
    Write-Host "Model: $model" -ForegroundColor Blue
    Write-Host "Junos: $junos" -ForegroundColor Blue

    # Return Model and Junos as an object for use in other functions
    return [PSCustomObject]@{
        Model = $model
        Junos = $junos
    }
}

function Execute-HostConfiguration {
    param (
        [System.IO.Ports.SerialPort]$serialPort,
        [string]$hostname,
        [PSCustomObject]$hostEntry
    )

    $startTime = Get-Date

    # Extract necessary values from the CSV row
    $iirb = $hostEntry.iirb
    $iip = $hostEntry.iip
    $route_iip = $iip -replace '\d+$', '1'
    $location = $hostname.Substring(5, 3)

    # Calculate VLANs based on IIRB value
    $preStageVlan = [int]$iirb + 10
    $preBMS = [int]$iirb + 40
    $preEPMS = [int]$iirb + 50
    $preSEC = [int]$iirb + 60
    $preIT = [int]$iirb + 70

    # Prepare VLANs based on non-blank entries
    $vlans = @()
    for ($i = 1; $i -le 20; $i++) {
        $vlanColumn = "vlan$i"
        $vlanValue = $hostEntry."$vlanColumn"
        if ($vlanValue -and $vlanValue -match "(.+):(\d+)") {
            $vlans += [PSCustomObject]@{
                Name = $matches[1]
                ID   = $matches[2]
            }
        }
    }

    # Call Get-SwitchVersionInfo to check and log JUNOS version info
    $switchInfo = Get-SwitchVersionInfo -serialPort $serialPort
    $model = $switchInfo.Model
    $junos = $switchInfo.Junos
    
    Write-Log -message "Setting system host-name to: $hostname"

    # Execute the initial set of commands
    $commands = @(
        "set system host-name $hostname",
        "commit",
        "set snmp location $location",
        "set snmp contact sdcnetsys@sabey.com",
        "set snmp community ""U%jQ67LB"" authorization read-only",
        "set snmp trap-group snmp_agents targets 10.20.20.250",
        "commit",
        "set virtual-chassis member 0 mastership-priority 255",
        "set virtual-chassis member 1 mastership-priority 128",
        "set chassis aggregated-devices ethernet device-count 10",
        "set vlans $location-MGMT vlan-id $iirb",
        "set switch-options voip interface access-ports vlan $location-VOIP",
        "set routing-options static route 0.0.0.0/0 next-hop $route_iip",
        "set interfaces irb unit $iirb family inet address $iip/24",
        "set vlans $location-MGMT l3-interface irb.$iirb",
        "set vlans Pre-Stage vlan-id $preStageVlan",
        "set vlans Pre-BMS vlan-id $preBMS",
        "set vlans Pre-EPMS vlan-id $preEPMS",
        "set vlans Pre-SEC vlan-id $preSEC",
        "set vlans Pre-IT vlan-id $preIT"
    )

    # Execute the commands
    foreach ($command in $commands) {
        Send-SerialCommand -serialPort $serialPort -command $command
        if ($command -like "commit*") {
            Start-Sleep -Seconds 5
        }
    }

    # Execute VLAN creation commands without committing after each VLAN
    $vlanCommands = @()
    foreach ($vlan in $vlans) {
        $vlanCommands += "set vlans $($vlan.Name) vlan-id $($vlan.ID)"
    }

    # Commit after all VLANs are set
    if ($vlanCommands.Count -gt 0) {
        $vlanCommands += "commit"
        foreach ($vlanCommand in $vlanCommands) {
            Send-SerialCommand -serialPort $serialPort -command $vlanCommand
        }
        Start-Sleep -Seconds 3
    }
    
    if ($switchInfo) {
        Write-Log -message "Switch model: $($switchInfo.Model), JUNOS version: $($switchInfo.Junos)"
        
        # If the switch model is not EX4600, run the additional commands
        if ($switchInfo.Model -ne "ex4600") {
            $additionalCommands = @(
                "delete interfaces xe-0/2/2",
                "delete interfaces xe-0/2/3",
                "set interfaces xe-0/2/2 ether-options 802.3ad ae0",
                "set interfaces xe-0/2/3 ether-options 802.3ad ae0",
                "set interfaces ae0 aggregated-ether-options lacp active",
                "set interfaces ae0 aggregated-ether-options lacp periodic fast",
                "set interfaces ae0 unit 0 family ethernet-switching interface-mode trunk",
                "set interfaces ae0 unit 0 family ethernet-switching vlan members all",
                "commit"
            )

            Write-Log -message "Running additional configuration for non-EX4600 model."
            foreach ($command in $additionalCommands) {
                Send-SerialCommand -serialPort $serialPort -command $command
            }

            # Delete RSTP, then delete GE interfaces in bundles of 47, and finally assign to Pre-Stage VLAN
            $groupCommands = @()
            for ($i = 0; $i -le 47; $i++) {
                $interface = "ge-0/0/$i"
                $groupCommands += "delete protocols rstp interface $interface"
            }

            # Execute the RSTP deletion commands
            foreach ($cmd in $groupCommands) {
                Send-SerialCommand -serialPort $serialPort -command $cmd
            }

            # Commit after deleting RSTP protocols
            Send-SerialCommand -serialPort $serialPort -command "commit"
            Start-Sleep -Seconds 5

            # Delete the interfaces for the group
            $groupCommands = @()
            for ($i = 0; $i -le 47; $i++) {
                $interface = "ge-0/0/$i"
                $groupCommands += "delete interfaces $interface"
            }
            foreach ($cmd in $groupCommands) {
                Send-SerialCommand -serialPort $serialPort -command $cmd
            }
            Start-Sleep -Seconds 3

            # Assign interfaces to Pre-Stage VLAN
            $groupCommands = @()
            for ($i = 0; $i -le 47; $i++) {
                $interface = "ge-0/0/$i"
                $groupCommands += "set interfaces $interface unit 0 family ethernet-switching vlan members Pre-Stage"
            }
            foreach ($cmd in $groupCommands) {
                Send-SerialCommand -serialPort $serialPort -command $cmd
            }
            Start-Sleep -Seconds 3

            # Commit after processing the group
            Send-SerialCommand -serialPort $serialPort -command "commit"
            Start-Sleep -Seconds 3

            # Set RSTP protocols on all GE interfaces after committing changes
            $rstpCommands = @()
            for ($i = 0; $i -le 47; $i++) {
                $interface = "ge-0/0/$i"
                $rstpCommands += "set protocols rstp interface $interface"
            }

            # Execute the RSTP setting commands
            foreach ($cmd in $rstpCommands) {
                Send-SerialCommand -serialPort $serialPort -command $cmd
            }
        }
    }

    # Final commit after setting RSTP on all interfaces
    Send-SerialCommand -serialPort $serialPort -command "commit"
    Start-Sleep -Seconds 5

    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Convert duration to minutes and seconds
    $minutes = [math]::Floor($duration.TotalMinutes)
    $seconds = $duration.Seconds + ($duration.Milliseconds / 1000)
    $formattedTime = "${minutes}m ${seconds:0.00}s"

    Write-Log -message "Your $($switchInfo.Model) configuration deployment completed in $formattedTime."
}




# ----------------------------- Menu Functions -----------------------------

function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "Juniper Switch Automation Script" -ForegroundColor Cyan
        Write-Host "---------------------------------" -ForegroundColor Cyan
        Write-Host "1) New Install"
        Write-Host "2) Restore from Backup"
        Write-Host "0) Exit"
        Write-Host "Select an option: " -ForegroundColor DarkGray -NoNewline
        $selection = Read-Host

        switch ($selection) {
            '1' {
                Show-NewInstallMenu
            }
            '2' {
                Show-RestoreMenu
            }
            '0' {
                Exit
            }
            default {
                Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            }
        }
    } while ($true)
}

function Show-NewInstallMenu {
    if (-not (Test-Path "$newInstallDir\New_Install_Test.csv")) {
        Write-Log -message "New_Install_Test.csv file not found in $newInstallDir" -level "ERROR"
        Pause
        return
    }

    $hostEntries = Import-Csv -Path "$newInstallDir\New_Install_Test.csv"
    if ($hostEntries.Count -eq 0) {
        Write-Log -message "No entries found in New_Install_Test.csv" -level "WARNING"
        Pause
        return
    }

    do {
        Clear-Host
        Write-Host "New Install Menu" -ForegroundColor Cyan
        Write-Host "----------------" -ForegroundColor Cyan
        for ($i = 0; $i -lt $hostEntries.Count; $i++) {
            Write-Host "$($i + 1)) $($hostEntries[$i].hostname)"
        }
        Write-Host "9) Template"
        Write-Host "0) Return to Main Menu"
        Write-Host "Select a host to configure: " -ForegroundColor DarkGray -NoNewline
        $selection = Read-Host

        if ($selection -eq '0') {
            return
        } elseif ($selection -eq '9') {
            Show-TemplateMenu
        } elseif ($selection -match '^\d+$' -and [int]$selection -le $hostEntries.Count -and [int]$selection -ge 1) {
            $selectedEntry = $hostEntries[$selection - 1]
            $hostname = $selectedEntry.hostname
            $serialPort = Initialize-SerialConnection
            if ($serialPort) {
                Perform-LoginSequence -serialPort $serialPort
                Execute-ConfigurationCommands -serialPort $serialPort
                Execute-HostConfiguration -serialPort $serialPort -hostname $hostname -hostEntry $selectedEntry
                Close-SerialConnection -serialPort $serialPort
            }
            Pause
        } else {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        }
    } while ($true)
}

function Show-TemplateMenu {
    $templateFiles = Get-ChildItem -Path $templateDir -Filter "*.txt"
    if ($templateFiles.Count -eq 0) {
        Write-Log -message "No template files found in $templateDir" -level "WARNING"
        Pause
        return
    }

    do {
        Clear-Host
        Write-Host "Template Files Menu" -ForegroundColor Cyan
        Write-Host "-------------------" -ForegroundColor Cyan
        for ($i = 0; $i -lt $templateFiles.Count; $i++) {
            Write-Host "$($i + 1)) $($templateFiles[$i].Name)"
        }
        Write-Host "0) Return to New Install Menu"
        Write-Host "Select a template file to use: " -ForegroundColor DarkGray -NoNewline
        $selection = Read-Host

        if ($selection -eq '0') {
            return
        } elseif ($selection -match '^\d+$' -and [int]$selection -le $templateFiles.Count -and [int]$selection -ge 1) {
            $selectedFile = $templateFiles[$selection - 1].FullName
            Write-Log -message "Template file selected: $selectedFile"
            # Implement the logic to use the selected template file
            Pause
        } else {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        }
    } while ($true)
}

function Show-RestoreMenu {
    $backupFiles = Get-ChildItem -Path $restoreDir -Filter "*.txt"
    if ($backupFiles.Count -eq 0) {
        Write-Log -message "No backup files found in $restoreDir" -level "WARNING"
        Pause
        return
    }

    do {
        Clear-Host
        Write-Host "Restore from Backup Menu" -ForegroundColor Cyan
        Write-Host "------------------------" -ForegroundColor Cyan
        for ($i = 0; $i -lt $backupFiles.Count; $i++) {
            Write-Host "$($i + 1)) $($backupFiles[$i].Name)"
        }
        Write-Host "0) Return to Main Menu"
        Write-Host "Select a backup file to restore: " -ForegroundColor DarkGray -NoNewline
        $selection = Read-Host

        if ($selection -eq '0') {
            return
        } elseif ($selection -match '^\d+$' -and [int]$selection -le $backupFiles.Count -and [int]$selection -ge 1) {
            $selectedFile = $backupFiles[$selection - 1].FullName
            $hostname = [System.IO.Path]::GetFileNameWithoutExtension($selectedFile)
            $serialPort = Initialize-SerialConnection
            if ($serialPort) {
                Perform-LoginSequence -serialPort $serialPort
                Execute-ConfigurationCommands -serialPort $serialPort -hostname $hostname
                Close-SerialConnection -serialPort $serialPort
            }
            Pause
        } else {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        }
    } while ($true)
}

# ----------------------------- Start Script -----------------------------

try {
    Show-MainMenu
} catch {
    Write-Log -message "Unhandled exception: $_" -level "ERROR"
}
