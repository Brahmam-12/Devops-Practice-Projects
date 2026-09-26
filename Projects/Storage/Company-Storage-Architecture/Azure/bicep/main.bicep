@description('Azure region')
param location string = resourceGroup().location

@description('Globally unique storage account name — lowercase, 3-24 chars')
param storageAccountName string = 'companystorage${uniqueString(resourceGroup().id)}'

@description('VNet name for private endpoints')
param vnetName string = 'company-vnet'

// ─── VNET + SUBNETS ──────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'app-subnet'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
      {
        name: 'pep-subnet'                          // dedicated subnet for private endpoints
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled' // required for private endpoints
        }
      }
    ]
  }
}

// ─── STORAGE ACCOUNT ─────────────────────────────────────────────────────────

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_ZRS' }                    // zone redundant — survives AZ failure
  kind: 'StorageV2'                                 // supports all 4 services
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false                    // no public blob access ever
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    publicNetworkAccess: 'Disabled'                 // private endpoints only
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: { enabled: true }
        file: { enabled: true }
        table: { enabled: true }
        queue: { enabled: true }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ─── BLOB SERVICE — versioning + soft delete ─────────────────────────────────

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: { enabled: true, days: 30 }
    containerDeleteRetentionPolicy: { enabled: true, days: 30 }
  }
}

// ─── BLOB CONTAINERS ─────────────────────────────────────────────────────────

resource containerBuildArtifacts 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'build-artifacts'
  parent: blobService
  properties: { publicAccess: 'None' }
}

resource containerAppLogs 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'app-logs'
  parent: blobService
  properties: { publicAccess: 'None' }
}

resource containerDbBackups 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'db-backups'
  parent: blobService
  properties: { publicAccess: 'None' }
}

resource containerTerraformState 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'terraform-state'
  parent: blobService
  properties: { publicAccess: 'None' }
}

resource containerTemp 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'temp'
  parent: blobService
  properties: { publicAccess: 'None' }
}

// ─── FILE SERVICE + SHARES ───────────────────────────────────────────────────

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    shareDeleteRetentionPolicy: { enabled: true, days: 30 }
  }
}

resource shareDevopsConfigs 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: 'devops-configs'
  parent: fileService
  properties: {
    shareQuota: 10                                  // 10 GiB
    enabledProtocols: 'SMB'
    accessTier: 'TransactionOptimized'
  }
}

resource shareSensitiveData 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: 'sensitive-data'
  parent: fileService
  properties: {
    shareQuota: 5                                   // 5 GiB
    enabledProtocols: 'SMB'
    accessTier: 'TransactionOptimized'
  }
}

// ─── TABLE SERVICE + TABLES ──────────────────────────────────────────────────

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
}

resource tableDeploymentLogs 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  name: 'DeploymentLogs'
  parent: tableService
}

resource tableFeatureFlags 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  name: 'FeatureFlags'
  parent: tableService
}

// ─── QUEUE SERVICE + QUEUES ──────────────────────────────────────────────────

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
}

resource queueDeploymentJobs 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  name: 'deployment-jobs'
  parent: queueService
}

resource queueNotifications 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  name: 'notifications'
  parent: queueService
}

// ─── LIFECYCLE MANAGEMENT POLICY ─────────────────────────────────────────────

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    policy: {
      rules: [
        {
          name: 'build-artifacts-tiering'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'], prefixMatch: ['build-artifacts/'] }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: 30 }
                tierToArchive: { daysAfterModificationGreaterThan: 90 }
                delete: { daysAfterModificationGreaterThan: 365 }
              }
            }
          }
        }
        {
          name: 'app-logs-tiering'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'], prefixMatch: ['app-logs/'] }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: 7 }
                tierToArchive: { daysAfterModificationGreaterThan: 30 }
                delete: { daysAfterModificationGreaterThan: 90 }
              }
            }
          }
        }
        {
          name: 'db-backups-tiering'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'], prefixMatch: ['db-backups/'] }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: 30 }
                tierToArchive: { daysAfterModificationGreaterThan: 90 }
                // intentionally no delete rule — keep backups forever
              }
            }
          }
        }
        {
          name: 'temp-cleanup'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'], prefixMatch: ['temp/'] }
            actions: {
              baseBlob: {
                delete: { daysAfterModificationGreaterThan: 3 }
              }
            }
          }
        }
        {
          name: 'cleanup-old-versions'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'] }
            actions: {
              version: {
                delete: { daysAfterCreationGreaterThan: 30 }
              }
            }
          }
        }
      ]
    }
  }
  dependsOn: [
    containerBuildArtifacts
    containerAppLogs
    containerDbBackups
    containerTemp
  ]
}

// ─── PRIVATE DNS ZONES ───────────────────────────────────────────────────────

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

resource filePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'
}

resource blobDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'blob-dns-vnet-link'
  parent: blobPrivateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource fileDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'file-dns-vnet-link'
  parent: filePrivateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// ─── PRIVATE ENDPOINTS ───────────────────────────────────────────────────────

resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-blob-pep'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/pep-subnet' }
    privateLinkServiceConnections: [
      {
        name: 'blob-plsc'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']                        // blob service endpoint
        }
      }
    ]
  }
}

resource filePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-file-pep'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/pep-subnet' }
    privateLinkServiceConnections: [
      {
        name: 'file-plsc'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['file']                        // file service endpoint
        }
      }
    ]
  }
}

// Link private endpoints to DNS zones
resource blobPepDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  name: 'blob-dns-group'
  parent: blobPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-config'
        properties: { privateDnsZoneId: blobPrivateDnsZone.id }
      }
    ]
  }
}

resource filePepDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  name: 'file-dns-group'
  parent: filePrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'file-config'
        properties: { privateDnsZoneId: filePrivateDnsZone.id }
      }
    ]
  }
}

// ─── OUTPUTS ─────────────────────────────────────────────────────────────────

output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output fileEndpoint string = storageAccount.properties.primaryEndpoints.file
output blobPrivateIp string = blobPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
output filePrivateIp string = filePrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
