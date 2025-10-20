function Test-Port {
    param(
        [string]$IP,
        [int]$Port,
        [int]$Timeout = 3000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $result = $tcpClient.BeginConnect($IP, $Port, $null, $null)
        $wait = $result.AsyncWaitHandle.WaitOne($Timeout, $false)
        
        if ($wait -and $tcpClient.Connected) {
            $tcpClient.EndConnect($result)
            $tcpClient.Close()
            return $true
        }
        $tcpClient.Close()
    } catch {
    }
    return $false
}

function Detect-OS {
    param(
        [string]$IP,
        [PSCredential]$Credential
    )
    
    Write-Host "Detecting OS for: $IP" -ForegroundColor Yellow
    
    $sshPortOpen = Test-Port -IP $IP -Port 22
    $winrmPortOpen = Test-Port -IP $IP -Port 5985
    $winrmSSLPortOpen = Test-Port -IP $IP -Port 5986
    
    Write-Host "  Port scan - SSH: $sshPortOpen, WinRM: $winrmPortOpen, WinRM SSL: $winrmSSLPortOpen" -ForegroundColor Gray
    
    if ($winrmPortOpen -or $winrmSSLPortOpen) {
        try {
            Write-Host "  Trying WinRM connection..." -ForegroundColor Gray
            $osInfo = Invoke-Command -ComputerName $IP -Credential $Credential -ScriptBlock { 
                (Get-CimInstance Win32_OperatingSystem).Caption 
            } -ErrorAction Stop
            Write-Host "✅ Windows detected on $IP (via WinRM): $osInfo" -ForegroundColor Green
            return "Windows"
        } catch {
            Write-Host "  WinRM connection failed: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }    
    if ($sshPortOpen) {
    try {
        Write-Host "  Trying SSH connection..." -ForegroundColor Gray
        
        $sshpassAvailable = Get-Command sshpass -ErrorAction SilentlyContinue
        $username = $Credential.UserName
        
        if (-not $sshpassAvailable) {
            Write-Host "  sshpass not available, trying direct SSH..." -ForegroundColor Yellow
            $osInfo = & ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${username}@${IP}" "uname -s" 2>$null
        } else {
            $password = $Credential.GetNetworkCredential().Password
            $osInfo = & sshpass -p "`"$password`"" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${username}@${IP}" "uname -s" 2>$null
        }
        
        if ($osInfo -and $osInfo.Trim() -eq "Linux") {
            Write-Host "✅ Linux detected on $IP (via SSH)" -ForegroundColor Green
            return "Linux"
        }
    } catch {
        Write-Host "  SSH connection failed: $($_.Exception.Message)" -ForegroundColor Gray
    }
}
     

    if ($winrmPortOpen -or $winrmSSLPortOpen) {
        Write-Host "✅ Windows detected on $IP (WinRM port open)" -ForegroundColor Green
        return "Windows"
    }
    
    if ($sshPortOpen) {
        Write-Host "✅ Linux detected on $IP (SSH port open)" -ForegroundColor Green
        return "Linux"
    }
    
    Write-Host "❌ Unable to detect OS for: $IP" -ForegroundColor Red
    return "Unknown"
}

function Get-WindowsEventLogs {
    param(
        [string]$IP,
        [PSCredential]$Credential,
        [string]$LocalDestination = "$env:USERPROFILE\Desktop\Collected_Logs\Windows"
    )

    Write-Host "Collecting Windows logs from: $IP" -ForegroundColor Cyan

    try {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $IP -Force

        $LogDir = "$LocalDestination\$IP_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

        Write-Host "Connecting to $IP..." -ForegroundColor Yellow
        
        $allEvents = Invoke-Command -ComputerName $IP -Credential $Credential -ScriptBlock {
            return @{
                SystemEvents = Get-EventLog -LogName System -Newest 50
                ApplicationEvents = Get-EventLog -LogName Application -Newest 50
                SecurityEvents = Get-EventLog -LogName Security -Newest 20
                SystemInfo = systeminfo
                NetworkInfo = ipconfig /all
            }
        }
        
        Write-Host "Saving events..." -ForegroundColor Yellow
        
function Export-CsvWithBom {
    param(
        [Parameter(Mandatory)]
        [object[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$Path
    )
    if ($null -eq $InputObject -or $InputObject.Count -eq 0) {
        Set-Content -Path $Path -Value "sep=," -Encoding UTF8
        return
    }
    $csvLines = $InputObject | ConvertTo-Csv -NoTypeInformation
    $utf8WithBom = New-Object System.Text.UTF8Encoding $true 
    [System.IO.File]::WriteAllLines($Path, $csvLines, $utf8WithBom)
}

Export-CsvWithBom -InputObject $allEvents.SystemEvents -Path "$LogDir\01_System_Events.csv"
Export-CsvWithBom -InputObject $allEvents.ApplicationEvents -Path "$LogDir\02_Application_Events.csv"
Export-CsvWithBom -InputObject $allEvents.SecurityEvents -Path "$LogDir\03_Security_Events.csv"

$allEvents.SystemInfo | Out-File "$LogDir\04_System_Info.txt" -Encoding Default
$allEvents.NetworkInfo | Out-File "$LogDir\05_Network_Info.txt" -Encoding Default
        Write-Host "✅ Windows logs collected from: $IP" -ForegroundColor Green
        return @{Status = "Success"; Path = $LogDir; IP = $IP}
    }
    catch {
        Write-Host "❌ Failed to collect Windows logs from $IP : $($_.Exception.Message)" -ForegroundColor Red
        return @{Status = "Failed"; Path = ""; IP = $IP; Error = $_.Exception.Message}
    }
}

function Get-AstraLogs {
    param(
        [string]$IP,
        [PSCredential]$Credential,
        [string]$RemoteLogDir = "/var/log",
        [string]$LocalDestination = "$env:USERPROFILE\Desktop\Collected_Logs\Linux"
    )
    
    Write-Host "Collecting Astra Linux logs from: $IP" -ForegroundColor Cyan

    try {
        $LogDir = "$LocalDestination\$IP_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (!(Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force
        }

        $password = $Credential.GetNetworkCredential().Password
        $username = $Credential.UserName

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $remoteArchive = "/tmp/logs_backup_$timestamp.tar.gz"
        
        Write-Host "Creating archive on remote machine..." -ForegroundColor Yellow
        
        $sshpassAvailable = Get-Command sshpass -ErrorAction SilentlyContinue
        
        $archiveCommand = "sudo tar -czf $remoteArchive -C $RemoteLogDir . 2>/dev/null"
        $fallbackCommand = "tar -czf $remoteArchive -C $RemoteLogDir ."
        
        if ($sshpassAvailable) {
            $process = Start-Process -FilePath "sshpass" -ArgumentList "-p", "`"$password`"", "ssh", "${username}@${IP}", $archiveCommand -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -ne 0) {
                Write-Host "  First attempt failed, trying without sudo..." -ForegroundColor Yellow
                $process = Start-Process -FilePath "sshpass" -ArgumentList "-p", "`"$password`"", "ssh", "${username}@${IP}", $fallbackCommand -Wait -PassThru -NoNewWindow
            }
        } else {
            Write-Host "sshpass not available. Please enter SSH password when prompted..." -ForegroundColor Yellow
            $process = Start-Process -FilePath "ssh" -ArgumentList "${username}@${IP}", $archiveCommand -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -ne 0) {
                Write-Host "  First attempt failed, trying without sudo..." -ForegroundColor Yellow
                $process = Start-Process -FilePath "ssh" -ArgumentList "${username}@${IP}", $fallbackCommand -Wait -PassThru -NoNewWindow
            }
        }
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Archive created successfully" -ForegroundColor Green
            
            Write-Host "Copying archive..." -ForegroundColor Yellow
            $localArchive = "$LogDir\logs_backup_$timestamp.tar.gz"
            
            if ($sshpassAvailable) {
                $process = Start-Process -FilePath "sshpass" -ArgumentList "-p", "`"$password`"", "scp", "${username}@${IP}:${remoteArchive}", $localArchive -Wait -PassThru -NoNewWindow
            } else {
                Write-Host "Please enter SSH password again for SCP..." -ForegroundColor Yellow
                $process = Start-Process -FilePath "scp" -ArgumentList "${username}@${IP}:${remoteArchive}", $localArchive -Wait -PassThru -NoNewWindow
            }
            
            if ($process.ExitCode -eq 0) {
                Write-Host "Archive copied successfully" -ForegroundColor Green
                
                if ($sshpassAvailable) {
                    Start-Process -FilePath "sshpass" -ArgumentList "-p", "`"$password`"", "ssh", "${username}@${IP}", "rm -f $remoteArchive" -Wait -NoNewWindow
                } else {
                    Start-Process -FilePath "ssh" -ArgumentList "${username}@${IP}", "rm -f $remoteArchive" -Wait -NoNewWindow
                }
                
=                Write-Host "Extracting archive..." -ForegroundColor Yellow
                $tarAvailable = Get-Command tar -ErrorAction SilentlyContinue
                if ($tarAvailable) {
                    & tar -xzf $localArchive -C $LogDir
                    Remove-Item $localArchive
                    Write-Host "✅ Astra Linux logs collected from: $IP" -ForegroundColor Green
                } else {
                    Write-Host "Archive saved as: $localArchive" -ForegroundColor Yellow
                }
                
                return @{Status = "Success"; Path = $LogDir; IP = $IP}
            } else {
                Write-Host "❌ Error copying archive from $IP" -ForegroundColor Red
                return @{Status = "Failed"; Path = ""; IP = $IP; Error = "Error copying archive"}
            }
        } else {
            Write-Host "❌ Error creating archive on $IP" -ForegroundColor Red
            return @{Status = "Failed"; Path = ""; IP = $IP; Error = "Error creating archive"}
        }
    } catch {
        Write-Host "❌ Execution error for $IP : $($_.Exception.Message)" -ForegroundColor Red
        return @{Status = "Failed"; Path = ""; IP = $IP; Error = $_.Exception.Message}
    }
}

function Get-NetworkComputers {
    param([string]$BaseIP)
    
    Write-Host "Scanning network for connected computers (parallel ping)..." -ForegroundColor Cyan
    
    $ipParts = $BaseIP -split '\.'
    $subnet = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2])"
    $timeoutMs = 500
    $jobs = @()

    
    for ($i = 1; $i -lt 255; $i++) {
        $ip = "$subnet.$i"
        $sb = {
            param($ip, $to)
            $p = New-Object System.Net.NetworkInformation.Ping
            try {
                if (($p.Send($ip, $to)).Status -eq 'Success') { return $ip }
            } catch {}
            finally { $p.Dispose() }
        }
        $jobs += Start-Job -ScriptBlock $sb -ArgumentList $ip, $timeoutMs
    }

    
    $total = $jobs.Count
    $lastPercent = -1
    do {
        $completed = ($jobs | Where-Object State -in 'Completed', 'Failed').Count
        $percent = [math]::Floor(($completed / $total) * 100)
        if ($percent -ne $lastPercent) {
            Write-Progress -Activity "Scanning network (parallel)" -Status "Checked $completed of $total IPs" -PercentComplete $percent
            $lastPercent = $percent
        }
        Start-Sleep -Milliseconds 300
    } while ($completed -lt $total)

    $computers = @()
    foreach ($job in $jobs) {
        if ($result = Receive-Job $job -ErrorAction SilentlyContinue) {
            Write-Host "Found active device: $result" -ForegroundColor Green
            $computers += $result
        }
        Remove-Job $job -Force
    }

    Write-Progress -Activity "Scanning network" -Completed
    return $computers
}

Write-Host "`nChecking dependencies..." -ForegroundColor Cyan

$sshpassAvailable = Get-Command sshpass -ErrorAction SilentlyContinue
if (-not $sshpassAvailable) {
    Write-Host "    sshpass not installed. Linux log collection may require manual password entry." -ForegroundColor Yellow
    Write-Host "   To install sshpass on Windows:" -ForegroundColor Yellow
    Write-Host "   - Download from: https://sourceforge.net/projects/sshpass/  " -ForegroundColor Yellow
    Write-Host "   - Or use Chocolatey: choco install sshpass" -ForegroundColor Yellow
}

Write-Host "`nPlease enter the required information:" -ForegroundColor Cyan

$MainIP = Read-Host "Enter main machine IP address"
$Username = Read-Host "Enter administrator username"
$SecurePassword = Read-Host "Enter password" -AsSecureString

$credential = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)

Write-Host "`nStarting network scan and log collection..." -ForegroundColor Cyan

$MainLogDir = "$env:USERPROFILE\Desktop\Collected_Logs"
New-Item -ItemType Directory -Path "$MainLogDir\Windows" -Force | Out-Null
New-Item -ItemType Directory -Path "$MainLogDir\Linux" -Force | Out-Null

$networkComputers = Get-NetworkComputers -BaseIP $MainIP

if ($networkComputers.Count -eq 0) {
    Write-Host "No connected computers found. Checking main IP only..." -ForegroundColor Yellow
    $networkComputers = @($MainIP)
}

$results = @()

foreach ($computer in $networkComputers) {
    $ipParts = $computer -split '\.'
    $lastOctet = [int]$ipParts[3]
    
    if ($lastOctet -eq 1 -or $lastOctet -eq 255) {
        Write-Host "⏭️ Skipping reserved IP: $computer" -ForegroundColor Yellow
        $results += @{Status = "Skipped"; Path = ""; IP = $computer; Error = "Reserved IP (gateway/broadcast)"}
        continue
    }

    Write-Host "`n--- Processing: $computer ---" -ForegroundColor Magenta
    
    $osType = Detect-OS -IP $computer -Credential $credential
    
    if ($osType -eq "Unknown") {
        Write-Host "⏭️ Skipping $computer - not Windows or Linux" -ForegroundColor Yellow
        $results += @{Status = "Skipped"; Path = ""; IP = $computer; Error = "Not Windows/Linux"}
        continue
    }

    switch ($osType) {
        "Windows" {
            $result = Get-WindowsEventLogs -IP $computer -Credential $credential
            $results += $result
        }
        "Linux" {
            $result = Get-AstraLogs -IP $computer -Credential $credential
            $results += $result
        }
        default {
            Write-Host "❌ Unexpected OS type: $osType on $computer" -ForegroundColor Red
            $results += @{Status = "Skipped"; Path = ""; IP = $computer; Error = "Unexpected OS: $osType"}
        }
    }
}
Write-Host "`n=== COLLECTION SUMMARY ===" -ForegroundColor Cyan

$totalScanned = $networkComputers.Count
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$failedCount  = ($results | Where-Object { $_.Status -eq "Failed"  }).Count
$skippedCount = ($results | Where-Object { $_.Status -eq "Skipped" }).Count

Write-Host "Network scan completed. Found $totalScanned active device$(if ($totalScanned -ne 1) { 's' })." -ForegroundColor White
Write-Host "Collected logs: $successCount" -ForegroundColor Green
Write-Host "Failed: $failedCount" -ForegroundColor Red
Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow

if ($successCount -gt 0) {
    Write-Host "`n Logs saved to:" -ForegroundColor Green
    Write-Host "   $MainLogDir"
    
    Write-Host "`n Detailed results:" -ForegroundColor Cyan
    Write-Host ("{0,-17} {1,-10} {2,-50} {3}" -f "IP", "Status", "Path", "Error") -ForegroundColor Cyan
    Write-Host ("-" * 80)

    foreach ($item in ($results | Where-Object { $_ -and $_.IP })) {
        $displayPath = if ($item.Path) { $item.Path } else { "" }
        $displayError = if ($item.Error) { $item.Error } else { "" }
        if ($displayPath.Length -gt 48) {
            $displayPath = $displayPath.Substring(0, 45) + "..."
        }
        Write-Host ("{0,-17} {1,-10} {2,-50} {3}" -f $item.IP, $item.Status, $displayPath, $displayError)
    }

    Invoke-Item $MainLogDir
}

Write-Host ("`n" + ("=" * 50)) -ForegroundColor DarkGray

Read-Host "Press Enter to exit"
