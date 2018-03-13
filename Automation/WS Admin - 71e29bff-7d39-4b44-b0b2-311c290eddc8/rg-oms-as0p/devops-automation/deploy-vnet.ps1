 . .\ensure-resource-group.ps1

 #if (!$deploy_vnet_sourced) { $deploy_vnet_sourced = $true
 Write-Output "Sourced 1:" $MyInvocation.InvocationName

 function Deploy-VNet{
	param(
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $secondary

	#Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -category "vnet" -secondary:$secondary 

    $parameters = @{}
    Add-WsTagsToParameters -parameters $parameters -secondary:$secondary -role "VNET"
	$parameters["vnetName"] = $currentContext["environmentCode"]
	$parameters["vnetCidrPrefix"] = Get-VnetCidrPrefix -secondary:$secondary 

	$resourceGroupName = $ctx.GetResourceGroupName("vnet", $secondary)
	Execute-Deployment -templateFile "arm-vnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

#} # end sourcing block