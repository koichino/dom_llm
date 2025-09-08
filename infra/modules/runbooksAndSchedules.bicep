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
@description('Time (HH:MM, 24h, UTC) to start the VMSS on weekdays.')
param startScheduleTime string = '08:00'
@description('Time (HH:MM, 24h, UTC) to stop the VMSS on weekdays.')
param stopScheduleTime string = '00:00'
@description('TZ name (IANA/Windows) for display only; schedules use UTC times with advancedSchedule hours/minutes.')
param timeZone string = 'Asia/Tokyo'
@description('VM Scale Set resource group name (parameter passed to runbooks).')
param vmssResourceGroupName string
@description('VM Scale Set name (parameter passed to runbooks).')
param vmssName string

@description('Anchor start time (ISO 8601) for schedules startTime; default utcNow().')
param scheduleAnchorTime string = utcNow()

@description('Version string to force republish of runbook content (change to trigger overwrite).')
param runbookContentVersion string = '1.0.0'
@description('Version to force recreation of jobSchedules (increment to rebuild job schedules)')
param jobScheduleVersion string = '1'

// Compose first occurrence times (anchor date portion + provided HH:MM)
var anchorDate = split(scheduleAnchorTime, 'T')[0]
var startTimeIso = '${anchorDate}T${startScheduleTime}:00Z'
var stopTimeIso = '${anchorDate}T${stopScheduleTime}:00Z'


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
// NOTE: hours/minutes arrays not currently validated in type metadata; using simple daily schedule.
resource weekdayStart 'Microsoft.Automation/automationAccounts/schedules@2020-01-13-preview' = {
  name: '${automationAccountName}/WeekdayStart'
  properties: {
  description: 'Daily start schedule (${timeZone}) - filter to weekdays via runbook logic if needed'
  startTime: startTimeIso
    expiryTime: '2099-12-31T00:00:00Z'
    frequency: 'Day'
    interval: 1
    timeZone: timeZone
  }
}

resource weekdayStop 'Microsoft.Automation/automationAccounts/schedules@2020-01-13-preview' = {
  name: '${automationAccountName}/WeekdayStop'
  properties: {
  description: 'Daily stop schedule (${timeZone}) - filter to weekdays via runbook logic if needed'
  startTime: stopTimeIso
    expiryTime: '2099-12-31T00:00:00Z'
    frequency: 'Day'
    interval: 1
    timeZone: timeZone
  }
}

// Job schedules linking schedule -> runbook with parameters
resource weekdayStartJob 'Microsoft.Automation/automationAccounts/jobSchedules@2020-01-13-preview' = {
  name: '${automationAccountName}/${guid(automationAccountName, 'WeekdayStartJob', jobScheduleVersion)}'
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
  name: '${automationAccountName}/${guid(automationAccountName, 'WeekdayStopJob', jobScheduleVersion)}'
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
