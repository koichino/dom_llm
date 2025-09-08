targetScope = 'subscription'

// Unified subscription-scope template (creates or reuses RG, then deploys modules). This replaces former main.subscription.bicep + group main.
param location string
param resourceGroupName string
param prefix string = 'demo'
@description('Name of the Automation Account to create')
param automationAccountName string
@description('Name of the VM Scale Set (managed by runbooks)')
param vmssName string
@description('Raw URL (GitHub raw) to the start VMSS runbook PowerShell script')
param runbookStartUrl string = 'https://raw.githubusercontent.com/koichino/dom_llm/main/runbooks/runbook-start-vmss.ps1'
@description('Raw URL (GitHub raw) to the stop VMSS runbook PowerShell script')
param runbookStopUrl string = 'https://raw.githubusercontent.com/koichino/dom_llm/main/runbooks/runbook-stop-vmss.ps1'
@description('HH:MM (UTC) weekday start time')
param startScheduleTime string = '08:00'
@description('HH:MM (UTC) weekday stop time')
param stopScheduleTime string = '00:00'
@allowed([
  'UTC'
  'Tokyo Standard Time'
])
@description('Display time zone (schedules use UTC internally)')
param timeZone string = 'Tokyo Standard Time'
@description('Runbook content version (change to force overwrite on redeploy)')
param runbookContentVersion string = '1.0.0'
@description('Version to force recreation of job schedules (change to recreate)')
param jobScheduleVersion string = '1'
@description('Reuse existing resource group instead of creating it')
param reuseExistingRg bool = false

// Resource group (conditional)
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = if (!reuseExistingRg) {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': prefix
  }
}

// Modules deployed into RG
module automation 'modules/automationAccount.bicep' = {
  name: 'automationAccountModule'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ rg ]
  params: {
    name: automationAccountName
    location: location
  }
}

module vmss 'modules/vmss.bicep' = {
  name: 'vmssModule'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ rg ]
  params: {
    name: vmssName
    location: location
  }
}

module runbooks 'modules/runbooksAndSchedules.bicep' = {
  name: 'runbooksModule'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ automation ]
  params: {
    automationAccountName: automationAccountName
    location: location
    runbookStartUrl: runbookStartUrl
    runbookStopUrl: runbookStopUrl
    startScheduleTime: startScheduleTime
    stopScheduleTime: stopScheduleTime
    timeZone: timeZone
    vmssResourceGroupName: resourceGroupName
    vmssName: vmssName
    runbookContentVersion: runbookContentVersion
    jobScheduleVersion: jobScheduleVersion
  }
}

output automationAccountId string = automation.outputs.automationAccountId
output automationPrincipalId string = automation.outputs.automationAccountPrincipalId
output vmssPlaceholder string = vmss.outputs.placeholderMessage
output deployedRunbooks string = runbooks.outputs.startRunbookDeployed
output deployedSchedules string = runbooks.outputs.schedules
output deployedJobSchedules string = runbooks.outputs.jobSchedules

