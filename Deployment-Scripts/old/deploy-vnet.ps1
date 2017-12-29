
$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$profileFile = $currentDir + "\Deployment-Scripts\azureprofile.json"

Import-AzureRmContext -Path $profileFile | Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

$subscriptionName = "Visual Studio Enterprise"
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  | Out-Null
Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green

function Deploy-vNet {
	param(
		[string]$environment,
		[string]$facility
	)

	$parameters = @{
		"environment" = $environment
		"facility" = $facility
	}

	$templateFile = $currentDir +"\Deployment-Scripts\arm-vnet-azuredeploy.json"
	$rg = "rg-vnet-ws" + $environment + $facility
	
	New-AzureRmResourceGroupDeployment `
		-Name ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
		-ResourceGroupName $rg `
		-TemplateFile $templateFile `
		-TemplateParameterObject $parameters `
		-Force -Verbose `
		-ErrorVariable errorMessages

	if ($errorMessages) {
		Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
	}
}

Deploy-vNet "pd" "dr"