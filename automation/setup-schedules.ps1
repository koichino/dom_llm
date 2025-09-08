<#
Helper script to create schedules and link them to Automation Runbooks.
Creates two schedules:
 - WeekdayStart: every weekday at 08:00
 - WeekdayStop: every weekday at 24:00 (midnight)

Usage:
.
$rg = 'rg-automation-demo'
$aa = 'demo-aa'
$startRunbook = 'rb-start-vmss'
$stopRunbook = 'rb-stop-vmss'

.
#>
param(
    [Parameter(Mandatory=$true)][string] $ResourceGroupName,
    [Parameter(Mandatory=$true)][string] $AutomationAccountName,
    [Parameter(Mandatory=$true)][string] $StartRunbookName,
    [Parameter(Mandatory=$true)][string] $StopRunbookName,
    [string] $TimeZone = 'UTC'
)

function New-WeekdaySchedule {
    param(
        [string] $name,
        [string] $time  # hh:mm in 24h
    )
    # Create a schedule that runs Mon-Fri at specified time
    $startTime = (Get-Date -Format 'yyyy-MM-dd') + "T$time:00Z"
    Write-Output "Creating schedule $name at $time ($TimeZone)"

    # If schedule exists, return
    $existingJson = az automation schedule show --resource-group $ResourceGroupName --automation-account-name $AutomationAccountName --name $name --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingJson) {
        Write-Output "Schedule $name already exists"
        return
    }

    az automation schedule create --resource-group $ResourceGroupName --automation-account-name $AutomationAccountName --name $name --start-time $startTime --expiry-time "2099-12-31T00:00:00Z" --interval 1 --frequency Day --description "Weekday schedule for $name" | Out-Null

    # Use REST API to update advancedSchedule to run only Mon-Fri at specified hour/minute
    $subId = az account show --query id -o tsv
    $scheduleResourceUri = "/subscriptions/$subId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/schedules/$name?api-version=2019-06-01"
    # parse time hh:mm
    $parts = $time -split ':'
    $hour = [int]$parts[0]
    $minute = [int]$parts[1]

    $body = @{
        properties = @{
            advancedSchedule = @{
                weekDays = @('Monday','Tuesday','Wednesday','Thursday','Friday')
                hours = @($hour)
                minutes = @($minute)
            }
        }
    } | ConvertTo-Json -Depth 6

    az rest --method PATCH --uri $scheduleResourceUri --body $body | Out-Null
}

function Link-ScheduleToRunbook {
    param(
        [string] $scheduleName,
        [string] $runbookName
    )

    Write-Output "Linking schedule $scheduleName to runbook $runbookName"
    az automation job-schedule create \
      --resource-group $ResourceGroupName \
      --automation-account-name $AutomationAccountName \
      --schedule-name $scheduleName \
      --runbook-name $runbookName | Out-Null
}

# Create schedules
New-WeekdaySchedule -name 'WeekdayStart' -time '08:00'
New-WeekdaySchedule -name 'WeekdayStop' -time '00:00'

# Link them
Link-ScheduleToRunbook -scheduleName 'WeekdayStart' -runbookName $StartRunbookName
Link-ScheduleToRunbook -scheduleName 'WeekdayStop' -runbookName $StopRunbookName

Write-Output "Schedules and links created. Note: CLI has limited ability to set day-of-week recurrence; verify recurrence (Mon-Fri) in portal or use REST API for precise recurrence settings." 
