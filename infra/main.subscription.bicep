targetScope = 'subscription'
// Subscription-scope template to create a resource group then deploy workload (automation, runbooks, schedules).

param location string
param resourceGroupName string
param prefix string = 'demo'
param automationAccountName string
param vmssName string
@description('Raw URL to start runbook (optional). Leave empty to skip runbooks.')
param runbookStartUrl string = 'https://raw.githubusercontent.com/koichino/dom_llm/main/runbooks/runbook-start-vmss.ps1'
@description('Raw URL to stop runbook (optional).')
param runbookStopUrl string = 'https://raw.githubusercontent.com/koichino/dom_llm/main/runbooks/runbook-stop-vmss.ps1'
param startScheduleTime string = '08:00'
param stopScheduleTime string = '00:00'
@allowed([
  'UTC'
  'Tokyo Standard Time'
])
param timeZone string = 'Tokyo Standard Time'
@description('Runbook content version (change to force overwrite on redeploy)')
param runbookContentVersion string = '1.0.0'
@description('Version to force recreation of job schedules (change to recreate)')
param jobScheduleVersion string = '1'

@description('Reuse existing resource group instead of creating it (resourceGroupName must already exist and location must match).')
param reuseExistingRg bool = false

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = if (!reuseExistingRg) {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': prefix
  }
}

// Deploy existing group-scope template after RG creation
module workload './main.bicep' = {
  name: 'workloadDeployment'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ rg ]
  params: {
    location: location
    prefix: prefix
    resourceGroupName: resourceGroupName
    automationAccountName: automationAccountName
    vmssName: vmssName
    runbookStartUrl: runbookStartUrl
    runbookStopUrl: runbookStopUrl
    startScheduleTime: startScheduleTime
    stopScheduleTime: stopScheduleTime
    timeZone: timeZone
    runbookContentVersion: runbookContentVersion
  jobScheduleVersion: jobScheduleVersion
  }
}

output automationAccountId string = workload.outputs.automationAccountId
output automationPrincipalId string = workload.outputs.automationPrincipalId
output runbooks string = workload.outputs.deployedRunbooks
output schedules string = workload.outputs.deployedSchedules
output jobSchedules string = workload.outputs.deployedJobSchedules
