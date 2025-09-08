@description('Module to deploy Automation Runbooks (start/stop VMSS) and weekday schedules with job schedules.')
param automationAccountName string
param location string
@description('Runbook (start) name')
param startRunbookName string = 'rb-start-vmss'
@description('Runbook (stop) name')
param stopRunbookName string = 'rb-stop-vmss'
@description('Raw content URL for start runbook (PowerShell). Typically a GitHub raw URL.')
param runbookStartUrl string
@description('Raw content URL for stop runbook (PowerShell). Typically a GitHub raw URL.')
param runbookStopUrl string
@description('Start time (HH:MM) in local timeZone (e.g. Tokyo Standard Time).')
param startScheduleTime string = '08:00'
@description('Stop time (HH:MM) in local timeZone. Use 24:00 for next-day midnight.')
param stopScheduleTime string = '24:00'
@description('TZ name (display only); schedules use UTC times.')
param timeZone string = 'Asia/Tokyo'
@description('VM Scale Set resource group name (parameter passed to runbooks).')
param vmssResourceGroupName string
@description('VM Scale Set name (parameter passed to runbooks).')
param vmssName string

@description('Version string to force republish of runbook content (change to trigger overwrite).')
param runbookContentVersion string = '1.0.0'
@description('Version to force recreation of jobSchedules (increment to rebuild job schedules)')
param jobScheduleVersion string = '1'

@description('Anchor date (YYYY-MM-DD) for first schedule run (provided by parent).')
param scheduleAnchorDate string

// --- Simplified schedule logic (no timezone conversion) ---
// 1. Normalize anchor date (YYYYMMDD -> YYYY-MM-DD)
// 2. Use that date directly for start
// 3. If stop = 24:MM treat as next day 00:MM (Automation accepts 00:00 next day)
// 4. GUID recreation only by changing jobScheduleVersion

var baseDateRaw = scheduleAnchorDate
var normalizedBaseDate = length(baseDateRaw) == 8 ? '${substring(baseDateRaw,0,4)}-${substring(baseDateRaw,4,2)}-${substring(baseDateRaw,6,2)}' : baseDateRaw

var stopIsNextDay = startsWith(stopScheduleTime, '24:')
var effectiveStopHour = stopIsNextDay ? '00' : split(stopScheduleTime, ':')[0]
var effectiveStopMin = split(stopScheduleTime, ':')[1]
var nextDayDate = split(dateTimeAdd('${normalizedBaseDate}T00:00:00Z','P1D'),'T')[0]
var stopBaseDate = stopIsNextDay ? nextDayDate : normalizedBaseDate

var startTimeIso = '${normalizedBaseDate}T${startScheduleTime}:00'
var stopTimeIso = '${stopBaseDate}T${effectiveStopHour}:${effectiveStopMin}:00'


// Runbooks (content via publishContentLink)
resource startRunbook 'Microsoft.Automation/automationAccounts/runbooks@2020-01-13-preview' = {
  name: '${automationAccountName}/${startRunbookName}'
  location: location
  properties: {
    logProgress: true
    logVerbose: true
    runbookType: 'PowerShell'
    description: 'Start specified VM Scale Set'
    publishContentLink: {
      uri: runbookStartUrl
      version: runbookContentVersion
    }
  }
}

resource stopRunbook 'Microsoft.Automation/automationAccounts/runbooks@2020-01-13-preview' = {
  name: '${automationAccountName}/${stopRunbookName}'
  location: location
  properties: {
    logProgress: true
    logVerbose: true
    runbookType: 'PowerShell'
    description: 'Stop specified VM Scale Set'
    publishContentLink: {
      uri: runbookStopUrl
      version: runbookContentVersion
    }
  }
}

// Weekday schedules (Mon-Fri) using advancedSchedule
// NOTE: hours/minutes arrays not currently validated in type metadata; using simple weekly schedule with fixed names.

resource weekdayStart 'Microsoft.Automation/automationAccounts/schedules@2020-01-13-preview' = {
  name: '${automationAccountName}/WeekdayStart'
  properties: {
    description: 'Weekday (Mon-Fri) start schedule (${timeZone})'
    startTime: startTimeIso
    expiryTime: '2099-12-31T00:00:00Z'
    frequency: 'Week'
    interval: 1
  timeZone: timeZone
    advancedSchedule: {
      weekDays: [
        'Monday'
        'Tuesday'
        'Wednesday'
        'Thursday'
        'Friday'
      ]
    }
  }
}

resource weekdayStop 'Microsoft.Automation/automationAccounts/schedules@2020-01-13-preview' = {
  name: '${automationAccountName}/WeekdayStop'
  properties: {
    description: 'Weekday (Mon-Fri) stop schedule (${timeZone})'
    startTime: stopTimeIso
    expiryTime: '2099-12-31T00:00:00Z'
    frequency: 'Week'
    interval: 1
  timeZone: timeZone
    advancedSchedule: {
      weekDays: [
        'Monday'
        'Tuesday'
        'Wednesday'
        'Thursday'
        'Friday'
      ]
    }
  }
}

// Job schedules linking schedule -> runbook with parameters
var startJobGuidSeed = jobScheduleVersion
var stopJobGuidSeed = jobScheduleVersion

resource weekdayStartJob 'Microsoft.Automation/automationAccounts/jobSchedules@2020-01-13-preview' = {
  name: '${automationAccountName}/${guid(automationAccountName, 'WeekdayStartJob', startJobGuidSeed)}'
  properties: {
    runbook: {
      name: startRunbookName
    }
    schedule: {
    // For jobSchedules, the schedule name must be the short name (without automation account prefix)
  name: 'WeekdayStart'
    }
    parameters: {
      ResourceGroupName: vmssResourceGroupName
      VMScaleSetName: vmssName
    }
  }
  // Ensure both the runbook and the schedule exist before creating the job schedule
  dependsOn: [ startRunbook, weekdayStart ]
}

resource weekdayStopJob 'Microsoft.Automation/automationAccounts/jobSchedules@2020-01-13-preview' = {
  name: '${automationAccountName}/${guid(automationAccountName, 'WeekdayStopJob', stopJobGuidSeed)}'
  properties: {
    runbook: {
      name: stopRunbookName
    }
    schedule: {
    // Use short schedule name
  name: 'WeekdayStop'
    }
    parameters: {
      ResourceGroupName: vmssResourceGroupName
      VMScaleSetName: vmssName
    }
  }
  dependsOn: [ stopRunbook, weekdayStop ]
}

output startRunbookDeployed string = startRunbook.name
output stopRunbookDeployed string = stopRunbook.name
output schedules string = 'WeekdayStart,WeekdayStop'
output jobSchedules string = '${weekdayStartJob.name},${weekdayStopJob.name}'
