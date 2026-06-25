$env:COREPACK_NPM_REGISTRY = npm config get registry
$env:COREPACK_INTEGRITY_KEYS = "0"

$env:NODE_EXTRA_CA_CERTS = "C:\Users\saado\AppData\Local\mkcert\rootCA.pem" # "$(mkcert -CAROOT)/rootCA.pem"

function awsl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,

        [Parameter(Mandatory = $false)]
        [ValidateSet("prod", "staging", "dev")]
        [string]$Stage = "prod"
    )

    Write-Host "[1/8] Setting Vault address for stage: $Stage" -ForegroundColor Cyan

    switch ($Stage) {
        "dev"     { $env:VAULT_ADDR = "https://civ1.dv.adskengineer.net" }
        "staging" { $env:VAULT_ADDR = "https://civ1.st.adskengineer.net" }
        "prod"    { $env:VAULT_ADDR = "https://civ1.pr.adskengineer.net" }
        default   { 
            Write-Host "Unknown stage: $Stage" -ForegroundColor Red
        }
    }

    Write-Host "[2/8] Logging in to Vault using OIDC..." -ForegroundColor Cyan
    Invoke-Expression "vault login -method=oidc"

    Write-Host "[3/8] Fetching credentials from Vault for account: $Account" -ForegroundColor Cyan
    # Call vault to get credentials as JSON
    $vaultCmd = "vault read -format=json account/$Account/sts/Owner ttl=4h"
    $vaultDataJson = Invoke-Expression $vaultCmd

    Write-Host "[4/8] Parsing credentials JSON" -ForegroundColor Cyan
    # Parse JSON for credentials using ConvertFrom-Json and extract them safely
    try {
        $vaultData = $vaultDataJson | ConvertFrom-Json
        $accessKey = $vaultData.data.access_key
        $secretKey = $vaultData.data.secret_key
        $sessionToken = $vaultData.data.security_token
        Write-Host "[5/8] Successfully parsed credentials" -ForegroundColor Green
    } catch {
        Write-Host "Failed to parse credentials from vault." -ForegroundColor Red
    }

    Write-Host "[6/8] Composing AWS credentials content" -ForegroundColor Cyan
    # Write credentials to ~/.aws/credentials
    $credentialsContent = @"
[default]
aws_access_key_id = $accessKey
aws_secret_access_key = $secretKey
aws_session_token = $sessionToken
"@

    # Ensure the .aws directory exists
    $awsCredentialsPath = Join-Path $HOME ".aws\credentials"
    $awsDir = Split-Path $awsCredentialsPath
    Write-Host "[7/8] Ensuring .aws directory exists at: $awsDir" -ForegroundColor Cyan
    if (!(Test-Path $awsDir)) {
        New-Item -ItemType Directory -Path $awsDir | Out-Null
    }

    Write-Host "[8/8] Writing credentials to $awsCredentialsPath" -ForegroundColor Cyan
    $credentialsContent | Set-Content -Path $awsCredentialsPath -Encoding UTF8 -Force

    Write-Host "Verifying credentials with AWS STS..." -ForegroundColor Cyan
    aws sts get-caller-identity --no-cli-pager
}

Import-Module posh-git

$script:lastShownHistoryId = -1

function prompt {
    $succeeded_exitcode = $LASTEXITCODE -eq 0 # 2
    $succeded_qm = $? # 3
    $lastCmd = Get-History -Count 1
    $succeeded_status = $lastCmd.ExecutionStatus -eq 'Completed' # 1

    $user = $env:USERNAME
    $computer = $env:COMPUTERNAME
    $time = [DateTime]::Now.ToString("HH:mm:ss")
    $path = [string]$ExecutionContext.SessionState.Path.CurrentLocation.Path

    if ($path.StartsWith($HOME)) {
        $path = $path.Replace($HOME, "~")
    }

    if ($status = Get-GitStatus -Force) {
        if ($status.HasWorking) {
            $gitstatus += (Write-GitWorkingDirStatusSummary $status -NoLeadingSpace) +
                       "$(Write-GitWorkingDirStatus $status) "
        }
        if ($status.HasWorking -and $status.HasIndex) {
            $gitstatus += "| "
        }
        if ($status.HasIndex) {
            $gitstatus += "$(Write-GitIndexStatus $status -NoLeadingSpace) "
        }
        $gitstatus += "$(Write-GitBranchStatus $status -NoLeadingSpace)$(Write-GitBranchName $status)"
    }

    Write-Host "${user}@${computer}" -ForegroundColor Cyan -NoNewline
    Write-Host " in" -ForegroundColor Gray -NoNewline
    Write-Host " $path" -ForegroundColor Yellow -NoNewline
    if ($status) {
        Write-Host " [" -ForegroundColor Yellow -NoNewline
        Write-Host "$gitstatus" -NoNewline
        Write-Host "]" -ForegroundColor Yellow -NoNewline
    }

    if ($lastCmd -and $lastCmd.Id -ne $script:lastShownHistoryId) {
        $script:lastShownHistoryId = $lastCmd.Id
        $duration = $lastCmd.EndExecutionTime - $lastCmd.StartExecutionTime

        if ($duration.TotalSeconds -lt 1) {
            $durationStr = "$([int]$duration.TotalMilliseconds)ms"
        } elseif ($duration.TotalSeconds -lt 100) {
            $durationStr = "$([math]::Round($duration.TotalSeconds, 2))s"
        } elseif ($duration.TotalMinutes -lt 100) {
            $durationStr = "$([math]::Round($duration.TotalMinutes, 2))m"
        } else {
            $durationStr = "$([math]::Round($duration.TotalHours, 2))h"
        }

        $symbol_status = if ($succeeded_status) { "✓" } else { "✗" }
        $symbol_exitcode = if ($succeeded_exitcode) { "✓" } else { "✗" }
        $symbol_qm = if ($succeded_qm) { "✓" } else { "✗" }

        $color_status = if ($succeeded_status) { "Green" } else { "Red" }
        $color_exitcode = if ($succeeded_exitcode) { "Green" } else { "Red" }
        $color_qm = if ($succeded_qm) { "Green" } else { "Red" }

        Write-Host " $symbol_status" -ForegroundColor $color_status -NoNewline
        Write-Host "$symbol_exitcode" -ForegroundColor $color_exitcode -NoNewline
        Write-Host "$symbol_qm" -ForegroundColor $color_qm -NoNewline
        Write-Host " took ${durationStr}" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
    
    Write-Host "[${time}]" -ForegroundColor DarkGray -NoNewline

    return "⚡$('>' * ($nestedPromptLevel)) "
}
