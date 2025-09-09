@description('Placeholder for API Management (APIM) instance - minimal consumption SKU for future integration with backend.')
param location string
param apimName string = 'apim-web'
param publisherEmail string = 'admin@example.com'
param publisherName string = 'admin'
param skuName string = 'Consumption'

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: skuName
    capacity: 0
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

output apimNameOut string = apim.name
output apimId string = apim.id
