@minLength(3)
@maxLength(24)
param storageAccountName string = 'store${uniqueString(resourceGroup().id)}'
param location string = resourceGroup().location
param vmName string 
param adminUsername string
param keyVaultName string
param secretName string
param sqlServerName string 
param sqlAdminLogin string

@secure()
param sqlAdminPwd string


resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'eoanVNET'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'Subnet-1'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg1.id
          }
        }
      }
      {
        name: 'Subnet-2'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg2.id
          }
        }
      }
    ]
  }
}

resource nsg1 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  location: location
  name: 'nsg1'
  properties: {
    securityRules: [
      // Inbound rule allowing traffic on port 1433
      {
        name: 'Allow_SQL_Server_Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      // Outbound rule allowing traffic on port 1433
      {
        name: 'Allow_SQL_Server_Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}
resource nsg2 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  location: location
  name: 'nsg2'
  properties: {
    securityRules: [
      // Inbound rule allowing RDP traffic on port 3389
      {
        name: 'Allow_RDP_Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      // Inbound rule allowing HTTP traffic on port 80
      {
        name: 'Allow_HTTP_Inbound'
        properties: {
          priority: 101
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      // Inbound rule allowing HTTPS traffic on port 443
      {
        name: 'Allow_HTTPS_Inbound'
        properties: {
          priority: 102
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      // Outbound rule allowing traffic on all ports
      {
        name: 'Allow_All_Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource TEGstorage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${vmName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/Subnet-2'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
  }
}



resource virtualMachine 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: '@Microsoft.KeyVault(SecretUri = secretReference.properties.secretUri)'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: 'cd73bfe4-5b3e-458d-928e-7336c99c9707'
        permissions: {
          secrets: ['get']
        }
      }
    ]
  }
}

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion:linuxFxVersion
      alwaysOn: true
      appSettings: [
        {
          name: 'DbConnectionString'
          value: 'Server=tcp:${sqlServer.name}${url},1433;Initial Catalog=${sqlDatabase.name};Persist Security Info=False;User ID=${sqlServer.properties.administratorLogin};Password=${sqlAdminPwd};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
        }
      ]
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2022-11-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPwd
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2022-11-01-preview' = {
  parent:sqlServer
  name: sqlServerName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    
  }
}
