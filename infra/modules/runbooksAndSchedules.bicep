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
@description('Start time (HH:MM) JST 固定 (Asia/Tokyo)')
param startScheduleTime string = '08:00'
@description('Stop time (HH:MM) JST 固定。24:00 指定で翌日 00:00 と解釈')
param stopScheduleTime string = '24:00'
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
@description('Expiry date (YYYY-MM-DD) for schedules')
param expiryDate string = '2099-12-31'

// Normalize anchor date (handles YYYYMMDD fallback)
var normalizedBaseDate = length(scheduleAnchorDate) == 8 ? '${substring(scheduleAnchorDate,0,4)}-${substring(scheduleAnchorDate,4,2)}-${substring(scheduleAnchorDate,6,2)}' : scheduleAnchorDate

// utcNow() only allowed in parameter default. Use a hidden parameter to capture deployment time.
@description('Deployment timestamp (比較用)')
param deploymentTimestamp string = utcNow()

// --- シンプルロジック (Asia/Tokyo 固定, UTC/DST 非対応) ---
// 1. stopScheduleTime が 24:MM の場合 翌日 00:MM に変換
// 2. start/stop それぞれ "現在+5分" より過去なら翌日に日付のみ +1 (HH:MM は保持)
// 3. 生成形式: YYYY-MM-DDTHH:MM:SS+09:00

var jstOffset = '+09:00'
// 固定タイムゾーン (param から var に変更)
// Azure Automation は Windows タイムゾーン ID を推奨 (例: 'Tokyo Standard Time')
// 以前 'Asia/Tokyo' を指定すると開始時刻が 1 時間ずれる事象が発生したため修正
var timeZone = 'Tokyo Standard Time'
var minAllowed = dateTimeAdd(deploymentTimestamp, 'PT5M')

// Start / Stop 正規化 (24: → 翌日 00:MM)
// 翌日計算基準日 (start/stop 共通)
var nextDayDateSimple = split(dateTimeAdd('${normalizedBaseDate}T00:00:00Z','P1D'),'T')[0]

// Start 側
var startIsNextDaySimple = startsWith(startScheduleTime, '24:')
var startEffectiveHourSimple = startIsNextDaySimple ? '00' : split(startScheduleTime, ':')[0]
var startEffectiveMinSimple = split(startScheduleTime, ':')[1]
var startBaseDateSimple = startIsNextDaySimple ? nextDayDateSimple : normalizedBaseDate

// Stop 側
var stopIsNextDaySimple = startsWith(stopScheduleTime, '24:')
var effectiveStopHourSimple = stopIsNextDaySimple ? '00' : split(stopScheduleTime, ':')[0]
var effectiveStopMinSimple = split(stopScheduleTime, ':')[1]
var stopBaseDateSimple = stopIsNextDaySimple ? nextDayDateSimple : normalizedBaseDate

// ローカル (JST) 表現
var candidateStartLocal = '${startBaseDateSimple}T${startEffectiveHourSimple}:${startEffectiveMinSimple}:00${jstOffset}'
var candidateStopLocal  = '${stopBaseDateSimple}T${effectiveStopHourSimple}:${effectiveStopMinSimple}:00${jstOffset}'

// 比較 & 出力用 UTC (Automation schedule は timeZone 指定時 UTC で渡す方がズレが出ない)
var candidateStartUtc = dateTimeAdd(candidateStartLocal,'-PT9H') // returns ...Z
var candidateStopUtc  = dateTimeAdd(candidateStopLocal,'-PT9H')

// 翌日にロール (UTC 基準)
var candidateStartUtcNextDay = dateTimeAdd(candidateStartUtc,'P1D')
var candidateStopUtcNextDay  = dateTimeAdd(candidateStopUtc,'P1D')

var startTimeIso = candidateStartUtc < minAllowed ? candidateStartUtcNextDay : candidateStartUtc
var stopTimeIso  = candidateStopUtc  < minAllowed ? candidateStopUtcNextDay  : candidateStopUtc

// Expiry: ローカル日付 00:00 JST を UTC に (前日 15:00Z) 変換
var expiryLocalJst = '${expiryDate}T00:00:00${jstOffset}'
var expiryTimeIso = dateTimeAdd(expiryLocalJst,'-PT9H')


// Runbooks (content via publishContentLink)
resource startRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
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

resource stopRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
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

resource weekdayStart 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
  name: '${automationAccountName}/WeekdayStart'
  properties: {
    description: 'Weekday (Mon-Fri) start schedule (${timeZone})'
  startTime: startTimeIso
    expiryTime: expiryTimeIso
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

resource weekdayStop 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
  name: '${automationAccountName}/WeekdayStop'
  properties: {
    description: 'Weekday (Mon-Fri) stop schedule (${timeZone})'
  startTime: stopTimeIso
    expiryTime: expiryTimeIso
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

resource weekdayStartJob 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
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

resource weekdayStopJob 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
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
