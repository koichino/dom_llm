@description('Placeholder VMSS module - extend with SKU, image, and networking when needed')
param name string
param location string = resourceGroup().location

// Minimal placeholder resource so module has an output
var message = 'VMSS module placeholder for ${name}'
output placeholderMessage string = message
