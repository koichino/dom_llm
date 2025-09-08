# Infra (Bicep) + Runbook sample

This repository contains a modular Bicep layout for Azure infrastructure, starting with an Automation Account and a placeholder VMSS module. It also includes a sample PowerShell Runbook script.

Structure
- infra/main.bicep - root Bicep file that composes modules
- infra/modules/automationAccount.bicep - module to create Automation Account
- infra/modules/vmss.bicep - placeholder VMSS module
- runbook.ps1 - sample runbook script to upload to Automation

Quick deploy (local, PowerShell)
1. Login and set subscription

```powershell
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

2. Create resource group

```powershell
az group create --name rg-automation-demo --location eastus
```

3. Deploy Bicep

```powershell
az deployment group create --resource-group rg-automation-demo --template-file infra/main.bicep --parameters prefix=demo
```

4. Create and publish Runbook (example)

```powershell
$rg = 'rg-automation-demo'
$aa = 'demo-aa'
$runbook = 'rb-demo-script'

az automation runbook create --resource-group $rg --automation-account-name $aa --name $runbook --type PowerShell --description 'Sample runbook'
$scriptContent = Get-Content -Raw -Path runbook.ps1
az automation runbook draft replace-content --resource-group $rg --automation-account-name $aa --runbook-name $runbook --content "$scriptContent"
az automation runbook publish --resource-group $rg --automation-account-name $aa --name $runbook
```

CI/CD notes
- Use GitHub Actions with the `azure/login` action and OIDC when possible.
- Keep secrets/credentials in Key Vault and use managed identities for runtime access.

Security & best practices
- Prefer managed identities for runbook access to other Azure resources.
- Pin API versions in Bicep modules and keep modules small and testable.

Deploy (Bicep -> verify identity & role -> upload Runbooks)
-----------------------------------------------

The commands below are PowerShell-ready and assume you are in the repository root. Replace values where noted.

1) Login, set subscription and variables

```powershell
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>

$rg = 'rg-automation-demo'
$location = 'eastus'
$prefix = 'demo'
$deploymentName = 'infra-deploy'
$automationAccountName = "${prefix}-aa"
$vmssName = "${prefix}-vmss"
$startRunbook = 'rb-start-vmss'
$stopRunbook = 'rb-stop-vmss'
```

2) Create resource group and deploy the Bicep (root: `infra/main.bicep`)

```powershell
az group create --name $rg --location $location

az deployment group create --name $deploymentName --resource-group $rg --template-file infra/main.bicep --parameters prefix=$prefix automationAccountName=$automationAccountName vmssName=$vmssName resourceGroupName=$rg -o table
```

3) Verify Automation Account identity and role assignment

Get the principalId that was output by the deployment and list role assignments for it:

```powershell
$principalId = az deployment group show --resource-group $rg --name $deploymentName --query "properties.outputs.automationAccountPrincipalId.value" -o tsv
Write-Output "Automation principalId: $principalId"

az role assignment list --assignee $principalId --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg" -o table
```

If the role assignment does not appear immediately it may take a short time to propagate. You can retry the previous command or check in the portal.

4) Upload and publish Runbooks

This example uses PowerShell to read runbook files from `runbooks/` and upload them to the Automation Account (creates the runbook if missing, replaces draft content and publishes):

```powershell
# Start Runbook
az automation runbook create --resource-group $rg --automation-account-name $automationAccountName --name $startRunbook --type PowerShell --description 'Start VMSS runbook' 2>$null || Write-Output "Runbook may already exist"
$script = Get-Content -Raw -Path runbooks/runbook-start-vmss.ps1
az automation runbook draft replace-content --resource-group $rg --automation-account-name $automationAccountName --runbook-name $startRunbook --content "$script"
az automation runbook publish --resource-group $rg --automation-account-name $automationAccountName --name $startRunbook

# Stop Runbook
az automation runbook create --resource-group $rg --automation-account-name $automationAccountName --name $stopRunbook --type PowerShell --description 'Stop VMSS runbook' 2>$null || Write-Output "Runbook may already exist"
$script = Get-Content -Raw -Path runbooks/runbook-stop-vmss.ps1
az automation runbook draft replace-content --resource-group $rg --automation-account-name $automationAccountName --runbook-name $stopRunbook --content "$script"
az automation runbook publish --resource-group $rg --automation-account-name $automationAccountName --name $stopRunbook
```

5) (Optional) Create schedules and link runbooks

```powershell
.
# Use the included helper to create schedules and link runbooks (this uses az REST to set Mon-Fri recurrence)
.
.
.
./automation/setup-schedules.ps1 -ResourceGroupName $rg -AutomationAccountName $automationAccountName -StartRunbookName $startRunbook -StopRunbookName $stopRunbook -TimeZone 'UTC'
```

Notes
- Ensure the Az modules required by the runbooks are installed into the Automation Account (Modules blade) or use Hybrid Worker with modules preinstalled.
- Use Managed Identity and least-privilege role assignments for production.

Assigning role to an existing VMSS
----------------------------------
If you want the Automation Account to manage a specific existing VM Scale Set, grant the Automation Account's managed identity the Contributor role on that VMSS resource (least privilege for this scenario).

Usage (example):

```powershell
# Assign Contributor on the VMSS named 'my-vmss' in the resource group
./automation/assign-role-to-vmss.ps1 -ResourceGroupName $rg -AutomationAccountName $automationAccountName -VmssName 'my-vmss'
```

The helper will resolve the VMSS resource id and create a role assignment for the Automation principal created by the deployment. If you prefer, pass a full resource id with `-VmssResourceId`.

