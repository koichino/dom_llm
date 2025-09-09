@description('Deploys networking components: VNet, subnets, NSG + rule, Public IP, Application Gateway (Standard_v2).\nApplication Gateway structure aligned closely with exported template while omitting read-only id properties.')
param location string
param vnetName string = 'vnet-web'
param addressSpace string = '10.10.0.0/16'
@description('Subnet for Application Gateway (dedicated)')
param appGatewaySubnetName string = 'appGatewaySubnet'
param appGatewaySubnetPrefix string = '10.10.0.0/24'
@description('Subnet for backend VMSS')
param backendSubnetName string = 'backendSubnet'
param backendSubnetPrefix string = '10.10.1.0/24'
@description('NSG name for backend subnet')
param backendNsgName string = 'nsg-backend'
@description('Public IP name for App Gateway')
param publicIpName string = 'agw-pip'
@description('Application Gateway name')
param appGatewayName string = 'agw-web'
@description('Backend address pool name (VMSS pool)')
param backendPoolName string = 'vmssPool'
@description('HTTP settings name')
param httpSettingsName string = 'appGatewayBackendHttpSettings'
@description('Probe name')
param probeName string = 'probe-http'
@description('Listener / Rule priority (100)')
param rulePriority int = 100
@description('Request routing rule name')
param ruleName string = 'rule1'
@description('Frontend port (HTTP)')
param frontendPort int = 80
@description('Probe path')
param probePath string = '/index.txt'
@description('Probe interval seconds')
param probeInterval int = 30
@description('Probe timeout seconds')
param probeTimeout int = 30
@description('Probe unhealthy threshold')
param probeUnhealthyThreshold int = 3
@description('App Gateway instance capacity (Standard_v2)')
param appGatewayCapacity int = 2

// VNet
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ addressSpace ]
    }
    subnets: [
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: appGatewaySubnetPrefix
        }
      }
      {
        name: backendSubnetName
        properties: {
          addressPrefix: backendSubnetPrefix
          networkSecurityGroup: {
            id: backendNsg.id
          }
        }
      }
    ]
  }
}

// Backend NSG
resource backendNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: backendNsgName
  location: location
  properties: {}
}

// Allow VNet inbound HTTP
resource backendNsgRuleAllowVnetHttp 'Microsoft.Network/networkSecurityGroups/securityRules@2023-09-01' = {
  name: 'allow-vnet-http'
  parent: backendNsg
  properties: {
    priority: 200
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    destinationPortRange: '80'
  }
}

// Public IP for Application Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Application Gateway (aligned with exported structure; id fields omitted)
resource appGateway 'Microsoft.Network/applicationGateways@2024-07-01' = {
  name: appGatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      family: 'Generation_1'
      capacity: appGatewayCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, appGatewaySubnetName)
          }
        }
      }
    ]
    sslCertificates: []
    trustedRootCertificates: []
    trustedClientCertificates: []
    sslProfiles: []
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort'
        properties: {
          port: frontendPort
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'appGatewayBackendPool'
        properties: {
          backendAddresses: []
        }
      }
      {
        name: backendPoolName
        properties: {
          backendAddresses: []
        }
      }
    ]
    loadDistributionPolicies: []
    backendHttpSettingsCollection: [
      {
        name: httpSettingsName
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          connectionDraining: {
            enabled: false
            drainTimeoutInSec: 1
          }
          pickHostNameFromBackendAddress: false
          requestTimeout: 60
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, probeName)
          }
        }
      }
    ]
    backendSettingsCollection: []
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'appGatewayFrontendPort')
          }
          protocol: 'Http'
          hostNames: []
          requireServerNameIndication: false
        }
      }
    ]
    listeners: []
    urlPathMaps: []
    requestRoutingRules: [
      {
        name: ruleName
        properties: {
          ruleType: 'Basic'
          priority: rulePriority
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, backendPoolName)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, httpSettingsName)
          }
        }
      }
    ]
    routingRules: []
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Http'
          host: '127.0.0.1'
          path: probePath
          interval: probeInterval
          timeout: probeTimeout
          unhealthyThreshold: probeUnhealthyThreshold
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: {
            statusCodes: [ '200-399' ]
          }
        }
      }
    ]
    rewriteRuleSets: []
    redirectConfigurations: []
    privateLinkConfigurations: []
    enableHttp2: false
  }
  dependsOn: [ backendNsgRuleAllowVnetHttp ]
}

output vnetId string = vnet.id
output backendSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, backendSubnetName)
output appGatewayBackendPoolId string = resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGateway.name, backendPoolName)
output appGatewayId string = appGateway.id
output appGatewayNameOut string = appGateway.name
output publicIpId string = publicIp.id
