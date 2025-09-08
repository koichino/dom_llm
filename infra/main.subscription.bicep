targetScope = 'subscription'
// Subscription-scope template to create a resource group then deploy workload (automation, runbooks, schedules).

param location string
param resourceGroupName string
param prefix string = 'demo'
param automationAccountName string
param vmssName string
@description('Raw URL to start runbook (optional). Leave empty to skip runbooks.')
param runbookStartUrl string = ''
@description('Raw URL to stop runbook (optional).')
param runbookStopUrl string = ''
param startScheduleTime string = '08:00'
param stopScheduleTime string = '00:00'
param timeZone string = 'UTC'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
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
  }
}

output automationAccountId string = workload.outputs.automationAccountId
output automationPrincipalId string = workload.outputs.automationPrincipalId
output runbooks string = workload.outputs.deployedRunbooks
output schedules string = workload.outputs.deployedSchedules
