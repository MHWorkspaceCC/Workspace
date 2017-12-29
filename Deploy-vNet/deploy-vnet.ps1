#
# deploy.ps1
#
$resourceGroupName = 'rg-vnet-ws-pdpr'
$location = "westus"

$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$profileFile = $currentDir + "\Deploy-Common\azureprofile.json"
$templateFile = $currentDir + '\Deploy-vNet\vnet-azuredeploy.json'
$templateParametersFile = $currentDir + '\Deploy-VNet\vnet-azuredeploy.parameters.json'

Import-AzureRmContext -Path $profileFile | Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

$subscriptionName = "Visual Studio Enterprise"
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  | Out-Null
Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green

$rg = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue

if ($rg -eq $null)
{
	Write-Host "Resource group did not exist.  Creating..."
	New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
}

New-AzureRmResourceGroupDeployment `
	-Name ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile $templateFile `
    -TemplateParameterFile $templateParametersFile `
    -Force -Verbose `
    -ErrorVariable errorMessages

if ($errorMessages) {
    Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
}
