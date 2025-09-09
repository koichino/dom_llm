targetScope = 'subscription'

// Unified subscription-scope template (creates or reuses RG, then deploys modules). This replaces former main.subscription.bicep + group main.
param location string
param resourceGroupName string
param prefix string = 'demo'

// 共通タグ (必要に応じて追加拡張)
var commonTags = {
  'azd-env-name': prefix
}
@description('Name of the Automation Account to create')
param automationAccountName string
@description('Name of the VM Scale Set (managed by runbooks)')
param vmssName string
@description('Raw URL (GitHub raw) to the start VMSS runbook PowerShell script')
param runbookStartUrl string = 'https://raw.githubusercontent.com/koichino/dom_llm/main/infra/runbooks/runbook-start-vmss.ps1'
@description('Raw URL (GitHub raw) to the stop VMSS runbook PowerShell script')
param runbookStopUrl string = 'https://raw.githubusercontent.com/koichino/dom_llm/main/infra/runbooks/runbook-stop-vmss.ps1'
@description('平日開始時刻 (HH:MM) 指定 timeZone のローカル時刻')
param startScheduleTime string = '08:00'
@description('平日停止時刻 (HH:MM) 指定 timeZone のローカル時刻。24:00 可')
param stopScheduleTime string = '00:00'
@description('スケジュール解釈用タイムゾーン (例: Tokyo Standard Time)')
param timeZone string = 'Tokyo Standard Time'
@description('Runbook content version (change to force overwrite on redeploy)')
param runbookContentVersion string = '1.0.0'
@description('Version to force recreation of job schedules (change to recreate)')
param jobScheduleVersion string = '1'
@description('Anchor date (YYYY-MM-DD) for first schedule run; override to tomorrow if current time already passed desired HH:MM today')
param scheduleAnchorDate string = split(utcNow(), 'T')[0]
@description('Reuse existing resource group instead of creating it')
param reuseExistingRg bool = false

// Network / Application Gateway parameters
@description('VNet name')
param vnetName string = 'vnet-web'
@description('App Gateway subnet name')
param appGatewaySubnetName string = 'appGatewaySubnet'
@description('Backend subnet name (for VMSS)')
param backendSubnetName string = 'backendSubnet'
@description('Backend subnet NSG name')
param backendNsgName string = 'nsg-backend'
@description('Public IP name for Application Gateway')
param publicIpName string = 'agw-pip'
@description('Application Gateway name')
param appGatewayName string = 'agw-web'
@description('Application Gateway backend pool name')
param backendPoolName string = 'vmssPool'
@description('Application Gateway HTTP settings name')
param httpSettingsName string = 'appGatewayBackendHttpSettings'
@description('Application Gateway probe name')
param probeName string = 'probe-http'

// VMSS extended parameters
@description('Admin username for VMSS instances')
param adminUsername string = 'azureuser'
@secure()
@description('SSH public key (必須: パスワードログインを廃止)')
param adminPublicKey string

// APIM parameters
@description('API Management service name')
param apimName string = 'apim-web'
@description('APIM publisher email')
param apimPublisherEmail string = 'admin@example.com'
@description('APIM publisher name')
param apimPublisherName string = 'admin'

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

// Network & App Gateway stack
module network 'modules/network.bicep' = {
  name: 'networkModule'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ rg ]
  params: {
    location: location
    vnetName: vnetName
    appGatewaySubnetName: appGatewaySubnetName
    backendSubnetName: backendSubnetName
    backendNsgName: backendNsgName
    publicIpName: publicIpName
    appGatewayName: appGatewayName
    backendPoolName: backendPoolName
    httpSettingsName: httpSettingsName
    probeName: probeName
  }
}

// VMSS (Application Gateway backend pool に参加)
module vmss 'modules/vmss.bicep' = {
  name: 'vmssModule'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    vmssName: vmssName
  adminUsername: adminUsername
  adminPublicKey: adminPublicKey
    subnetId: network.outputs.backendSubnetId
    appGatewayBackendPoolId: network.outputs.appGatewayBackendPoolId
  tags: commonTags
  }
}

// API Management (placeholder minimal)
module apim 'modules/apim.bicep' = {
  name: 'apimModule'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ rg ]
  params: {
    location: location
    apimName: apimName
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
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
  scheduleAnchorDate: scheduleAnchorDate
  }
}

// VMSS への Contributor 付与 (旧スクリプト assign-role-to-vmss.ps1 自動化)
module vmssRoleAssign 'modules/roleAssignments.bicep' = {
  name: 'vmssRoleAssignmentModule'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [ vmss ]
  params: {
    automationPrincipalId: automation.outputs.automationAccountPrincipalId
    vmssName: vmssName
  }
}

output automationAccountId string = automation.outputs.automationAccountId
output automationPrincipalId string = automation.outputs.automationAccountPrincipalId
// Legacy placeholder output removed; provide real resource outputs
output vnetId string = network.outputs.vnetId
output appGatewayId string = network.outputs.appGatewayId
output appGatewayBackendPoolId string = network.outputs.appGatewayBackendPoolId
output vmssId string = vmss.outputs.vmssId
output apimId string = apim.outputs.apimId
output deployedRunbooks string = runbooks.outputs.startRunbookDeployed
output deployedSchedules string = runbooks.outputs.schedules
output deployedJobSchedules string = runbooks.outputs.jobSchedules

