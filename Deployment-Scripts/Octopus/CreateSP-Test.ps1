#
# CreateSP.ps1
#
# Obviously, replace the following with your own values
$subscriptionId = "3f7acc9e-d55d-4463-a7a8-cd8d9b01de40"
$tenantId = "3bca58b4-fcf2-4e3e-aca9-bc95ec08ae47"
$password = ConvertTo-SecureString  "octopusdeploy" -AsPlainText -Force

# Login to your Azure Subscription
Login-AzureRMAccount
Set-AzureRMContext -SubscriptionId $subscriptionId -TenantId $tenantId

# Create an Octopus Deploy Application in Active Directory
Write-Output "Creating AAD application..."
$azureAdApplication = New-AzureRmADApplication -DisplayName "Octopus Deploy WS Test" -HomePage "http:/workspace.cc" -IdentifierUris "http://octodeploy.workspace.cc" -Password $password
$azureAdApplication | Format-Table

# Create the Service Principal
Write-Output "Creating AAD service principal..."
$servicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $azureAdApplication.ApplicationId
$servicePrincipal | Format-Table

# Sleep, to Ensure the Service Principal is Actually Created
Write-Output "Sleeping for 10s to give the service principal a chance to finish creating..."
Start-Sleep -s 30
 
# Assign the Service Principal the Contributor Role to the Subscription.
# Roles can be Granted at the Resource Group Level if Desired.
Write-Output "Assigning the Contributor role to the service principal..."
New-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $azureAdApplication.ApplicationId

# The Application ID (aka Client ID) will be Required When Creating the Account in Octopus Deploy
Write-Output "Client ID: $($azureAdApplication.ApplicationId)"