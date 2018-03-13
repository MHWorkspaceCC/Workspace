 . .\source-all.ps1

 #if (!$ensure_resource_group_sourced) { $ensure_resource_group_sourced = $true
 #Write-Verbose "Sourced: " $MyInvocation.InvocationName

 Write-Output "Sourced 0:" $MyInvocation.InvocationName

 function Ensure-ResourceGroup{
	param(
		[Parameter(Mandatory=$true)]
		[string]$category,
		[switch]$secondary
	)

	Write-Output "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $category

	#Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName($category, $secondary)
	$location = $ctx.GetLocation($secondary)

	Write-Host "Checking existence of resource group: " $resourceGroupName
	$rg = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue
	if ($rg -eq $null)
	{
		Write-Host "Resource group did not exist.  Creating..."
		New-AzureRmResourceGroup -Name $resourceGroupName -Location $location | Out-Null
		Write-Host "Created " $resourceGroupName "in" $location
	}
	else
	{
		Write-Host $resourceGroupName "already exists"
	}

	Write-Output "Out: " $MyInvocation.MyCommand 
}

#} #end sourced