<#
Assign Contributor role on an existing VM Scale Set to the Automation Account's managed identity.

Usage:
./automation/assign-role-to-vmss.ps1 -ResourceGroupName rg-automation-demo -AutomationAccountName demo-aa -VmssName my-vmss

You can also pass a full VMSS resourceId via -VmssResourceId if preferred.
#>
param(
    [Parameter(Mandatory=$true)][string] $ResourceGroupName,
    [Parameter(Mandatory=$true)][string] $AutomationAccountName,
    [Parameter(Mandatory=$false)][string] $VmssName,
    [Parameter(Mandatory=$false)][string] $VmssResourceId
)

if (-not $VmssResourceId) {
    if (-not $VmssName) {
        throw "Either VmssName or VmssResourceId must be provided"
    }
    Write-Output "Resolving VMSS resource id for $VmssName in RG $ResourceGroupName"
    $VmssResourceId = az vmss show --resource-group $ResourceGroupName --name $VmssName --query id -o tsv
    if (-not $VmssResourceId) {
        throw "VMSS $VmssName not found in resource group $ResourceGroupName"
    }
}

Write-Output "Target VMSS resource id: $VmssResourceId"

Write-Output "Retrieving Automation principalId"
$deploymentName = 'infra-deploy'
$principalId = az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query "properties.outputs.automationAccountPrincipalId.value" -o tsv
if (-not $principalId) {
    throw "Could not retrieve automation principalId from deployment outputs. Ensure deployment name is $deploymentName and deployment succeeded."
}

Write-Output "Assigning Contributor role to principal $principalId on scope $VmssResourceId"
try {
    az role assignment create --assignee $principalId --role "Contributor" --scope $VmssResourceId | Out-Null
    Write-Output "Role assignment created (or already exists)."
}
catch {
    Write-Error "Failed to create role assignment: $_"
    throw $_
}

Write-Output "Done"
