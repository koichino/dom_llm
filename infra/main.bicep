// Root Bicep that composes modular infra resources (Automation Account, VMSS, etc.).
param location string = resourceGroup().location
param prefix string = 'demo'
@description('The name of the resource group where resources are deployed. Defaults to the current deployment resource group.')
param resourceGroupName string = resourceGroup().name
@description('Name of the Automation Account to create (pass at deployment time)')
param automationAccountName string
@description('Name of the VM Scale Set (vmss) to manage (pass at deployment time)')
param vmssName string

@description('Raw URL (e.g. GitHub raw) to the start VMSS runbook PowerShell script')
param runbookStartUrl string = ''
@description('Raw URL (e.g. GitHub raw) to the stop VMSS runbook PowerShell script')
param runbookStopUrl string = ''
@description('HH:MM (UTC) weekday start time')
param startScheduleTime string = '08:00'
@description('HH:MM (UTC) weekday stop time')
param stopScheduleTime string = '00:00'
@description('Time zone label (display only)')
param timeZone string = 'UTC'

// Automation Account module
// Automation Account module
module automation 'modules/automationAccount.bicep' = {
  name: 'automationAccountModule'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: automationAccountName
    location: location
  }
}

// VMSS module (placeholder) - extend this when adding VMSS configuration
module vmss 'modules/vmss.bicep' = {
  name: 'vmssModule'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmssName
    location: location
  }
}

// Runbooks & schedules (optional: only if URLs provided)
module runbooks 'modules/runbooksAndSchedules.bicep' = {
  name: 'runbooksModule'
  scope: resourceGroup(resourceGroupName)
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
  }
}

output automationAccountId string = automation.outputs.automationAccountId
output automationPrincipalId string = automation.outputs.automationAccountPrincipalId
output vmssPlaceholder string = vmss.outputs.placeholderMessage
output deployedRunbooks string = runbooks.outputs.startRunbookDeployed
output deployedSchedules string = runbooks.outputs.schedules

