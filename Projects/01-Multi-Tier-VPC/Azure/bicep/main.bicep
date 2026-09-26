@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Project name prefix')
param projectName string = 'multi-tier'

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@secure()
@description('Admin password for VMs')
param adminPassword string

// ─── VIRTUAL NETWORK ────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${projectName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'public-subnet-1'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
      {
        name: 'public-subnet-2'
        properties: { addressPrefix: '10.0.2.0/24' }
      }
      {
        name: 'app-subnet-1'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: { id: appNsg.id }
        }
      }
      {
        name: 'app-subnet-2'
        properties: {
          addressPrefix: '10.0.4.0/24'
          networkSecurityGroup: { id: appNsg.id }
        }
      }
      {
        name: 'db-subnet-1'
        properties: {
          addressPrefix: '10.0.5.0/24'
          networkSecurityGroup: { id: dbNsg.id }
        }
      }
      {
        name: 'db-subnet-2'
        properties: {
          addressPrefix: '10.0.6.0/24'
          networkSecurityGroup: { id: dbNsg.id }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: '10.0.100.0/27' }
      }
    ]
  }
}

// ─── NETWORK SECURITY GROUPS ─────────────────────────────────────────────────

resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${projectName}-app-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-http-from-lb'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow-ssh-from-bastion'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.100.0/27'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
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

resource dbNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${projectName}-db-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-mysql-from-app'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: '10.0.3.0/23'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
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

// ─── AZURE BASTION ───────────────────────────────────────────────────────────

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: '${projectName}-bastion-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-05-01' = {
  name: '${projectName}-bastion'
  location: location
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'AzureBastionSubnet')
          }
          publicIPAddress: { id: bastionPublicIp.id }
        }
      }
    ]
  }
}

// ─── LOAD BALANCER ───────────────────────────────────────────────────────────

resource lbPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: '${projectName}-lb-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource lb 'Microsoft.Network/loadBalancers@2023-05-01' = {
  name: '${projectName}-lb'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend'
        properties: { publicIPAddress: { id: lbPublicIp.id } }
      }
    ]
    backendAddressPools: [
      { name: 'app-backend-pool' }
    ]
    probes: [
      {
        name: 'http-probe'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${projectName}-lb', 'frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${projectName}-lb', 'app-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${projectName}-lb', 'http-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// ─── APP VMs ─────────────────────────────────────────────────────────────────

var vmSubnets = [
  resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'app-subnet-1')
  resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'app-subnet-2')
]

resource appNics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for i in range(0, 2): {
  name: '${projectName}-app-nic-${i + 1}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: { id: vmSubnets[i] }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lb.name, 'app-backend-pool') }
          ]
        }
      }
    ]
  }
}]

resource appVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for i in range(0, 2): {
  name: '${projectName}-app-vm-${i + 1}'
  location: location
  zones: [string(i + 1)]
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: '${projectName}-app-${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: appNics[i].id }]
    }
  }
}]

// ─── OUTPUTS ─────────────────────────────────────────────────────────────────

output lbPublicIpAddress string = lbPublicIp.properties.ipAddress
output vnetId string = vnet.id
output bastionName string = bastion.name
