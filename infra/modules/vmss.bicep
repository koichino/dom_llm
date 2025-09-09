@description('Deploy VM Scale Set and join to Application Gateway backend pool via backend subnet. Cloud-init installs simple Python HTTP server.')
param location string
param vmssName string = 'vmss-web'
param adminUsername string = 'azureuser'
@secure()
@description('SSH public key (must be provided; password auth disabled)')
param adminPublicKey string
param subnetId string
param appGatewayBackendPoolId string
param instanceCount int = 2
param vmSku string = 'Standard_B1ms'
param upgradePolicyMode string = 'Automatic'
@description('Overprovision VMs for faster scaling (true default)')
param overprovision bool = true
@description('Single placement group (true for <=100 instances)')
param singlePlacementGroup bool = true
@description('Platform fault domain count (optional, leave -1 to omit)')
param platformFaultDomainCount int = -1
param linuxImagePublisher string = 'Canonical'
param linuxImageOffer string = '0001-com-ubuntu-server-jammy'
param linuxImageSku string = '22_04-lts-gen2'
param linuxImageVersion string = 'latest'
@description('OS disk size in GB (set 0 to omit)')
param osDiskSizeGB int = 30
@description('OS disk storage account type')
param osDiskStorageAccountType string = 'Standard_LRS'
@description('Enable Trusted Launch security profile (secure boot + vTPM)')
param enableTrustedLaunch bool = true
@description('Provision VM Agent')
param provisionVMAgent bool = true
@description('Optional tags to apply to the VM Scale Set')
param tags object = {}

// Externalized cloud-init user data (keep lightweight here)
var cloudInit = loadTextContent('../cloudinit/cloud-init.yaml')

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-11-01' = {
  name: vmssName
  location: location
  tags: tags
  sku: {
    name: vmSku
    capacity: instanceCount
    tier: 'Standard'
  }
  properties: {
    upgradePolicy: {
      mode: upgradePolicyMode
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: take(replace(vmssName, '-', ''), 9)
        adminUsername: adminUsername
        customData: base64(cloudInit)
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminPublicKey
              }
            ]
          }
          provisionVMAgent: provisionVMAgent
        }
        allowExtensionOperations: true
      }
      storageProfile: {
        imageReference: {
          publisher: linuxImagePublisher
          offer: linuxImageOffer
          sku: linuxImageSku
          version: linuxImageVersion
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: osDiskStorageAccountType
          }
          osType: 'Linux'
          diskSizeGB: osDiskSizeGB == 0 ? null : osDiskSizeGB
        }
        diskControllerType: 'SCSI'
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: '${vmssName}-ipconfig'
                  properties: {
                    subnet: {
                      id: subnetId
                    }
                    applicationGatewayBackendAddressPools: [
                      {
                        id: appGatewayBackendPoolId
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      securityProfile: enableTrustedLaunch ? {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      } : null
    }
    orchestrationMode: 'Uniform'
    overprovision: overprovision
    singlePlacementGroup: singlePlacementGroup
    doNotRunExtensionsOnOverprovisionedVMs: false
    platformFaultDomainCount: platformFaultDomainCount == -1 ? null : platformFaultDomainCount
  }
}

output vmssId string = vmss.id
output vmssNameOut string = vmss.name
