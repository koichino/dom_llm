# Sample Runbook script (PowerShell)
# This runbook writes a timestamped message to the job output and can be extended to perform management tasks.

param(
    [string] $Message = "Hello from Runbook"
)

Write-Output "Runbook started at: $(Get-Date -Format o)"
Write-Output "Message: $Message"

# Example: interact with Azure resources using Managed Identity or Az modules
# Install-Module Az -Scope CurrentUser -Force -AllowClobber  # not recommended inside automation runbooks; prefer Hybrid Worker with modules preinstalled

# Example operation placeholder
# Write-Output "Would perform resource operations here"

Write-Output "Runbook completed at: $(Get-Date -Format o)"
