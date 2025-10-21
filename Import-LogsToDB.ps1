# Import-LogsToDB.ps1
# Import Windows CSV and Linux log files to SQLite

param(
    [string]$LogsRoot = "C:\LogVisualizer",
    [string]$DatabasePath = "C:\LogVisualizer\system_logs.db"
)

# === 1. Setup SQLite ===
$BinPath = Join-Path $LogsRoot "bin"
$env:PATH = "$BinPath;$env:PATH"

$SQLiteDll = Join-Path $BinPath "System.Data.SQLite.dll"
if (-not (Test-Path $SQLiteDll)) {
    throw "ERROR: System.Data.SQLite.dll not found in $BinPath"
}
Add-Type -Path $SQLiteDll

# === 2. Connect and ensure table structure ===
$connectionString = "Data Source=$DatabasePath;Version=3;"
$connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
$connection.Open()

# Create table if not exists (with os_type)
$createTable = @"
CREATE TABLE IF NOT EXISTS system_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip_address TEXT NOT NULL,
    log_level TEXT,
    message TEXT,
    timestamp TEXT,
    event_id INTEGER,
    source TEXT,
    machine_name TEXT,
    user_sid TEXT,
    process_id INTEGER,
    thread_id INTEGER,
    log_name TEXT,
    os_type TEXT DEFAULT 'windows',
    UNIQUE(ip_address, timestamp, message, source)
);
"@

$cmd = $connection.CreateCommand()
$cmd.CommandText = $createTable
$cmd.ExecuteNonQuery() | Out-Null
$cmd.Dispose()

# Add os_type column if missing (safe for existing DB)
$checkCol = $connection.CreateCommand()
$checkCol.CommandText = "PRAGMA table_info(system_logs);"
$reader = $checkCol.ExecuteReader()
$hasOsType = $false
while ($reader.Read()) {
    if ($reader["name"] -eq "os_type") { $hasOsType = $true }
}
$reader.Close()
$checkCol.Dispose()

if (-not $hasOsType) {
    $alterCmd = $connection.CreateCommand()
    $alterCmd.CommandText = "ALTER TABLE system_logs ADD COLUMN os_type TEXT DEFAULT 'windows';"
    $alterCmd.ExecuteNonQuery() | Out-Null
    $alterCmd.Dispose()
}

Write-Host "SUCCESS: Database ready" -ForegroundColor Green

# === 3. Helper: Parse Linux log line ===
function Parse-LinuxLogLine {
    param([string]$Line, [string]$LogName)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    # Пример: "Oct 21 01:07:39 host sshd[1234]: Accepted password..."
    $pattern = '^(?<month>\w{3})\s+(?<day>\d{1,2})\s+(?<time>\d{2}:\d{2}:\d{2})\s+(?<host>\S+)\s+(?<source>\S+)(\[\d+\])?:\s+(?<message>.+)$'
    if ($Line -match $pattern) {
        $year = (Get-Date).Year
        $dateStr = "$($matches.month) $($matches.day) $year $($matches.time)"
        try {
            $timestamp = [DateTime]::ParseExact(
                $dateStr,
                "MMM d yyyy HH:mm:ss",
                [System.Globalization.CultureInfo]::InvariantCulture
            ).ToString("yyyy-MM-dd HH:mm:ss")
        } catch {
            Write-Debug "Failed to parse date: $dateStr"
            $timestamp = "1970-01-01 00:00:00"
        }

        # Определяем уровень
        $level = "Information"
        if ($Line -match "(?i)fail|error|denied|invalid|refused") { $level = "Error" }
        elseif ($Line -match "(?i)warn|warning") { $level = "Warning" }

        return [PSCustomObject]@{
            Timestamp = $timestamp
            Level     = $level
            Source    = $matches.source
            Message   = $matches.message
            LogName   = $LogName
        }
    }
    return $null
}

# === 4. Import Windows logs (as before) ===
function Import-WindowsLogs {
    param($LogsRoot, $Connection)
    $count = 0
    $WindowsRoot = Join-Path $LogsRoot "Windows"
    if (-not (Test-Path $WindowsRoot)) { return 0 }

    $hostFolders = Get-ChildItem -Path $WindowsRoot -Directory -Name | Where-Object { $_ -match '^host_(\d{1,3}\.){3}\d{1,3}$' }
    foreach ($folder in $hostFolders) {
        $ip = $folder -replace '^host_'
        $folderPath = Join-Path $WindowsRoot $folder

        $csvFiles = @("01_System_Events.csv","02_Application_Events.csv","03_Security_Events.csv") | ForEach-Object {
            Join-Path $folderPath $_
        } | Where-Object { Test-Path $_ }

        foreach ($csvFile in $csvFiles) {
            $data = Import-Csv -Path $csvFile -Encoding UTF8 -ErrorAction Stop
            foreach ($row in $data) {
                $levelText = switch ($row.Level) {
                    '1' { 'Critical' }
                    '2' { 'Error' }
                    '3' { 'Warning' }
                    '4' { 'Information' }
                    default { $row.Level }
                }

                $cmd = $Connection.CreateCommand()
                $cmd.CommandText = @"
INSERT OR IGNORE INTO system_logs 
(ip_address, log_level, message, timestamp, event_id, source, machine_name, user_sid, process_id, thread_id, log_name, os_type)
VALUES (@ip, @level, @message, @timestamp, @eventId, @source, @machine, @userSid, @procId, @threadId, @logName, 'windows')
"@
                $cmd.Parameters.AddWithValue("@ip", $ip) | Out-Null
                $cmd.Parameters.AddWithValue("@level", $levelText) | Out-Null
                $cmd.Parameters.AddWithValue("@message", $row.Message) | Out-Null
                $cmd.Parameters.AddWithValue("@timestamp", $row.TimeCreated) | Out-Null
                $cmd.Parameters.AddWithValue("@eventId", [int]$row.Id) | Out-Null
                $cmd.Parameters.AddWithValue("@source", $row.Provider) | Out-Null
                $cmd.Parameters.AddWithValue("@machine", $row.MachineName) | Out-Null
                $cmd.Parameters.AddWithValue("@userSid", $row.UserId) | Out-Null
                $cmd.Parameters.AddWithValue("@procId", $(if ($row.ProcessId -match '^\d+$') { [int]$row.ProcessId } else { $null })) | Out-Null
                $cmd.Parameters.AddWithValue("@threadId", $(if ($row.ThreadId -match '^\d+$') { [int]$row.ThreadId } else { $null })) | Out-Null
                $cmd.Parameters.AddWithValue("@logName", $row.LogName) | Out-Null
                $count += $cmd.ExecuteNonQuery()
                $cmd.Dispose()
            }
        }
    }
    return $count
}

# === 5. Import Linux logs ===
function Import-LinuxLogs {
    param($LogsRoot, $Connection)
    $count = 0
    $LinuxRoot = Join-Path $LogsRoot "Linux"
    if (-not (Test-Path $LinuxRoot)) { return 0 }

    $hostFolders = Get-ChildItem -Path $LinuxRoot -Directory -Name | Where-Object { $_ -match '^host_(\d{1,3}\.){3}\d{1,3}$' }
    foreach ($folder in $hostFolders) {
        $ip = $folder -replace '^host_'
        $folderPath = Join-Path $LinuxRoot $folder

        # Поддерживаемые файлы
        $logFiles = @("auth.log", "syslog", "messages") | ForEach-Object {
            Join-Path $folderPath $_
        } | Where-Object { Test-Path $_ }

        foreach ($logFile in $logFiles) {
            $logName = Split-Path $logFile -Leaf
            Write-Host "   IMPORTING Linux log: $logName from $ip" -ForegroundColor Gray
            $lines = Get-Content -Path $logFile -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                $parsed = Parse-LinuxLogLine -Line $line -LogName $logName
                if ($parsed) {
                    $cmd = $Connection.CreateCommand()
                    $cmd.CommandText = @"
INSERT OR IGNORE INTO system_logs 
(ip_address, log_level, message, timestamp, source, log_name, os_type)
VALUES (@ip, @level, @message, @timestamp, @source, @logName, 'linux')
"@
                    $cmd.Parameters.AddWithValue("@ip", $ip) | Out-Null
                    $cmd.Parameters.AddWithValue("@level", $parsed.Level) | Out-Null
                    $cmd.Parameters.AddWithValue("@message", $parsed.Message) | Out-Null
                    $cmd.Parameters.AddWithValue("@timestamp", $parsed.Timestamp) | Out-Null
                    $cmd.Parameters.AddWithValue("@source", $parsed.Source) | Out-Null
                    $cmd.Parameters.AddWithValue("@logName", $parsed.LogName) | Out-Null
                    $count += $cmd.ExecuteNonQuery()
                    $cmd.Dispose()
                }
            }
        }
    }
    return $count
}

# === 6. Run import ===
$winCount = Import-WindowsLogs -LogsRoot $LogsRoot -Connection $connection
$linuxCount = Import-LinuxLogs -LogsRoot $LogsRoot -Connection $connection

$connection.Close()
Write-Host "`nDONE: Windows records added: $winCount" -ForegroundColor Cyan
Write-Host "DONE: Linux records added: $linuxCount" -ForegroundColor Green
Write-Host "DATABASE: $DatabasePath" -ForegroundColor White