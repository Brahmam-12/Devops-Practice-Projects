@description('Azure region')
param location string = resourceGroup().location

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@secure()
param adminPassword string

@description('Number of VMs in the Availability Set')
param avSetVmCount int = 3

// ─── VNET ─────────────────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'placement-lab-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'lab-subnet'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'placement-lab-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow-icmp'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── AVAILABILITY SET ─────────────────────────────────────────────────────────
// Fault domains = separate racks (power + network)
// Update domains = groups patched separately during planned maintenance

resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-07-01' = {
  name: 'ha-availability-set'
  location: location
  sku: { name: 'Aligned' }
  properties: {
    platformFaultDomainCount: 3
    platformUpdateDomainCount: 5
  }
}

// ─── PROXIMITY PLACEMENT GROUP ────────────────────────────────────────────────
// Co-locates VMs in the same data center for low latency (Azure's Cluster PG equivalent)

resource ppg 'Microsoft.Compute/proximityPlacementGroups@2023-07-01' = {
  name: 'low-latency-ppg'
  location: location
  properties: {
    proximityPlacementGroupType: 'Standard'
  }
}

// ─── VMs IN AVAILABILITY SET ─────────────────────────────────────────────────

resource avSetNics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for i in range(0, avSetVmCount): {
  name: 'avset-vm-${i + 1}-nic'
  location: location
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'lab-subnet')
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource avSetVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for i in range(0, avSetVmCount): {
  name: 'avset-vm-${i + 1}'
  location: location
  properties: {
    availabilitySet: { id: availabilitySet.id }
    hardwareProfile: { vmSize: 'Standard_B1s' }
    osProfile: {
      computerName: 'avset-vm-${i + 1}'
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
      networkInterfaces: [{ id: avSetNics[i].id }]
    }
  }
}]

// ─── VMs IN PROXIMITY PLACEMENT GROUP ────────────────────────────────────────

resource ppgNics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for i in range(0, 3): {
  name: 'ppg-vm-${i + 1}-nic'
  location: location
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'lab-subnet')
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource ppgVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for i in range(0, 3): {
  name: 'ppg-vm-${i + 1}'
  location: location
  properties: {
    proximityPlacementGroup: { id: ppg.id }
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: 'ppg-vm-${i + 1}'
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
      networkInterfaces: [{ id: ppgNics[i].id }]
    }
  }
}]

// ─── ZONE-REDUNDANT VMs (Best practice for HA) ────────────────────────────────

resource zoneNics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for i in range(0, 3): {
  name: 'zone-vm-${i + 1}-nic'
  location: location
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'lab-subnet')
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource zoneVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for i in range(0, 3): {
  name: 'zone-vm-${i + 1}'
  location: location
  zones: [string(i + 1)]
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: 'zone-vm-${i + 1}'
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
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: zoneNics[i].id }]
    }
  }
}]

// ─── OUTPUTS ─────────────────────────────────────────────────────────────────

output availabilitySetId string = availabilitySet.id
output proximityPlacementGroupId string = ppg.id
output avSetVmNames array = [for i in range(0, avSetVmCount): 'avset-vm-${i + 1}']
output ppgVmNames array = ['ppg-vm-1', 'ppg-vm-2', 'ppg-vm-3']
output zoneVmNames array = ['zone-vm-1', 'zone-vm-2', 'zone-vm-3']
