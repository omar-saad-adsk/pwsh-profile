$env:COREPACK_NPM_REGISTRY = npm config get registry
$env:COREPACK_INTEGRITY_KEYS = "0"

Import-Module posh-git

$script:lastShownHistoryId = -1

function prompt {
    $lastCmd = Get-History -Count 1
    $gitStatus = Get-GitStatus

    $user = $env:USERNAME
    $computer = $env:COMPUTERNAME
    $time = (Get-Date).ToString("HH:mm:ss")
    $path = [string]$ExecutionContext.SessionState.Path.CurrentLocation

    if ($path.StartsWith($HOME)) {
        $path = $path.Replace($HOME, "~")
    }

    Write-Host "[${time}] " -ForegroundColor DarkGray -NoNewline
    Write-Host "${user}@${computer}" -ForegroundColor Cyan -NoNewline
    Write-Host " in " -ForegroundColor Gray -NoNewline
    Write-Host $path -ForegroundColor Yellow -NoNewline

    if ($gitStatus) {
        Write-Host " " -NoNewline
        Write-GitStatus $gitStatus
    }

    if ($lastCmd -and $lastCmd.Id -ne $script:lastShownHistoryId) {
        $script:lastShownHistoryId = $lastCmd.Id
        $duration = $lastCmd.EndExecutionTime - $lastCmd.StartExecutionTime
        $succeeded = $lastCmd.ExecutionStatus -eq 'Completed'

        if ($duration.TotalSeconds -lt 1) {
            $durationStr = "$([int]$duration.TotalMilliseconds)ms"
        } elseif ($duration.TotalMinutes -lt 1) {
            $durationStr = "$([math]::Round($duration.TotalSeconds, 2))s"
        } elseif ($duration.TotalHours -lt 1) {
            $durationStr = "$([math]::Round($duration.TotalMinutes, 2))m"
        } else {
            $durationStr = "$([math]::Round($duration.TotalHours, 2))h"
        }

        $symbol = if ($succeeded) { "✓" } else { "✗" }
        $color  = if ($succeeded) { "Green" } else { "Red" }

        Write-Host " $symbol " -ForegroundColor $color -NoNewline
        Write-Host "took ${durationStr}" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }

    return "⚡ "
}
