@description('Azure region')
param location string = resourceGroup().location

@description('Project name prefix')
param projectName string = 'ha-app'

@description('Admin username')
param adminUsername string = 'azureuser'

@secure()
param adminPassword string

@description('Initial VM count in scale set')
param instanceCount int = 2

@description('Min instance count for autoscale')
param minCount int = 2

@description('Max instance count for autoscale')
param maxCount int = 6

// ─── VNET ────────────────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${projectName}-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'lb-subnet'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
      {
        name: 'app-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { id: appNsg.id }
        }
      }
    ]
  }
}

resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${projectName}-nsg'
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
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── LOAD BALANCER ───────────────────────────────────────────────────────────

resource lbPip 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: '${projectName}-lb-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
  zones: ['1', '2', '3']
}

resource lb 'Microsoft.Network/loadBalancers@2023-05-01' = {
  name: '${projectName}-lb'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend'
        zones: ['1', '2', '3']
        properties: { publicIPAddress: { id: lbPip.id } }
      }
    ]
    backendAddressPools: [{ name: 'backend-pool' }]
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
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${projectName}-lb', 'backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${projectName}-lb', 'http-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// ─── VIRTUAL MACHINE SCALE SET ───────────────────────────────────────────────

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-07-01' = {
  name: '${projectName}-vmss'
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Standard'
    capacity: instanceCount
  }
  zones: ['1', '2']
  properties: {
    overprovision: true
    upgradePolicy: { mode: 'Rolling' }
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'haapp'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: base64('''
          #cloud-config
          packages:
            - nginx
          runcmd:
            - systemctl start nginx
            - systemctl enable nginx
            - echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
        ''')
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
        networkInterfaceConfigurations: [
          {
            name: 'nic-config'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig'
                  properties: {
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'app-subnet')
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lb.name, 'backend-pool')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ─── AUTOSCALE SETTINGS ──────────────────────────────────────────────────────

resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${projectName}-autoscale'
  location: location
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'default-profile'
        capacity: {
          minimum: string(minCount)
          maximum: string(maxCount)
          default: string(instanceCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '2'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

// ─── OUTPUTS ─────────────────────────────────────────────────────────────────

output lbPublicIp string = lbPip.properties.ipAddress
output vmssName string = vmss.name
output backendPoolId string = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lb.name, 'backend-pool')
