@description('Azure region')
param location string = resourceGroup().location

@description('Admin username for test VMs')
param adminUsername string = 'azureuser'

@secure()
param adminPassword string

// ─── THREE VNETS ─────────────────────────────────────────────────────────────

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'hub-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'hub-subnet'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: '10.0.100.0/27' }
      }
    ]
  }
}

resource spokeAVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'spoke-a-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.1.0.0/16'] }
    subnets: [
      {
        name: 'spoke-a-subnet'
        properties: { addressPrefix: '10.1.1.0/24' }
      }
    ]
  }
}

resource spokeBVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'spoke-b-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.2.0.0/16'] }
    subnets: [
      {
        name: 'spoke-b-subnet'
        properties: { addressPrefix: '10.2.1.0/24' }
      }
    ]
  }
}

// ─── VNet PEERINGS ───────────────────────────────────────────────────────────
// Azure peering requires a peering resource in BOTH vnets

// Hub → Spoke-A
resource hubToSpokeA 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: 'hub-to-spoke-a'
  parent: hubVnet
  properties: {
    remoteVirtualNetwork: { id: spokeAVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Spoke-A → Hub
resource spokeAToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: 'spoke-a-to-hub'
  parent: spokeAVnet
  properties: {
    remoteVirtualNetwork: { id: hubVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
  dependsOn: [hubToSpokeA]
}

// Hub → Spoke-B
resource hubToSpokeB 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: 'hub-to-spoke-b'
  parent: hubVnet
  properties: {
    remoteVirtualNetwork: { id: spokeBVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Spoke-B → Hub
resource spokeBToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: 'spoke-b-to-hub'
  parent: spokeBVnet
  properties: {
    remoteVirtualNetwork: { id: hubVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
  dependsOn: [hubToSpokeB]
}

// ─── NSGs ─────────────────────────────────────────────────────────────────────

resource hubNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'hub-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-icmp-from-spokes'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow-ssh'
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
    ]
  }
}

resource spokeNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'spoke-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-icmp-from-hub'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow-ssh-from-hub'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── AZURE BASTION (Hub) ─────────────────────────────────────────────────────

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'hub-bastion-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-05-01' = {
  name: 'hub-bastion'
  location: location
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnet.name, 'AzureBastionSubnet')
          }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

// ─── TEST VMs ─────────────────────────────────────────────────────────────────

var vmConfigs = [
  {
    name: 'hub-vm'
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnet.name, 'hub-subnet')
    nsgId: hubNsg.id
  }
  {
    name: 'spoke-a-vm'
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', spokeAVnet.name, 'spoke-a-subnet')
    nsgId: spokeNsg.id
  }
  {
    name: 'spoke-b-vm'
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', spokeBVnet.name, 'spoke-b-subnet')
    nsgId: spokeNsg.id
  }
]

resource testNics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for vm in vmConfigs: {
  name: '${vm.name}-nic'
  location: location
  properties: {
    networkSecurityGroup: { id: vm.nsgId }
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: { id: vm.subnetId }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource testVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for (vm, i) in vmConfigs: {
  name: vm.name
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_B1s' }
    osProfile: {
      computerName: vm.name
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
      osDisk: { createOption: 'FromImage' }
    }
    networkProfile: {
      networkInterfaces: [{ id: testNics[i].id }]
    }
  }
}]

// ─── OUTPUTS ─────────────────────────────────────────────────────────────────

output hubVnetId string = hubVnet.id
output spokeAVnetId string = spokeAVnet.id
output spokeBVnetId string = spokeBVnet.id
output bastionName string = bastion.name
