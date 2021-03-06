$currentDir = "d:\Workspace\workspace"

$facilitiesLocationMap = @{
	"p" = "westus"
	"d" = "eastus"
}

$resourceCategories = @(
	"web"
	"ftp"
	"jump"
	"admin"
	"db"
	"svc"
	"pips"
	"nsgs"
	"vnet"
	)

Class EnvironmentAndFacilitiesInfo{
	static $environmentsInfo = @{
		"validCodes" = "pdtsqc"
		"codeNameMap" = @{
			p = "Production"
			d = "Development"
			t = "Test"
			s = "Staging"
			q = "QA"
			c = "Common"
		}
		"cidrValues" = @{
			p = 0
			d = 1 
			t = 2
			s = 3
			q = 4
			c = 5
		}
	}

	static $facilitiesInfo = @{
		"validCodes" = "pd"
		"codeNameMap" = @{
			p = "Primary"
			d = "Disaster Recovery"
		}
		"cidrValues" = @{
			p = 0 
			d = 1 
		}
		"locationMap" = @{
			p = "westus"
			d = "eastus"
		}
		"peerFacilityMap" = @{
			"p" = "d"
			"d" = "p"
		}
	}

	static [string] CalculateVnetCidrPrefix($envCode, $slot, $facCode){
		$cidr1 = [EnvironmentAndFacilitiesInfo]::environmentsInfo['cidrValues'][$envCode] 
		$cidr2 = [int]$slot
		$cidr3 = [EnvironmentAndFacilitiesInfo]::facilitiesInfo['cidrValues'][$facCode]
		$cidrValue = ($cidr1 -shl 5) + ($cidr2 -shl 2) + $cidr3

		return "10." + ("{0}" -f $cidrValue) + "."
	}

	static [string] GetFacilityLocation($facility){
		return [EnvironmentAndFacilitiesInfo]::facilitiesInfo['locationMap'][$facility]
	}

	static [string]GetPeerfacility($facility){
		return [EnvironmentAndFacilitiesInfo]::facilitiesInfo['peerFacilityMap'][$facility]
	}
}

$wsAcctInfo = @{
	"profileFile" = "workspacecc.json"
	"subscriptions" = @{
		"a" = @{
			"subscriptionName" = "WS Admin"
			"subscriptionID" = "71e29bff-7d39-4b44-b0b2-311c290eddc8"
		}
		"t" = @{
			"subscriptionName" = "WS Test"
			"subscriptionID" = "3f7acc9e-d55d-4463-a7a8-cd8d9b01de40"
		}
		"d" = @{
			"subscriptionName" = "WS Dev"
			"subscriptionID" = "8cc982bb-0877-4c51-aa28-6325a012e486"
		}
		"s" = @{
			"subscriptionName" = "WS Data - Platform"
			"subscriptionID" = "687dd9cb-d46c-4dcc-abd1-6cb3d19ab063"
		}
	}
}

$fileSharesName = "workspace-file-storage"
$fileSharesQuota = 512

Class Context{
	[string]$subscription
	[string]$environment
	[int]$slot
	[string]$facility
	[string]$peerfacility
	[string]$resourcePostfix
	[string]$peerResourcePostfix
	[string]$location
	[string]$peerLocation
	[string]$vnetCidrPrefix
	[string]$peerVnetCidrPrefix
	[object]$azureCtx
	[object]$azureSub
	[object]$previousSub
	[object]$currentAzureContext
	[object]$previousAzureContext
	
	Validate(){
		if ($this.azureCtx -eq $null) { throw "must have an azure context" }
		if ($this.azureSub -eq $null) { throw "must have an azure subscription" }
		if ($this.subscription -eq $null) { throw "subscription cannot be null" }
		if ($this.slot -eq $null) { throw "slot cannot be null" }
		if ($this.facility -eq $null) { throw "facility cannot be null" }
		if ($this.peerfacility -eq $null) { throw "peerfacility cannot be null" }
		if ($this.resourcePostfix -eq $null) { throw "resourcePostfix cannot be null" }
		if ($this.peerResourcePostfix -eq $null) { throw "peerResourcePostfix cannot be null" }
		if ($this.location -eq $null) { throw "location cannot be null" }
		if ($this.peerLocation -eq $null) { throw "peerLocation cannot be null" }
		if ($this.vnetCidrPrefix -eq $null) { throw "vnetCidrPrefix cannot be null" }
		if ($this.peerVnetCidrPrefix -eq $null) { throw "peerVnetCidrPrefix cannot be null" }
	}

	[string] GetResourceGroupName($category, $usePeer=$false){
		if (!$usePeer){ $postfix = $this.resourcePostfix
		}else{ $postfix = $this.peerResourcePostfix }
		return "rg-" + $category + "-" + $postfix
	}

	[string] GetScaleSetName($category, $peer){
		return "vmss-" + $category + $this.GetResourcePostfix($peer)
	}

	[string] GetSharedResourceGroupName($resourceCategory, $usePeer=$false){
		if (!$usePeer){
			$facil = $this.facility
		}
		else{
			$facil = $this.peerfacility
		}
		return "rg-" + $resourceCategory + "-s" + "s0" + $facil
	}

	[string] GetSubscriptionSharedResourceGroupName($resourceCategory, $usePeer=$false){
		if (!$usePeer){
			$facil = $this.facility
		}
		else{
			$facil = $this.peerfacility
		}
		return "rg-" + $resourceCategory + "-" + $this.subscription + "s0" + $facil
	}

	[string] GetDataPlatformSubscriptionResourceGroupName($resourceCategory, $usePeer=$false){
		if (!$usePeer){
			$facil = $this.facility
		}
		else{
			$facil = $this.peerfacility
		}
		return "rg-" + $resourceCategory + "-" + "s" + "s0" + $facil
	}

	[string] GetAdminSubscriptionResourceGroupName($resourceCategory, $usePeer=$false){
		if (!$usePeer){
			$facil = $this.facility
		}
		else{
			$facil = $this.peerfacility
		}
		return "rg-" + $resourceCategory + "-" + "s" + "s0" + $facil
	}

	[string] GetStorageAccountName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.resourcePostfix
		}
		else{
			$postfix = $this.peerResourcePostfix
		}
		return "stg" + $resourceType + $postfix	
	}

	[string] GetFilesStorageAccountName($usePeer=$false){
		# force prod into shared data storage
		if ($this.environment -eq 'p'){
			return "stgfiles" + $this.GetDataPlatformResourcePostfix($usePeer)
		}

		if (!$usePeer){
			$postfix = $this.resourcePostfix
		}
		else{
			$postfix = $this.peerResourcePostfix
		}

		return "stgfiles" + $postfix
	}

	[string] GetFilesResourceGroupName($usePeer=$false){
		# force prod into shared data storage
		if ($this.environment -eq 'p'){
			return "rg-files-" + $this.GetDataPlatformResourcePostfix($usePeer)
		}

		if (!$usePeer){
			$postfix = $this.resourcePostfix
		}
		else{
			$postfix = $this.peerResourcePostfix
		}

		return "rg-files-" + $postfix	
	}

	[string] GetDataPlatformSubscriptionStorageAccountName($resourceType, $usePeer=$false){
		$postfix = $this.GetDataPlatformResourcePostfix($usePeer);
		return "stg" + $resourceType + $postfix
	}

	[string] GetAdminSubscriptionStorageAccountName($resourceType, $usePeer=$false){
		$postfix = $this.GetAdminResourcePostfix($resourceType, $usePeer);
		return "stg" + $resourceType + $postfix
	}

	[string] GetDataPlatformResourcePostfix($usePeer = $false){
		if (!$usePeer){
			$postfix = "ss0p"
		}
		else{
			$postfix = "ss0d"
		}
		return $postfix
		
	}
	
	# note that for now this is the same as the data platform
	[string] GetAdminResourcePostfix($resourceType, $usePeer = $false){
		if (!$usePeer){
			$postfix = "ss0p"
		}
		else{
			$postfix = "ss0d"
		}
		return $postfix
		
	}
	
	[string] GetSharedStorageAccountName($resourceCategory, $usePeer=$false){
		if (!$usePeer){
			$facil = $this.facility
		}
		else{
			$facil = $this.peerfacility
		}
		return "stg" + $resourceCategory + "s" + "s0" + $facil
	}

	[string] GetLocation($usePeer = $false){
		if (!$usePeer){
			return $this.location
		}
		return $this.peerLocation
	}

	[string] GetResourcePostfix($usePeer = $false){
		if (!$usePeer){
			return $this.resourcePostfix
		}
		return $this.peerResourcePostfix
	}

	static [string] BuildResourcePostfix([Context]$ctx, $usePeer){
		if (!$usePeer){
			return $ctx.subscription + $ctx.environment + $ctx.slot + $ctx.facility
		}
		return $ctx.subscription + $ctx.environment + $ctx.slot + $ctx.peerfacility
	}

	[string] GetVnetCidrPrefix($usePeer = $false){
		if (!$usePeer){
			return $this.vnetCidrPrefix
		}
		return $this.peerVnetCidrPrefix
	}

	[string] Getfacility($usePeer = $false){
		if (!$usePeer){
			return $this.facility
		}
		return $this.peerfacility
	}

	[string] GetSharedResourcePostfix($usePeer = $false){
		if (!$usePeer){
			return "s" + "s0" + $this.facility
		}
		return "s" + "s0" + $this.peerfacility
	}

	static [object] GetFacilityUsages($primary, $secondary){
		if (!$primary -and !$secondary){ return @($false, $true) }
		if ($primary -and $secondary){ return @($false, $true) }
		if ($primary -and !$secondary){ return @($false) }
		return @($true)
	}
	
	[string] GetKeyVaultName($usePeer){
		$keyVaultName = "kv-vaults-" + $this.GetResourcePostfix($usePeer)
		return $keyVaultName
	}

	static [Context]newEnvironmentContextFrom($fromCtx, $environment, $slot){
		$ctx = [Context]::new()
		$ctx.azureCtx = $fromCtx.azureCtx
		$ctx.azureSub = $fromCtx.azureSub
		$ctx.environment = $environment
		$ctx.slot = $slot
		$ctx.facility = $fromCtx.facility
		$ctx.peerfacility = [EnvironmentAndFacilitiesInfo]::GetPeerfacility($ctx.facility)
		$ctx.subscription = $fromCtx.subscription
		$ctx.resourcePostfix = [Context]::BuildResourcePostfix($ctx, $false)
		$ctx.peerResourcePostfix = [Context]::BuildResourcePostfix($ctx, $true)
		$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facility)
		$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerfacility)
		$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environment, $ctx.slot, $ctx.facility)
		$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environment, $ctx.slot, $ctx.peerfacility)

		return $ctx
	}

	[HashTable] GetTags($secondary, $role){
		return @{
			"environment" = $this.environment
			"environmentCode" = $this.environment + $this.slot
			"facility" = $this.Getfacility($secondary)
			"instance" = $this.slot.ToString()
			"subscriptionCode" = $this.subscription
			"Role" = $role
			"resourceNamePostfix" = $this.GetResourcePostfix($secondary)
			"location" = $this.GetLocation($secondary)
		}
	}
}

function Login-WorkspaceAzureAccount{
	param(
		[Parameter(Mandatory=$true)]
		[string]$environment,
		[Parameter(Mandatory=$true)]
		[string]$slot,
		[Parameter(Mandatory=$true)]
		[string]$facility,
		[Parameter(Mandatory=$true)]
		[string]$subscription
	)
	Write-Host "In: " $MyInvocation.MyCommand $subscription $environment $slot $facility 

	$profileFile = $currentDir + "\Deployment-Scripts\" + $wsAcctInfo['profileFile']

	Write-Host "Logging into azure account"
	$azureCtx = Import-AzureRmContext -Path $profileFile
	Write-Host "Successfully loaded the profile file: " $profileFile

	Try{
		Write-Host "Setting subscription..."

		$subscriptionInfo = $wsAcctInfo["subscriptions"]
		$theSubscription = $subscriptionInfo[$subscription]

		$azureSub = Get-AzureRmsubscription -SubscriptionId $theSubscription["subscriptionID"] 
		$sub = Select-AzureRmSubscription -SubscriptionObject $azureSub
		$context = Set-AzureRmContext -SubscriptionObject $azureSub
		Write-Host "Set Azure subscription for session complete"
		Write-Host $azureSub.Name $azureSub.subscription

	}
	Catch{
		Write-Host "subscription set failed"
		Write-Host $_
	}

	$ctx = [Context]::new()
	$ctx.azureCtx = $context
	$ctx.azureSub = $azureSub
	$ctx.environment = $environment
	$ctx.slot = $slot
	$ctx.facility = $facility
	$ctx.peerfacility = [EnvironmentAndFacilitiesInfo]::GetPeerfacility($facility)
	$ctx.subscription = $subscription
	$ctx.resourcePostfix = [Context]::BuildResourcePostfix($ctx, $false)
	$ctx.peerResourcePostfix = [Context]::BuildResourcePostfix($ctx, $true)
	$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facility)
	$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerfacility)
	$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environment, $ctx.slot, $ctx.facility)
	$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environment,$ctx.slot, $ctx.peerfacility)

	#Dump-Ctx $ctx
	#$ctx.Validate()

	Write-Host "Out: " $MyInvocation.MyCommand 

	return $ctx
}

function Set-DataPlatformContext{
	param(
		[Context]$ctx
	)

	$subscriptionInfo = $wsAcctInfo["subscriptions"]
	$theSubscription = $subscriptionInfo['s']
	$dataSub = Get-AzureRmsubscription -SubscriptionId $theSubscription["subscriptionID"]
	$context = Select-AzureRmSubscription -SubscriptionId $dataSub.Id
	#$context = Set-AzureRmContext -SubscriptionObject $dataSub
	$ctx.previousAzureContext = $ctx.currentAzureContext
	$ctx.currentAzureContext = $context
	$ctx.previousSub = $ctx.azureSub
	$ctx.azureSub = $dataSub
	Write-Host "Set context to: " + $context.Subscription.Id
}

function Set-AdminContext{
	param(
		[Context]$ctx
	)

	$subscriptionInfo = $wsAcctInfo["subscriptions"]
	$theSubscription = $subscriptionInfo['a']
	$adminSub = Get-AzureRmsubscription -SubscriptionId $theSubscription["subscriptionID"]
	$dataSub = Select-AzureRmSubscription -SubscriptionId $adminSub
	Set-AzureRmContext -SubscriptionObject $adminSub
	$ctx.previousAzureContext = $ctx.currentAzureContext
	$ctx.currentAzureContext = Get-AzureRmContext
	$ctx.previousSub = $ctx.azureSub
	$ctx.azureSub = $adminSub
}

function Revert-Context{
	param(
		[Context]$ctx
	)

	Set-AzureRmContext -SubscriptionObject $ctx.previousSub
	Select-AzureRmSubscription -SubscriptionId $ctx.previousSub.Id
	$ctx.previousAzureContext = $ctx.currentAzureContext
	$ctx.currentAzureContext = Get-AzureRmContext
	$ctx.previousSub = $ctx.azureSub
	$ctx.azureSub = $ctx.previousSub
	$ctx.previousSub = $null
}

function Dump-Ctx{
	param(
		[Parameter(Mandatory=$true)]
		[Context] $ctx
	)
	<#
	Write-Host 'environment:' $ctx.environment
	Write-Host 'environment:' $ctx.environment
	Write-Host 'slot:' $ctx.slot
	Write-Host 'facility:' $ctx.facility
	Write-Host 'peerfacility:' $ctx.peerfacility
	Write-Host 'subscription:' $ctx.subscription
	Write-Host 'location:' $ctx.location
	Write-Host 'peerLocation:' $ctx.peerLocation
	Write-Host 'resourcePostfix:' $ctx.resourcePostfix
	Write-Host 'peerResourcePostfix:' $ctx.peerResourcePostfix
	Write-Host 'sharedPeerResourcePostfix:' $ctx.sharedPeerResourcePostfix
	Write-Host 'sharedResourcePostfix:' $ctx.sharedResourcePostfix
	Write-Host 'vnetCidrPrefix:' $ctx.vnetCidrPrefix
	Write-Host 'peerVnetCidrPrefix:' $ctx.peerVnetCidrPrefix
	#>
}

function Ensure-LoggedIntoAzureAccount {
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx
	)

	if ($ctx -eq $null) { throw "Must have a context" }
	if ($ctx.azureCtx -eq $null -or $ctx.azureSub -eq $null){
		$ctx2 = Login-WorkspaceAzureAccount -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription
		$ctx.azureCtx = $ctx2.azureCtx
		$ctx.azureSub = $ctx2.azureSub
	}
}

function Ensure-ResourceGroup{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[Parameter(Mandatory=$true)]
		[string]$category
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $category

	Ensure-LoggedIntoAzureAccount -ctx $ctx

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

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Ensure-ResourceGroupWithName{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[Parameter(Mandatory=$true)]
		[string]$resourceGroupName,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $resourceGroupName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

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

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Ensure-AllResourceGroups{
	param(
		[Parameter(Mandatory=$true)]
		[string]$facility,
		[Parameter(Mandatory=$true)]
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $environment

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	foreach ($resourceCategory in $resourceCategories){
		$groupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory $resourceCategory
		Ensure-ResourceGroup -facility $facility -groupName $groupName
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Execute-Deployment{
	param(
		[Parameter(Mandatory=$true)]
		[string]$templateFile,
		[Parameter(Mandatory=$true)]
		[string]$resourceGroupName,
		[Parameter(Mandatory=$true)]
		[hashtable]$parameters,
		[switch]$simulate
	)
	Write-Host "In: " $MyInvocation.MyCommand $templateFile $resourceGroupName

	Write-Host "Executing template deployment: " $resourceGroupName $templateFile

	$items = Get-ChildItem -Path $currentDir -Include $templateFile -Recurse
	if ($items -eq $null) { throw "Could not find template: " + $templateFile}
	$fullTemplateFileName = $items[0]
	
	$name = ((Get-ChildItem $fullTemplateFileName).BaseName + '-' + $resourceGroupName + "-" + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))
	Write-Host "Deployment name: " $name

	if (!$simulate){
		$result = New-AzureRmResourceGroupDeployment `
			-Name $name `
			-ResourceGroupName $resourceGroupName `
			-TemplateFile $fullTemplateFileName `
			-TemplateParameterObject $parameters `
			-Force -Verbose `
			-InformationAction Continue `
			-ErrorVariable errorMessages

		if ($errorMessages) {
			$exceptionMessage = 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
			Write-Output $exceptionMessage
			throw $exceptionMessage
		}
	}
	else {
		Write-Host "Skipped deployment because of simulation flag" -ForegroundColor Yellow
	}


	Write-Host "Out: " $MyInvocation.MyCommand 

	return $name
}

function Deploy-StorageAccount{
	param(
		[Parameter(Mandatory=$true)]
		[string]$resourceGroupName,
		[Parameter(Mandatory=$true)]
		[string]$storageAccountName
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $resourceGroupName $storageAccountName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$parameters = @{
		"storageAccountName" = $storageAccountName
	}

	Execute-Deployment -templateFile "arm-stgaccount-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Ensure-StorageAccount{
	param(
		[Context]$ctx,
		[Parameter(Mandatory=$true)]
		[string]$resourceGroupName,
		[Parameter(Mandatory=$true)]
		[string]$storageAccountName
	)

	Write-Host "In: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$account = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue
	if (!$account)
	{
		Write-Host "Storage account did not exist.  Creating..."
		Deploy-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
		Write-Host "Created: " $storageAccountName
	}
	else
	{
		Write-Host $account "Storage account already exists"
	}


	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-VNet{
	param(
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $ctx.facility $secondary

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "vnet"

	$parameters = $ctx.GetTags($secondary, "VNET")
	$parameters["vnetName"] = $ctx.environment + $ctx.slot
	$parameters["vnetCidrPrefix"] = $ctx.GetVnetCidrPrefix($secondary)

	$resourceGroupName = $ctx.GetResourceGroupName("vnet", $secondary)
	Execute-Deployment -templateFile "arm-vnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-VPN{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "vnet"

	$parameters = $ctx.GetTags($false, "VNET")
	$parameters["peerFacility"] = $ctx.peerfacility
	$parameters["peerResourceNamePostfix"] = $ctx.GetResourcePostfix($true)
	$parameters["mainVnetCidrPrefix"] = $ctx.vnetCidrPrefix
	$parameters["peerVnetCidrPrefix"] = $ctx.peerVnetCidrPrefix
	$parameters["peerLocation"] = $ctx.peerLocation
	$parameters["sharedKey"] = "workspacevpn"

	$resourceGroupName = $ctx.GetResourceGroupName("vnet", $false)
	Execute-Deployment -templateFile "arm-vpn-deploy.json" -resourceGroupName $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}
<# old deploy 
function Deploy-DB{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diagnosticStorageAccountKey,
		[string]$installersStgAcctKey,
		[string]$installersStgAcctName,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[string]$saUserName,
		[string]$saPassword,
		[string]$loginUserName,
		[string]$loginPassword,
		[string]$dbBackupsStorageAccountKey

	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey $dbAdminUserName $dbBackupsStorageAccountKey

	Dump-Ctx $ctx

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "db" -secondary:$secondary

	$parameters = $ctx.GetTags($secondary, "DB")
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
	$parameters["dataDogApiKey"] = $dataDogApiKey
	$parameters["adminUserName"] = $adminUserName
	$parameters["adminPassword"] = $adminPassword
	$parameters["installersStgAcctKey"] = $installersStgAcctKey
	$parameters["installersStgAcctName"] = $installersStgAcctName
	$parameters["saUserName"] = $saUserName
	$parameters["saPassword"] = $saPassword
	$parameters["loginUserName"] = $loginUserName
	$parameters["loginPassword"] = $loginPassword
	$parameters["vmSize"] = "Standard_D1_v2"
	$parameters["dbServerName"] = "sql1"
	$parameters["dbBackupsStorageAccountKey"] = $dbBackupsStorageAccountKey
	$parameters["dbBackupsStorageAccountName"] = $ctx.GetSharedStorageAccountName("dbbackups", $secondary)
	$parameters["dbBackupBlobName"] = "AdventureWorks2016.bak"
	$parameters["databaseName"] = "AdventureWorks"
	$parameters["dbMdfFileName"] = "AdventureWorks2016_Data"
	$parameters["dbLdfFileName"] = "AdventureWorks2016_log"

	$resourceGroupName = $ctx.GetResourceGroupName("db", $secondary)
	Execute-Deployment -templateFile "arm-db-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}
#>

function Deploy-Web{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diagnosticStorageAccountName,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[string]$sslCertificateUrl,
		[string]$octoUrl,
		[string]$octoApiKey,
		[string]$fileShareKey,
		[string]$fileStgAcctName,
		[string]$fileShareName,
		[int]$scaleSetCapacity = 2,
		[switch]$dontUseImage,
		[string]$vmSku = "Standard_DS2_v2",
		[switch]$simulate
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "web" -secondary:$secondary

	$parameters = $ctx.GetTags($secondary, "WEB")
	$parameters["diagStorageAccountName"] = $diagnosticStorageAccountName
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
	$parameters["dataDogApiKey"] = $dataDogApiKey
	$parameters["sslCertificateUrl"] = $sslCertificateUrl
	$parameters["sslCertificateStore"] = "MyCerts"
	$parameters["adminUserName"] = $adminUserName
	$parameters["adminPassword"] = $adminPassword
	$parameters["octoUrl"] = $octoUrl
	$parameters["octoApiKey"] = $octoApiKey
	$parameters["fileShareKey"] = $fileShareKey
	$parameters["fileStgAcctName"] = $fileStgAcctName
	$parameters["fileShareName"] = $fileShareName
	$parameters["vmSku"] = $vmSku
	$parameters["scaleSetCapacity"] = $scaleSetCapacity

	Write-Host "-------->" $parameters["vmSku"] $vmSku

	$resourceGroupName = $ctx.GetResourceGroupName("web", $secondary) 

	$templateName = "arm-vmssweb-deploy-from-image.json"
	if ($dontUseImage){ $templateName = "arm-vmssweb-deploy.json" }

	Execute-Deployment -templateFile $templateName -resourceGroup $resourceGroupName -parameters $parameters -simulate:$simulate

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey
}

function Deploy-FTP{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[int]$scaleSetCapacity = 2
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "ftp" -secondary:$secondary

	$parameters = $ctx.GetTags($secondary, "FTP")
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
	$parameters["dataDogApiKey"] = $dataDogApiKey
	$parameters["adminUserName"] = $adminUserName
	$parameters["adminPassword"] = $adminPassword
	$parameters["vmSku"] = "Standard_DS1_v2"
	$parameters["scaleSetCapacity"] = $scaleSetCapacity

	$resourceGroupName = $ctx.GetResourceGroupName("ftp", $secondary) 
	Execute-Deployment -templateFile "arm-vmssftp-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) 
}

function Deploy-Jump{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[string]$installersStgAcctKey,
		[string]$installersStgAcctName 
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "jump" -secondary:$secondary

	$parameters = $ctx.GetTags($secondary, "JUMP")
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
	$parameters["dataDogApiKey"] = $dataDogApiKey
	$parameters["adminUserName"] = $adminUserName
	$parameters["adminPassword"] = $adminPassword
	$parameters["installersStgAcctKey"] = $installersStgAcctKey
	$parameters["installersStgAcctName"] = $installersStgAcctName

	$resourceGroupName = $ctx.GetResourceGroupName("jump", $secondary)
	Execute-Deployment -templateFile "arm-jump-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)
}

function Deploy-Admin{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "admin"

	$parameters = $ctx.GetTags($secondary, "ADMIN")
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
	$parameters["dataDogApiKey"] = $dataDogApiKey
	$parameters["adminUserName"] = $adminUserName
	$parameters["adminPassword"] = $adminPassword

	$resourceGroupName = $ctx.GetResourceGroupName("admin", $secondary)
	Execute-Deployment -templateFile "arm-admin-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-OctoServer{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "svc"

	$parameters = $ctx.GetTags($secondary, "OCTO")

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $secondary)
	Execute-Deployment -templateFile "arm-octoserver-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand  $ctx.GetResourcePostfix($secondary)
}

function Deploy-ServicesVnetEntities{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "svc"

	$parameters = @{
		"vnetCidrPrefix" = $ctx.GetVnetCidrPrefix($secondary)
		"resourceNamePostfix" = $ctx.GetResourcePostfix($secondary)
		"vnetName" = "s0" 
	}
	
	$resourceGroupName = $ctx.GetResourceGroupName("svc", $secondary)
	Execute-Deployment -templateFile "arm-svcvnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}


function Check-IfDiskIsPresent{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diskName
	)

	Ensure-LoggedIntoAzureAccount -ctx $ctx
	$rgn = $ctx.GetResourceGroupName("disks", $secondary)
	Write-Host "Checking existence of:" $diskname $rgn
	$disk = Get-AzureRmDisk -DiskName $diskname -ResourceGroupName $rgn -ErrorAction SilentlyContinue -ErrorVariable err
	if ($err -ne $null) { return $false }
	$result = $disk -ne $null
	Write-Host "Result:" $result
	return $result
}

function Create-Disk{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diskName,
		[int]$sizeInGB,
		[string]$accountType="StandardLRS"
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $sizeInGB $accountType

	Write-Host "Disk name:" $diskName
	$diskconfig = New-AzureRmDiskConfig -Location $ctx.GetLocation($secondary) -DiskSizeGB $sizeInGB -AccountType $accountType -OsType Windows -CreateOption Empty
	New-AzureRmDisk -ResourceGroupName $ctx.GetResourceGroupName("disks", $secondary) -DiskName $diskName -Disk $diskconfig

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Ensure-DiskPresent{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$diskNamePrefix,
		[int]$sizeInGB,
		[string]$accountType="StandardLRS"
	)
	Write-Host "In:  " $MyInvocation.MyCommand  $ctx.GetResourcePostfix($secondary) $diskNamePrefix $sizeInGB $accountType

	Ensure-LoggedIntoAzureAccount -ctx $ctx
	Ensure-ResourceGroup -ctx $ctx -category "disks" -secondary:$secondary

	$diskName = $diskNamePrefix + "-" + $ctx.GetResourcePostfix($secondary)

	$diskPresent = Check-IfDiskIsPresent -ctx $ctx -secondary:$secondary -diskName $diskName
	if (!$diskPresent){
		Write-Host "Disk did not exist - Creating"
		Write-Host $sizeInGB $diskName $accountType

		Create-Disk -ctx $ctx -secondary:$secondary -sizeInGB $sizeInGB -diskName $diskName -accountType $accountType
	}else{
		Write-Host "Found the disk"
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Delete-DiskFromVM{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$vmNamePrefix,
		[string]$diskNamePrefix
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $vmNamePrefix $diskNamePrefix
	
	$diskName = $diskNamePrefix + "-" + $ctx.GetResourcePostfix($secondary)
	$virtualMachineName = $vmNamePrefix + "-" + $ctx.GetResourcePostfix($secondary)
	$vmResourceGroupName = $ctx.GetResourceGroupName("db", $secondary)
	$virtualMachine = Get-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $virtualMachineName

	Write-Host "Attempting to remove disk:" $diskName $virtualMachineName
	Remove-AzureRmVMDataDisk -VM $virtualMachine -Name $diskName
	Write-Host "Updating VM:"$vmResourceGroupName $virtualMachineName
	Update-AzureRmVM -ResourceGroupName $vmResourceGroupName -VM $virtualMachine

	$diskResourceGroupName = $ctx.GetResourceGroupName("disks", $secondary)
	Remove-AzureRmDisk -ResourceGroupName $diskResourceGroupName -DiskName $diskName -Force -InformationAction SilentlyContinue

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Create-KeyVault{
	param(
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "vaults" -secondary:$secondary

	$resourcePostfix = $ctx.GetResourcePostfix($secondary)

	$keyVaultName = "kv-vaults-" + $resourcePostfix

	$resourceGroupName = $ctx.GetResourceGroupName("vaults", $secondary)
	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
	if (!$keyVault)
	{
		Write-Host "Did not find KeyVault, so trying to create..."
		$location = $ctx.GetLocation($secondary)
		$keyVault = New-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -Location $location -EnabledForDeployment
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	return $keyVault
}

function Remove-KeyVault{
	param(
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $secondary)
	$resourcePostfix = $ctx.GetResourcePostfix($secondary)
	$keyVaultName = "kv-svc-" + $resourcePostfix
	$location = $ctx.GetLocation($secondary)

	$keyVault = Remove-AzureRmKeyVault -Force -VaultName $keyVaultName -Location $location -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue -InformationAction Continue

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)
	return $keyVault
}

function Set-KeyVaultSecret{
	param(
		[string]$KeyVaultName,
		[string]$SecretName,
		[string]$SecretValue
	)
	Write-Host "In: " $MyInvocation.MyCommand $KeyVaultName $SecretName

	$secureValue = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
	Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $secureValue 

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName 
}

function Get-KeyVaultSecret{
	param(
		[string]$KeyVaultName,
		[string]$SecretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $KeyVaultName $SecretName
	
	$text = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction Stop).SecretValueText

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName 

	return $text
}

function Get-KeyVaultSecretId{
	param(
		[string]$KeyVaultName,
		[string]$SecretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $KeyVaultName $SecretName
	
	$secret = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction Stop

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName $secret.Id 

	return $Secret.Id
}

function Add-LocalCertificateToKV{
	param(
		[string]$keyVaultName,
		[string]$pfxFile,
		[string]$password,
		[string]$secretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $keyVaultName $certName $pfxFile

	Ensure-LoggedIntoAzureAccount -ctx $ctx
	$pfxFilePath = $currentDir + "\Deployment-Scripts\" + $pfxFile
	$flag = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
	$collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection 
	$collection.Import($pfxFilePath, $password, $flag)
	$pkcs12ContentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12
	$clearBytes = $collection.Export($pkcs12ContentType)
	$fileContentEncoded = [System.Convert]::ToBase64String($clearBytes)
	$secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText -Force
	$secretContentType = 'application/x-pkcs12'

	Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secret -ContentType $secretContentType #-ErrorAction SilentlyContinue -ErrorVariable err
	if ($err){
		Write-Host $err
	}

	Write-Host "Out: " $MyInvocation.MyCommand $keyVaultName $certName $pfxFile
}


function Create-KeyVaultSecrets{
	param(
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$webSslCertificateSecretName = "WebSslCertificate"

	# force this to the west region octo for now
	$postfix = $ctx.GetSharedResourcePostfix($false)
	$region = $ctx.GetLocation($false)
	$octoUrl = "http://pip-octo-as0p.westus.cloudapp.azure.com" 

	$octoApiKey = "API-5TAPS5LFLRT6VV5T90A41XDR0"
	$dataDogApiKey = "01c70cf6720873928c58e2690e81417d"
	$pfxfile = "workspace.pfx"
	$pfxfilePassword = "workspace"

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $secondary)
	$resourcePostfix = $ctx.GetResourcePostfix($secondary)
	$keyVaultName = "kv-vaults-" + $resourcePostfix

	# this has been forced by set secrets getting a DNS error on the KV name after it is created.
	# so, we'll try a few times with a slight delay until it is available
	$kv = $null
	$tries = 0
	$maxTries = 6
	$tryDelayInSeconds = 5
	while (($kv -eq $null) -and ($tries -lt $maxTries)){
		Write-Host "Trying to get key vault" $keyVaultName
		$kv = Get-AzureRmKeyVault -VaultName $keyVaultName
		if (!$kv){
			Write-Host "KV access failed"
			$tries++
			Start-Sleep -Seconds $tryDelayInSeconds
			continue
		}
	}
	if ($tries -eq $maxTries){
		Write-Host "Could not connect to KV"
		throw "Error connecting to key vault"
	}
	Write-Host "Got KV"

	Write-Host "Setting certificate"
	Add-LocalCertificateToKV -keyVaultName $keyVaultName -pfxFile $pfxfile -password $pfxfilePassword -secretName $webSslCertificateSecretName
	
	Write-Host "Setting server passwords"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword" -SecretValue "Workspace!Web!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminPassword" -SecretValue "Workspace!Ftp!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword" -SecretValue "Workspace!DB!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminPassword" -SecretValue "Workspace!Jump!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminPassword" -SecretValue "Workspace!Admin!2018"

	Write-Host "Setting database secrets"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword" -SecretValue "Workspace!DB!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName" -SecretValue "wsapp"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword" -SecretValue "Workspace!DB!2018"
	
	Write-Host "Setting octo and data dog secrets"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoUrl" -SecretValue $octoUrl
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoApiKey" -SecretValue $octoApiKey
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey" -SecretValue $dataDogApiKey

	Write-Host "Getting secrets from data platform subscription"
	Set-DataPlatformContext -ctx $ctx
	$diagAcctResourceGroupName = $ctx.GetDataPlatformSubscriptionResourceGroupName("diag", $secondary)
	$diagStorageAccountName = $ctx.GetDataPlatformSubscriptionStorageAccountName("diag", $secondary)
	$diagStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $diagAcctResourceGroupName -AccountName $diagStorageAccountName

	Write-Host $fileShareAcctResourceGroupName $fileShareStorageAccountName
	$fileShareAcctResourceGroupName = $ctx.GetFilesResourceGroupName($secondary) # $ctx.GetDataPlatformSubscriptionResourceGroupName("files", $secondary)
	$fileShareStorageAccountName = $ctx.GetFilesStorageAccountName($secondary) # $ctx.GetDataPlatformSubscriptionStorageAccountName("files", $secondary)
	$fileShareStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $fileShareAcctResourceGroupName -AccountName $fileShareStorageAccountName

	$dbbackupAcctResourceGroupName = $ctx.GetDataPlatformSubscriptionResourceGroupName("dbbackups", $secondary)
	$dbBackupsStorageAccountName = $ctx.GetDataPlatformSubscriptionStorageAccountName("dbbackups", $secondary)
	$dbBackupsStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $dbbackupAcctResourceGroupName -AccountName $dbBackupsStorageAccountName
	Revert-Context -ctx $ctx
	Write-Host "Done getting secrets from shared subscription"
	
	Write-Host "Setting diagnostics secrets"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey" -SecretValue $diagStgAcctKeys.Value[0]
	Write-Host "Setting file share secrets"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey" -SecretValue $fileShareStgAcctKeys.Value[0]
	Write-Host "Setting database backup secrets"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "dbBackupsStorageAccountKey" -SecretValue $dbBackupsStgAcctKeys.Value[0]

	Write-Host "Getting secrets from data platform subscription"
	Set-AdminContext -ctx $ctx
	$installersAcctResourceGroupName = $ctx.GetAdminSubscriptionResourceGroupName("installers", $secondary)
	$installersStorageAccountName = $ctx.GetAdminSubscriptionStorageAccountName("installers", $secondary)
	$installersStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $installersAcctResourceGroupName -AccountName $installersStorageAccountName
	Revert-Context -ctx $ctx

	Write-Host "Setting installer secrets"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey" -SecretValue $installersStgAcctKeys.Value[0]

	Write-Host "Out: " $MyInvocation.MyCommand 
}


function Build-KeyVault{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	
	Create-KeyVault -ctx $ctx -secondary:$secondary
	Create-KeyVaultSecrets -ctx $ctx -secondary:$secondary
}

function Rebuild-KeyVault{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	
	Remove-KeyVault -ctx $ctx -secondary:$secondary
	Build-KeyVault -ctx $ctx -secondary:$secondary
}

function Wait-ForJobsToComplete{
	param(
		[System.Collections.ArrayList]$jobs
	)

	if ($jobs.Count -eq 0){
		Write-Host "No jobs to wait for"
		return
	}

	Write-Host "Watching the following jobs:" $jobs.Name
	Write-Host "With ids:" $jobs.Id

	while ($true){
		$alldone = $true
		foreach ($job in $jobs){
			if ($job.State -ne [System.Management.Automation.JobState]::Completed -and
				$job.State -ne [System.Management.Automation.JobState]::Failed){
				$alldone = $false
				break
			}
		}

		if ($alldone) { break }

		foreach ($job in $jobs){
			if ($job.HasMoreData){
				$data = Receive-Job $job
				if (![string]::IsNullOrWhiteSpace($data)){
					Write-Host $data
				}
			}
		}

		$msg = ""
		foreach ($job in $jobs){
			$status = $job.Name + " (" + $job.JobStateInfo + ") "
			$msg = $msg + $status`
		}

		Write-Host "Waiting 5 seconds:" $msg 
		Wait-Job -Job $jobs -Timeout 5
	}
	
	Write-Host "Jobs ended" $jobs.Name

	$allNoData = $false
	while (!$allNoData){
		$anyWithData = $false
		foreach ($job in $jobs){
			if ($job.HasMoreData){
				$data = Receive-Job $job
				Write-Host $data
				$anyWithData = $true
			}
		}
		$allNoData = !$anyWithData
	}

	Write-Host "Done waiting for jobs:" $jobs.Name
}

function Start-ScriptJob{
	param(
		[string]$environment, 
		[string]$slot,
		[string]$facility, 
		[string]$subscription, 
		[bool]$usage,
		[string]$category,
		[string]$name,
		[scriptblock]$scriptToRun,
		[string]$vmSku,
		[switch]$simulate,
		[string]$dataDiskNamePrefix,
		[int]$dbDiskSizeInGB,
		[string]$dbDiskType,
		[string]$computerName
	)

	Write-Host "\\\\\\\\=>" $simulate

	$arguments = New-Object System.Collections.ArrayList
	$arguments.Add($ctx.environment) | Out-Null
	$arguments.Add($ctx.slot) | Out-Null
	$arguments.Add($ctx.facility) | Out-Null
	$arguments.Add($ctx.subscription) | Out-Null
	$arguments.Add($usage) | Out-Null
	$arguments.Add($category) | Out-Null
	$arguments.Add($vmSku) | Out-Null
	$arguments.Add($simulate) | Out-Null
	$arguments.Add($dataDiskNamePrefix) | Out-Null
	$arguments.Add($dbDiskSizeInGB) | Out-Null
	$arguments.Add($dbDiskType) | Out-Null
	$arguments.Add($computerName) | Out-Null

	$preamble = {
		param(
			[string]$environment, 
			[string]$slot,
			[string]$facility, 
			[string]$subscription, 
			[bool]$usage,
			[string]$category,
			[string]$vmSku,
			[bool]$simulate,
			[string]$dataDiskNamePrefix,
			[int]$dbDiskSizeInGB,
			[string]$dbDiskType,
			[string]$computerName
		)
		
		Write-Host "_____>" $simulate
		. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
		$newctx = Login-WorkspaceAzureAccount -environment $environment -slot $slot -facility $facility -subscription $subscription 
	}

	$scriptBlock = [scriptblock]::Create($preamble.ToString() + " " + $scriptToRun.ToString())

	$jobName = $name
	if ($jobName -eq $null){
		$jobName = $((Get-PSCallStack)[1].Command) + "-" + $ctx.GetResourcePostfix($usage)
	}

	Write-Host "Starting job:" $jobName
	$job = Start-Job -Name $jobName `
					 -ArgumentList $arguments `
					 -ScriptBlock $scriptBlock

	$job
}

function Create-Core{
	param(
		[Context]$ctx,
		[int]$webScaleSetSize=2,
		[int]$ftpScaleSetSize=2,
		[switch]$networkOnly,
		[switch]$excludeVPN,
		[switch]$excludeNetwork,
		[switch]$primary,
		[switch]$secondary,
		[switch]$vpnOnly,
		[switch]$vnetOnly,
		[switch]$computeOnly,
		[switch]$excludeBase,
		[switch]$baseOnly,
		[switch]$excludeCompute,
		[switch]$excludeVnet,
		[switch]$forceKeyVault,
		[array]$computeElements=@("db", "web", "ftp", "jump", "ftp", "admin"),
		[string]$webVmSku = "Standard_DS2_v2",
		[string]$dbVmSku = "Standard_DS13_v2",
		[string]$dbComputerName = "sql1",
		[int]$dbDiskSizeInGB = 256,
		[string]$dbDiskType = "StandardLRS",
		[string]$fileShareName = "workspace-file-storage",
		[switch]$simulate
	)
	
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true)

	#if ($ctx.subscription -eq "d"){
	#	Create-Core-Dev -ctx $ctx -computeOnly -vmSize $vmSize -computerName $computerName
	#	return
	#}

	$facilities = [Context]::GetFacilityUsages($primary, $secondary)
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$jobs = New-Object System.Collections.ArrayList

	if (!$computeOnly -and !$baseOnly -and !$excludeVnet -and !$excludeNetwork -and !$vpnOnly -or $vnetOnly){
		foreach ($usage in $facilities){
			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
				    -usage $usage `
					-name $("Deploy-VNET-" + $ctx.GetResourcePostfix($usage)) `
					-scriptToRun {
		 				Deploy-VNet -ctx $newctx -secondary:$usage
					}
			$jobs.Add($job) | Out-Null
		}     
	}
	
	# KV has a bug that it can't be run in a sub-job, so we have to do it at this level
	# this does everything, but excludes KV
	if (!$excludeBase -and !$vnetOnly -and !$computeOnly){
		foreach ($usage in $facilities){
			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
				    -usage $usage `
					-name $("Create-BaseEntities-" + $ctx.GetResourcePostfix($usage)) `
					-scriptToRun {
		 				Create-BaseEntities -ctx $newctx -secondary:$usage -excludeKeyVault
					}
			$jobs.Add($job) | Out-Null
		}
	}

	Wait-ForJobsToComplete $jobs

	if ($vnetOnly -and !$forceKeyVault){ return }
	
	# And now, unfortunately, we have to do KV top level, and serially if both regions
	if (!$excludeBase -and !$computeOnly -and !$computeOnly -or $forceKeyVault){
		foreach ($usage in $facilities){
		 	Create-BaseEntities -ctx $ctx -secondary:$usage -keyVaultOnly
		}
	}

	if ($vnetOnly){ return }
	if ($baseOnly) { return }

	$jobs.Clear()

	if ($vpnOnly -or (!$excludeVPN -and !$computeOnly) -and ($facilities.length -ne 1)){
		$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
				-name $("Deploy-VPN-" + $ctx.GetResourcePostfix($false) + "-" + $ctx.GetResourcePostfix($true)) `
				-scriptToRun {
					Deploy-VPN -ctx $newctx
				}
		$jobs.Add($job) | Out-Null
	}

	if ($excludeCompute){
		Wait-ForJobsToComplete $jobs
		return
	}

	if ("db" -in $computeElements -and !$excludeCompute -and !$networkOnly){
		foreach ($usage in $facilities){
			Write-Host "#########" $dbVmSku

			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription -vmSku $dbVmSku -simulate:$simulate `
				-dataDiskNamePrefix $dataDiskNamePrefix `
				-dbDiskSizeInGB $dbDiskSizeInGB -dbDiskType $dbDiskType `
				-computerName $dbComputerName `
								   -usage $usage `
								   -name $("Deploy-DB-" + $ctx.GetResourcePostfix($usage)) `
								   -scriptToRun {
										 Write-Host "Starting Deploy-DB subtask"
										 <#										 Old Task
										Ensure-DiskPresent -ctx $newctx -secondary:$usage -diskNamePrefix  "data1-sql1-db" -sizeInGB 64
										Ensure-DiskPresent -ctx $newctx -secondary:$usage -diskNamePrefix  "init1-sql1-db" -sizeInGB 64
									   
									    $keyVaultName = $newctx.GetKeyVaultName($usage)
										$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey"
										$installersStorageAccountName = $newctx.GetSharedStorageAccountName("installers", $usage)
										$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"
										$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey"
										$dbSaUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName"
										$dbSaPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword"
										$dbLoginUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName"
										$dbLoginPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword"
										$dbAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName"
										$dbAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword"
									    $dbBackupsStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "dbBackupsStorageAccountKey"
									   
										Deploy-DB -ctx $newctx -secondary:$usage `
												  -diagnosticStorageAccountKey $diagStorageAccountKey `
												  -dataDogApiKey $dataDogApiKey `
												  -installersStgAcctKey $installersStorageAccountKey -installersStgAcctName $installersStorageAccountName `
												  -adminUserName $dbAdminUserName -adminPassword $dbAdminPassword `
												  -saUserName $dbSaUserName -saPassword $dbSaPassword `
												  -loginUserName $dbLoginUserName -loginPassword $dbLoginPassword `
												  -dbBackupsStorageAccountKey $dbBackupsStorageAccountKey
									   
									    Delete-DiskFromVM -ctx $newctx -secondary:$secondary -diskNamePrefix "init1-sql1-db" -vmNamePrefix "sql1-db"
										#>

										$databaseVolumeLabel = "WorkspaceDB"
										<# for AW
										$databaseName = "AdventureWorks"
										$dbMdfFileName = "AdventureWorks2016_Data"
										$dbLdfFileName = "AdventureWorks2016_log"
										$dbBackupBlobName = "AdventureWorks2016.bak"
										#>
										$databaseName = "Workspace_v3.0"
										$dbMdfFileName = "ws1"
										$dbLdfFileName = "ws1"
										$dbBackupBlobName = "WS-REDACTED-20180225.BAK"

										$keyVaultName = $newctx.GetKeyVaultName($false)
										$adminUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName"
										$adminPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword"
										$saUserName       = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName"
										$saPassword       = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword"
										$loginUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName"
										$loginPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword"
									
										$dbBackupsStorageAccountName = $newctx.GetDataPlatformSubscriptionStorageAccountName("dbbackups", $secondary)
										$dbBackupsStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "dbBackupsStorageAccountKey"
									
										$resourceNamePostfix = $newctx.GetResourcePostfix($secondary)
										$dataDiskNamePrefix = $("data1-" + $computerName + "-vm-db")
									
										$diagStorageAccountName = $newctx.GetSharedStorageAccountName("diag", $usage)
										$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"

										Write-Host "##########" $vmSku $diagStorageAccountName $diagStorageAccountKey $computerName $dataDiskNamePrefix $dbDiskSizeInGB $dbDiskType

										$resourceGroupName = $newctx.GetResourceGroupName("db", $usage)
										$parameters = @{
											"resourceNamePostfix" = $resourceNamePostfix
											"vmSize" = $vmSku
											"computerName" = $computerName
											"adminUserName" = $adminUserName
											"adminPassword" = $adminPassword
											"loginUserName" = $loginUserName
											"loginPassword" = $loginPassword
											"saUserName" = $saUserName
											"saPassword" = $saPassword
											"dbBackupsStorageAccountName" = $dbBackupsStorageAccountName
											"dbBackupsStorageAccountKey" = $dbBackupsStorageAccountKey
											"databaseName" = $databaseName
											"dbMdfFileName" = $dbMdfFileName
											"dbLdfFileName" = $dbLdfFileName
											"dbBackupBlobName" = $dbBackupBlobName
											"databaseVolumeLabel" = $databaseVolumeLabel
											"environmentCode" = $newctx.environment + $newctx.slot
											"diagStorageAccountName" = $diagStorageAccountName
											"diagStorageAccountKey" = $diagStorageAccountKey
										}
									
										Ensure-DiskPresent -ctx $newctx -diskNamePrefix $dataDiskNamePrefix -sizeInGB $dbDiskSizeInGB -accountType $dbDiskType
										Ensure-ResourceGroup -ctx $newctx -category "db" -secondary:$secondary
										Execute-Deployment -templateFile "arm-deploy-db-from-image.json" -resourceGroup $resourceGroupName -parameters $parameters -simulate:$simulate
									
 									    Write-Host "Ending Deploy-DB subtask"
									}
			$jobs.Add($job) | Out-Null
		}
	}
Write-Host "*******>" $simulate $webVmSku
	if ("web" -in $computeElements -and !$excludeCompute -and !$networkOnly){
		foreach ($usage in $facilities){

			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription -vmSku $webVmSku -simulate:$simulate `
						-usage $usage `
						-name $("Deploy-WEB-" + $ctx.GetResourcePostfix($usage)) `
						-scriptToRun {
							Write-Host "========>" $simulate $diagStorageAccountName $diagStorageAccountKey 

							$keyVaultName = $newctx.GetKeyVaultName($usage)

							$diagStorageAccountName = $newctx.GetSharedStorageAccountName("diag", $usage)
							$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"
							$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey"

							$fileShareStorageAccountKey = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey"
							$octoApiKey                 = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoApiKey"
							$octoUrl                    = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoUrl"
							$webAdminUserName           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName"
							$webAdminPassword           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword"
							$webSslCertificateId        = Get-KeyVaultSecretId -KeyVaultName $keyVaultName -SecretName "WebSslCertificate"

							$fileStgAcctName = $newctx.GetFilesStorageAccountName($usage)
							$fileShareName = "workspace-file-storage"

							Deploy-Web -ctx $newctx -secondary:$usage `
									-diagnosticStorageAccountName $diagStorageAccountName -diagnosticStorageAccountKey $diagStorageAccountKey `
									-dataDogApiKey $dataDogApiKey `
									-scaleSetCapacity $using:webScaleSetSize `
									-adminUserName $webAdminUserName -adminPassword $webAdminPassword -sslCertificateUrl $webSslCertificateId `
									-octoUrl $octoUrl -octoApiKey $octoApiKey `
									-fileShareKey $fileShareStorageAccountKey -fileStgAcctName $fileStgAcctName -fileShareName $fileShareName `
									-vmSku $vmSku `
									-simulate:$simulate
						}
			$jobs.Add($job) | Out-Null
		}
	}

	if ("ftp" -in $computeElements -and !$excludeCompute -and !$networkOnly){
		foreach ($usage in $facilities){
			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
						-usage $usage `
						-name $("Deploy-FTP-" + $ctx.GetResourcePostfix($usage)) `
						-scriptToRun {
							$keyVaultName = $newctx.GetKeyVaultName($usage)
							$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"
							$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey"
							$ftpAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminName"
							$ftpAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminPassword"

							Deploy-FTP -ctx $newctx -secondary:$usage `
									   -diagnosticStorageAccountKey $diagStorageAccountKey `
									   -dataDogApiKey $dataDogApiKey `
									   -scaleSetCapacity $using:ftpScaleSetSize `
									   -adminUserName $ftpAdminUserName -adminPassword $ftpAdminPassword 
						}
			$jobs.Add($job) | Out-Null
		}
	}

	if ("jump" -in $computeElements -and !$excludeCompute -and !$networkOnly){
		foreach ($usage in $facilities){
			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
						-usage $usage `
						-name $("Deploy-JUMP-" + $ctx.GetResourcePostfix($usage)) `
						-scriptToRun {
							$keyVaultName = $newctx.GetKeyVaultName($usage)
							$jumpAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminName"
							$jumpAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminPassword"
							$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey"
							$installersStorageAccountName = $newctx.GetSharedStorageAccountName("installers", $usage)

							Deploy-Jump -ctx $newctx -secondary:$usage `
									   -diagnosticStorageAccountKey $diagStorageAccountKey `
									   -dataDogApiKey $dataDogApiKey `
									   -adminUserName $jumpAdminUserName -adminPassword $jumpAdminPassword `
 									   -installersStgAcctKey $installersStorageAccountKey -installersStgAcctName $installersStorageAccountName 
			}
			$jobs.Add($job) | Out-Null
		}
	}

	if ("admin" -in $computeElements -and !$excludeCompute -and !$networkOnly){
		foreach ($usage in $facilities){
			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
					-usage $usage `
					-name $("Deploy-ADMIN-" + $ctx.GetResourcePostfix($usage)) `
					-scriptToRun {
						$keyVaultName = $newctx.GetKeyVaultName($usage)
						$adminAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminName"
						$adminAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminPassword"

						Deploy-Admin -ctx $newctx -secondary:$usage `
									    -diagnosticStorageAccountKey $diagStorageAccountKey `
									    -dataDogApiKey $dataDogApiKey `
									    -adminUserName $adminAdminUserName -adminPassword $adminAdminPassword 
			}
			$jobs.Add($job) | Out-Null
		}
	}

	Wait-ForJobsToComplete $jobs

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-ResourceCategory{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[string]$category
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $category

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName($category, $secondary)

	Write-Host "Getting resource group: " $resourceGroupName
	$rg =  Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue
	if ($rg -eq $null)
	{
		Write-Host "Resource group did not exist: " $resourceGroupName
	}
	else
	{
		Write-Host "Deleting resource group: " $resourceGroupName
		Remove-AzureRmResourceGroup -Name $resourceGroupName -Force -InformationAction Continue | Out-Null
		Write-Host "Deleted resource group: " $resourceGroupName
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-Core{
	param(
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$excludeDiagnostics,
		[switch]$excludeFiles,
		[switch]$forceProdFilesRemoval,
		[switch]$filesOnly,
		[switch]$includeDisks,
		[switch]$dataDisksOnly,
		[switch]$computeOnly,
		[switch]$excludeCompute,
		[array]$computeElements = @("db", "web", "ftp", "jump", "admin", "svc"),
		[switch]$vnetOnly,
		[switch]$excludeNetwork,
		[switch]$baseOnly,
		[switch]$all
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.environment $ctx.facility $ctx.subscription $secondary $includeServices

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$groups = New-Object System.Collections.ArrayList

	$filesElements=@()
	if (($all -and $forceProdFilesRemoval) -or (!$excludeFiles -and ($ctx.environment -ne "p" -or  ($forceProdFilesRemoval -and ($ctx.environment -eq "p"))))){
		$filesElements = @("files")
	}

	$diskElements = @()
	if (($all -and $includeDisks) -or $includeDisks){
		$diskElements = @("disks")
	}

	$vnetElements = @()
	if ($all -or !$excludeNetwork){
		$vnetElements = @("vnet")
	}

	$diagElements = @()
	if ($all -or !$excludeDiagnostics){
		$diagElements = @("diag", "bootdiag")
	}

	if (!$all -and $excludeCompute){ $computeElements = @() }

	$group1 = @($computeElements) 
	$group2 = @($vnetElements + $filesElements + $diskElements + $diagElements)
	$groups = $group1, $group2

	if (!$all -and $baseOnly){
		$groups = @()
		$groups += $filesElements
		$groups += $diskElements
		$groups += $diagElements
	}
	if (!$all -and $computeOnly){
		$groups = @($computeElements)
	}
	if (!$all -and $vnetOnly){
		$groups = @($vnetElements)
	}
	if (!$all -and $dataDisksOnly){
		$groups = @($diskElements)
	}
	if (!$all -and $filesOnly){
		$groups = @($filesElements)
	}

	$usages = [Context]::GetFacilityUsages($primary, $secondary)

	foreach ($group in $groups){
		$jobs = New-Object System.Collections.ArrayList
		foreach ($category in $group){
			foreach ($usage in $usages){
				$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
				    				   -usage $usage `
										-name $("TCE-" + $ctx.GetResourcePostfix($usage) + "-" + $category) `
										-category $category `
										-scriptToRun {
											Teardown-ResourceCategory -ctx $newctx -secondary:$usage -category $category
										}
				$jobs.Add($job) | Out-Null
			}
		}

		Write-Host $jobs.Count "jobs created"
		if ($jobs.Count -gt 0){
			Wait-ForJobsToComplete $jobs
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-ResourceCategories{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[string]$category
	)

	$job = Start-Job -Name $($MyInvocation.MyCommand + "-" + $ctx.GetResourcePostfix($secondary)) -ArgumentList $ctx.environment,$ctx.Getfacility($usage),$ctx.subscription -ScriptBlock {
		param([string]$environment, [string]$facility, [string]$subscription)
		. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
		$newctx = Login-WorkspaceAzureAccount -environment $environment -slot $ctx.slot -facility $facility -subscription $subscription
		Teardown-ResourceCategory -ctx $newctx -secondary:$using:secondary -category $using:category
	}

	Wait-ForJobsToComplete @($job)
}

function Create-DiagnosticsEntities{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceCategories = @("bootdiag", "diag")

	$jobs = New-Object System.Collections.ArrayList

	foreach ($rc in $resourceCategories){
		$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
				    	-usage $secondary `
						-name $("Create-Diag-Storage-Accounts" + "-" + $ctx.GetResourcePostfix($secondary)) `
						-category $rc `
						-scriptToRun {
							$resourceGroupName = $newctx.GetResourceGroupName($category, $usage)
							$storageAccountName = $newctx.GetStorageAccountName($category, $usage)
							Ensure-ResourceGroup -ctx $newctx -secondary:$usage -category $category
							Ensure-StorageAccount -ctx $newctx -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
						}
		$jobs.Add($job) | Out-Null
	}

	Wait-ForJobsToComplete $jobs

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-Diagnostics{
	param(
		[Context]$ctx
	)
	Write-Host "In: " $MyInvocation.MyCommand 

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Teardown-DiagnosticsEntities -ctx $ctx -secondary:$false
	Teardown-DiagnosticsEntities -ctx $ctx -secondary:$true

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-DiagnosticsEntities{
	param(
		[Context]$context,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$group1 = @("bootdiag", "diag")
	foreach ($rc in $group1){
		Teardown-ResourceCategory -ctx $ctx -secondary:$secondary -category $rc
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-DatabaseDisk{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Teardown-ResourceCategory -ctx $ctx -secondary:$secondary -category "disks"

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility
}

function Create-BaseEntities{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[switch]$excludeKeyVault,
		[switch]$keyVaultOnly
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$jobs = New-Object System.Collections.ArrayList

	if (!$keyVaultOnly){
		$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
						-usage $secondary `
						-name $("Create-DiagnosticsEntities" + "-" + $ctx.GetResourcePostfix($secondary)) `
						-scriptToRun {
							Create-DiagnosticsEntities -ctx $newctx -secondary:$usage
						}
		$jobs.Add($job) | Out-Null

		$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
						-usage $secondary `
						-name $("Create-AzureFilesEntities" + "-" + $ctx.GetResourcePostfix($secondary)) `
						-scriptToRun {
							Create-AzureFilesEntities -ctx $newctx -secondary:$usage
						}
		$jobs.Add($job) | Out-Null

		Wait-ForJobsToComplete $jobs
	}
	$jobs.Clear()

	if (!$excludeKeyVault)
	{
		# must do KV after the prior two as it needs keys from both
		Build-KeyVault -ctx $ctx -secondary:$secondary
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Create-AzureFilesEntities{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$location = $ctx.GetLocation($secondary)
	$resourceGroupName = $ctx.GetFilesResourceGroupName($secondary)
	$storageAccountName = $ctx.GetFilesStorageAccountName($secondary)

	$useDataPlatform = $resourceGroupName.EndsWith("ss0p") -or $resourceGroupName.EndsWith("ss0d")
	if ($useDataPlatform) {
		Set-DataPlatformContext -ctx $ctx
	}

	Ensure-ResourceGroup -ctx $ctx -category "files" -secondary:$secondary
	Ensure-StorageAccount -ctx $ctx -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	Create-AzureFilesShare -ctx $ctx -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

	if ($useDataPlatform){
		Revert-Context -ctx $ctx
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Get-AllWorkspaceEntities{
	# codes don't matter for this process: this will get all item the selected subscription
	$ctx = Login-WorkspaceAzureAccount -environment "p" -slot "0" -facility "p" -subscription "ws"
	Get-AzureRmResource | Select-Object Name, Location, ResourceGroupName, ResourceType | `
		Sort-Object -Property @{Expression = "Location"; Descending=$true}, ResourceGroupName, ResourceType 
}

function Write-AllWorkspaceEntitiesToCSV{
	Get-AllWorkspaceEntities | Export-Csv -Path $($currentDir + "\resources.csv")
}

function Create-AzureFilesShare{
	param(
		[Context]$ctx,
		[string]$resourceGroupName,
		[string]$storageAccountName
	)
	Write-Host "In: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-StorageAccount -ctx $ctx  -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

	$storageAccountKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName
	$storageAccountKey = $storageAccountKeys.Value[0]

	$context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
	$share = Get-AzureStorageShare -Name $fileSharesName -Context $context  -ErrorAction SilentlyContinue
	if ($share -eq $null){
		New-AzureStorageShare -Name $fileSharesName -Context $context
		Set-AzureStorageShareQuota -ShareName $fileSharesName -Context $context -Quota $fileSharesQuota
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Teardown-AzureFilesEntities{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$location = $ctx.GetLocation($secondary)
	$resourceGroupName = $ctx.GetResourceGroupName("files", $secondary)
	$storageAccountName = $ctx.GetStorageAccountName("files", $secondary)

	Teardown-ResourceCategory -ctx $ctx -secondary:$secondary -category "files"

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Stop-ComputeResources{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeServicesVMs
	)
	
	Stop-ComputeVMs -ctx $ctx -primary:$primary -secondary:$secondary
	Stop-ScaleSetVMs -ctx $ctx -primary:$primary -secondary:$secondary

	if ($includeServicesVMs){
		$servicesCtx = [Context]::newEnvironmentContextFrom($ctx, "s", "0")
		Stop-ComputeVMs -ctx $ctx -primary:$primary -secondary:$secondary
	}
}

function Stop-ComputeVMs{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeServicesVMs
	)
	$usages = [Context]::GetFacilityUsages($primary, $secondary)
	foreach ($usage in $usages)	{
		$resourcePostfix = $ctx.GetResourcePostfix($usage)
		$allVirtualMachines = Get-AzureRmVM
		$virtualMachinesToStop =  $allVirtualMachines | Where-Object { $_.Name.EndsWith($resourcePostfix) }
		$virtualMachinesToStop | ForEach-Object -Process {
			Write-Host "Stopping VM: " $_.Name
			Stop-AzureRmVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force -InformationAction Continue
		}
	}
}

function Stop-ScaleSetVMs{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeServicesVMs
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$usages = [Context]::GetFacilityUsages($primary, $secondary)
	foreach ($usage in $usages)	{
		$resourcePostfix = $ctx.GetResourcePostfix($usage)
		$allScaleSets = Get-AzureRmVmss 
		$scaleSets = $allScaleSets | Where-Object { $_.Name.EndsWith($resourcePostfix) }
		foreach ($scaleSet in $scaleSets){
			$vmssVMs = Get-AzureRmVmssVM -ResourceGroupName $scaleSet.ResourceGroupName -VMScaleSetName $scaleSet.Name 
			foreach ($vmssVM in $vmssVMs){
				Write-Host "Stopping VMSS VM: " $scaleSet.Name $vmssVM.Name
				Stop-AzureRmVmss -ResourceGroupName $scaleSet.ResourceGroupName -VMScaleSetName $scaleSet.Name -InstanceId $vmssVM.InstanceId -StayProvisioned -Force -InformationAction Continue
			}
		}
	}
}

function Start-ComputeResources{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Start-ComputeVMs -ctx $ctx -primary:$primary -secondary:$secondary
	Start-ScaleSetVMs -ctx $ctx -primary:$primary -secondary:$secondary
}

function Start-ComputeVMs{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary
	)

	$usages = [Context]::GetFacilityUsages($primary, $secondary)
	foreach ($usage in $usages)	{
		$resourcePostfix = $ctx.GetResourcePostfix($usage)
		$allVirtualMachines = Get-AzureRmVM
		$virtualMachinesToStop =  $allVirtualMachines | Where-Object { $_.Name.EndsWith($resourcePostfix) }
		$virtualMachinesToStop | ForEach-Object -Process {
			Write-Host "Starting VM: " $_.Name
			Start-AzureRmVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name
		}
	}
}

function Start-ScaleSetVMs{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$usages = [Context]::GetFacilityUsages($primary, $secondary)
	foreach ($usage in $usages)	{
		$resourcePostfix = $ctx.GetResourcePostfix($usage)
		$allScaleSets = Get-AzureRmVmss 
		$scaleSets = $allScaleSets | Where-Object { $_.Name.EndsWith($resourcePostfix) }
		foreach ($scaleSet in $scaleSets){
			$vmssVMs = Get-AzureRmVmssVM -ResourceGroupName $scaleSet.ResourceGroupName -VMScaleSetName $scaleSet.Name 
			foreach ($vmssVM in $vmssVMs){
				Write-Host "Starting VMSS VM: " $scaleSet.Name $vmssVMs.Name
				Start-AzureRmVmss -ResourceGroupName $scaleSet.ResourceGroupName -VMScaleSetName $scaleSet.Name -InstanceId $vmssVM.InstanceId
			}
		}
	}
}

function Find-OpenDeploymentSlotNumber{
	# finds the first numeric deployment slot for an environment
	# this is defined by looking for the vnets and finding the first
	# open spot ?n-vnet-<postfix>, the lowest number n in 0-7 
	# where a vnet is not found

	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx
	)

	$env = $ctx.environment
	$postfix = $ctx.GetResourcePostfix($false)
	$utilized = @{
		$($env + "0") = $false
		$($env + "1") = $false
		$($env + "2") = $false
		$($env + "3") = $false
		$($env + "4") = $false
		$($env + "5") = $false
		$($env + "6") = $false
		$($env + "7") = $false
	}

	$vnetNames = Get-AzureRmVirtualNetwork | Where-Object {$_.Name.StartsWith("p")} | Select-Object -Property Name -ExpandProperty Name

	foreach ($vnetName in $vnetNames)
	{
		$envCode = $vnetName.Split("-")[0]
		if ($envCode -in $utilized.Keys){
			$utilized[$envCode] = $true
		}
	}

	#$vnetNames | ForEach-Object -Process { $utilized[$_] = $true }
	#$utilized | Where-Object {$_.Value}

	$free = $utilized.GetEnumerator() | Where-Object { !$_.Value } | Select-Object -ExpandProperty Name

	$next = $free | Sort-Object | Select-Object -First 1
	$next[1]
}

function Create-NextEnvironmentSlotContext{
	param(
		[Context]$ctx,
		[string]$instanceId
	)

	$newCtx = [Context]::newEnvironmentContextFrom($ctx, $ctx.environment, $instanceId)
	return $newCtx
}

function Deploy-NextEnvironmentInstance{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeBase,
		[int]$webScaleSetSize=2,
		[int]$ftpScaleSetSize=2,
		[array]$computeElements=@("db", "web", "ftp", "jump", "ftp", "admin")
	)

	Write-Host "Starting deploy of next environment" $ctx.environment $ctx.facility $ctx.subscription $primary $secondary $includeBase

	$instanceId = Find-OpenDeploymentSlotNumber $ctx

	Write-Host "Next environment slot is: " $instanceId

	$newCtx = Create-NextEnvironmentSlotContext -ctx $ctx -instanceId $instanceId

	#if ($includeBase) { Create-Base -ctx $newCtx }
	Create-Core -ctx $newCtx -primary:$primary -secondary:$secondary -webScaleSetSize $webScaleSetSize -ftpScaleSetSize $ftpScaleSetSize -computeElements $computeElements

	return $newCtx
}

function Delete-AllResourcesInRole{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[Parameter(Mandatory=$true)]
		[string]$category,
		[Parameter(Mandatory=$true)]
		[string]$role
	)

	$resourceNamePostfix = $ctx.GetResourcePostfix($secondary)
	
	$resourceOrderMap = @{}
	$resourceMap = @{}

	$matched = Find-AzureRmResource -Tag @{ Role = $role } | foreach {
		$tags = (Get-AzureRmResource -ResourceId $_.ResourceId).Tags
		$resourceOrderMap[$_.ResourceId] = $tags["DeleteOrder"] -as [int]
		$resourceMap[$_.ResourceId] = $_
	}

	Write-Host "Deleting the following resources:"
	Foreach ($de in $resourceMap.GetEnumerator()){
		$r = $resourceMap[$de.Key]
		Write-Host "Deleting: " $r.ResourceName $r.ResourceType
	}
	$currentOrder = 0
	while ($resourceOrderMap.Count -gt 0){
		$removed = New-Object System.Collections.ArrayList
		Foreach ($de in ($resourceOrderMap.GetEnumerator() | Where-Object {$_.Value -eq $currentOrder})){
			$removed.Add($de.Key)

			$r = $resourceMap[$de.Key]
			Remove-AzureRmResource -ResourceId $de.Key -Force -InformationAction Continue -Verbose
		}

		foreach ($key in $removed){
			$resourceOrderMap.Remove($key)
		}

		$currentOrder++
	}

	$toDelete = $null
}

function Set-WebScaleSetSize{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[Parameter(Mandatory=$true)]
		[int]$size,
		[switch]$primary,
		[switch]$secondary
	)

	Set-ScaleSetSize -ctx $ctx -category "web" -size $size -primary:$primary -secondary:$secondary
}

function Set-FtpScaleSetSize{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[Parameter(Mandatory=$true)]
		[int]$size,
		[switch]$primary,
		[switch]$secondary
	)

	Set-ScaleSetSize -ctx $ctx -category "ftp" -size $size -primary:$primary -secondary:$secondary
}

function Set-ScaleSetSize{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[Parameter(Mandatory=$true)]
		[string]$category,
		[Parameter(Mandatory=$true)]
		[int]$size,
		[switch]$primary,
		[switch]$secondary
	)
	$usages = [Context]::GetFacilityUsages($primary, $secondary)
	foreach ($usage in $usages){
		$resourceGroupName = $ctx.GetResourceGroupName($category, $usage)
		$scaleSetName = $ctx.GetScaleSetName($category, $usage)
		$vmss = Get-AzureRmVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $scaleSetName
		$vmss.sku.capacity = $size
		Update-AzureRmVmss -ResourceGroupName $resourceGroupNam -Name $scaleSetName -VirtualMachineScaleSet $vmss
	}
}

function Cancel-ActiveDeployments{
	param(
		[Context]$ctx
	)
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$groups = Get-AzureRmResourceGroup
	foreach ($group in $groups){
		$groupName = $group.ResourceGroupName
		Write-Host "Checking:" $groupName

		$deployments = Get-AzureRmResourceGroupDeployment -ResourceGroupName $groupName
		foreach ($deployment in $deployments){
			if ($deployment.ProvisioningState -eq "Running"){
				Write-Host "  Found:" $deployment.DeploymentName
				Stop-AzureRmResourceGroupDeployment -ResourceGroupName $groupName -Name $deployment.DeploymentName | Out-Null
				Write-Host "    Stopped"
			}
		}
	}
}

function Create-Core-Dev{
	param(
		[Context]$ctx,
		[string]$vmSize,
		[string]$computerName
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	#Deploy-DevVnet -ctx $ctx
	Build-DevMachineImage -ctx $ctx -vmSize $vmSize -computerName $computerName
	
	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-DevVnet{
	param(
		[Context]$ctx
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$resourceGroupName = "rg-vnet-dd0p"
	$parameters = @{
		"vnetCidrPrefix" = "10.32."
		"resourceNamePostfix" = "dd0p"
		"vnetName" = "d0"
		"role" = "dev"
	}

	Ensure-ResourceGroup -ctx $ctx "vnet"

	Execute-Deployment -templateFile "arm-devvnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}
function Build-DevMachineImage{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_D2_v3",
		[string]$computerName = "d2v3"
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$resourceGroupName = "rg-dev-dd0p"
	$parameters = @{
		"resourceNamePostfix" = "dd0p"
		"role" = "devworkstation"
		"adminUserName" = "wsadmin"
		"adminPassword" = "Workspace!Dev!2018"
		#"vmSize" = "Standard_D2_v3"
		#"vmSize" = "Standard_B4ms" 
		"vmSize" = $vmSize
		"computerName" = $computerName
		"installersStgAcctKey" = "RTroekJPVf2/9tMyTfJ+LTrup0IwZIDyuus13KoQX0QuH3MCTBLt0wawD0Air2bMYF03JDV0sRSYuqYypSBxbg=="
		"installersStgAcctName" = "stginstallersss0p"
		"saUserName" = "wsadmin"
		"saPassword" = "Workspace!Dev!2018"
		"loginUserName" = "wsapp"
		"loginPassword" = "Workspace!Dev!2018"
		"dbBackupsStorageAccountName" = "stgdbbackupsss0p"
		"dbBackupsStorageAccountKey" = "MjxzzdLwmgeB6emUEcepOEko+SYiZtPE578BMXFeSMQnXHXO7PJm8EyhM9Ndk1afp94wZ55vXp656li6BlD+6w=="
		"dbBackupBlobName" = "AdventureWorks2016.bak"
		"databaseName" = "AdventureWorks"
		"dbMdfFileName" = "AdventureWorks2016_Data"
		"dbLdfFileName" = "AdventureWorks2016_log"
	}

	Ensure-ResourceGroup -ctx $ctx "dev"
	Execute-Deployment -templateFile "arm-devvmbuild-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Create-DevVM{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_D2_v3",
		[string]$computerName = "d2v3"
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$resourceGroupName = "rg-dev-dd0p"
	$parameters = @{
		"resourceNamePostfix" = "dd0p"
		"role" = "devworkstation"
		"adminUserName" = "wsadmin"
		"adminPassword" = "Workspace!Dev!2018"
		"vmSize" = $vmSize
		"computerName" = $computerName
	}

	Ensure-ResourceGroup -ctx $ctx "dev"

	#Copy-DevDataDisk -ctx $ctx -computerName $computerName

	Execute-Deployment -templateFile "arm-devvm-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Copy-DevDataDisk{
	param(
		[Context]$ctx,
		[string]$computerName
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$diskName = $("datadisk-" + $computerName + "-vm-dev-dd0p")

	$rng = "rg-devvmimages-dd0p"
	$disk = Get-AzureRmDisk -DiskName $$diskName -ResourceGroupName $rng -ErrorAction SilentlyContinue -ErrorVariable err
	if ($err -ne $null) { return $false }

	$disk = Get-AzureRmDisk -ResourceGroupName "rg-dev-dd0p" -DiskName "datadisk-dev-dd0p"

	$diskConfig = New-AzureRmDiskConfig -SourceResourceId $disk.Id -CreateOption Copy -Location "westus" 
	New-AzureRmDisk -ResourceGroupName "rg-devvmimages-dd0p" -Disk $diskConfig -DiskName $diskName

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Create-SystemImage{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_D2_v3",
		[string]$computerName = "d2v3",
		[switch]$development,
		[switch]$database,
		[switch]$web
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$resourceGroupName = "rg-dev-dd0p"
	$parameters = @{
		"resourceNamePostfix" = "dd0p"
		"role" = "devworkstation"
		"adminUserName" = "wsadmin"
		"adminPassword" = "Workspace!Dev!2018"
		"vmSize" = $vmSize
		"computerName" = $computerName
	}

	Ensure-ResourceGroup -ctx $ctx "dev"

	#Copy-DevDataDisk -ctx $ctx -computerName $computerName

	Execute-Deployment -templateFile "arm-devvm-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}


function Build-WebServerImageBase{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_B4ms",
		[string]$computerName = "wwwib"
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$keyVaultName = $ctx.GetKeyVaultName($usage)
	$webAdminUserName           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName"
	$webAdminPassword           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword"
	$resourceGroupName = $ctx.GetResourceGroupName("imagebuild", $false)

	$parameters = @{
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"adminUserName" = $webAdminUserName
		"adminPassword" =$webAdminPassword
		"vmSize" = $vmSize
		"computerName" = $computerName
		"subnetName" = "default"
		"environmentCode" = $ctx.environment + $ctx.slot
		#"sslCertificateUrl" = $webSslCertificateId
		#"fileShareKey" = $fileShareStorageAccountKey
		#"fileStgAcctName" = $fileStgAcctName
		#"fileShareName" = $fileShareName
	}

	Ensure-ResourceGroupWithName -ctx $ctx -resourceGroupName $resourceGroupName
	Execute-Deployment -templateFile "arm-image-build-web.json" -resourceGroup $resourceGroupName -parameters $parameters

	#$vmName = "wwwib-vm-web-dd0p"
	#$customScriptName = "configure-web-server-image-base"
	#Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name $customScriptName -Force

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Build-DatabaseServerImageBase{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_D2S_v3",
		[string]$computerName = "dbib"
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$keyVaultName = $ctx.GetKeyVaultName($false)
	$resourceGroupName = "rg-dbimagebuild-tp0p"

	$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey"
	$installersStorageAccountName = $ctx.GetSharedStorageAccountName("installers", $false)
	$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"
	$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey"
	$saUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName"
	$saPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword"
	$loginUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName"
	$loginPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword"
	$adminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName"
	$adminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword"

	$parameters = @{
		"installersStgAcctKey" = $installersStorageAccountKey
		"installersStgAcctName" = $installersStorageAccountName
		"resourceNamePostfix" = "tp0p"
		"adminUserName" = $adminUserName
		"adminPassword" =$adminPassword
		"saUserName" = $saUserName
		"saPassword" =$saPassword
		"loginUserName" = $loginUserName
		"loginPassword" = $loginPassword
		"vmSize" = $vmSize
		"computerName" = $computerName
		"environmentCode" = $ctx.environment + $ctx.slot
	}

	Ensure-ResourceGroup -ctx $ctx -category "dbimagebuild"
	Execute-Deployment -templateFile "arm-image-build-db.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

Function Create-WebServerImage{
	param(
		[Context]$ctx
	)

	$vmName = "wwwib-vm-web-tp0p"
	$vmResourceGroupName = "rg-imagebuild-tp0p"
	$imageResourceGroupName = "rg-vmimages-ts0p"
	$imageName = "image-web"

	Ensure-ResourceGroup -ctx $ctx -category "vmimages"

	Stop-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName -Force
	Set-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName -Generalized
	$vm = Get-AzureRmVM -Name $vmName -ResourceGroupName $vmResourceGroupName
	$image = New-AzureRmImageConfig -Location westus -SourceVirtualMachineId $vm.Id

	#Set-DataPlatformContext -ctx $ctx
	Ensure-ResourceGroupWithName -ctx $ctx -resourceGroupName $imageResourceGroupName
	New-AzureRmImage -Image $image -ImageName $imageName -ResourceGroupName $imageResourceGroupName
}

Function Create-DatabaseServerImage{
	param(
		[Context]$ctx
	)

	$vmName = "dbib-vm-db-tp0p"
	$vmResourceGroupName = "rg-dbimagebuild-tp0p"
	$imageResourceGroupName = "rg-vmimages-tp0p"
	$imageName = "image-db"

	Ensure-ResourceGroup -ctx $ctx -category "vmimages"

	Stop-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName -Force
	Set-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName -Generalized
	$vm = Get-AzureRmVM -Name $vmName -ResourceGroupName $vmResourceGroupName
	$image = New-AzureRmImageConfig -Location westus -SourceVirtualMachineId $vm.Id

#	Set-DataPlatformContext -ctx $ctx
	New-AzureRmImage -Image $image -ImageName $imageName -ResourceGroupName $imageResourceGroupName
#	Revert-Context
}

function Deploy-StandaloneWebServerFromImage{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_B4ms",
		[string]$computerName = "www"
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$keyVaultName = $ctx.GetKeyVaultName($false)

	$resourceGroupName = "rg-testwebimage-dd0p"
	$parameters = @{
		"resourceNamePostfix" = "dd0p"
		"adminUserName" = $webAdminUserName
		"adminPassword" =$webAdminPassword
		"vmSize" = $vmSize
		"computerName" = $computerName
		"sslCertificateUrl" = $webSslCertificateId
		"fileShareKey" = $fileShareStorageAccountKey
		"fileStgAcctName" = $fileStgAcctName
		"fileShareName" = $fileShareName
		"octoUrl" = $octoUrl
		"octoApiKey" = $octoApiKey
		"octoEnvironment" = "WP0P"
	}

	Ensure-ResourceGroup -ctx $ctx -category "testwebimage"
	Execute-Deployment -templateFile "arm-deploy-web-from-image.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-StandaloneDatabaseServerFromImage{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[string]$vmSize = "Standard_D2S_v3",
		[string]$computerName = "sql1",
		[int]$diskSizeInGB = 128,
		[string]$diskType = "StandardLRS",
		[string]$databaseName = "AdventureWorks",
		[string]$dbMdfFileName = "AdventureWorks2016_Data",
		[string]$dbLdfFileName = "AdventureWorks2016_log",
		[string]$dbBackupBlobName = "AdventureWorks2016.bak",
		[string]$databaseVolumeLabel = "WorkspaceDB"
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	$keyVaultName = $ctx.GetKeyVaultName($false)
	$adminUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName"
	$adminPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword"
	$saUserName       = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName"
	$saPassword       = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword"
	$loginUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName"
	$loginPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword"

	$dbBackupsStorageAccountName = $ctx.GetDataPlatformSubscriptionStorageAccountName("dbbackups", $secondary)
	$dbBackupsStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "dbBackupsStorageAccountKey"

	$resourceNamePostfix = $ctx.GetResourcePostfix($secondary)
	$dataDiskNamePrefix = $("data1-" + $computerName + "-vm-db")

	$resourceGroupName = "rg-testdbimage-tp0p"
	$parameters = @{
		"resourceNamePostfix" = $resourceNamePostfix
		"vmSize" = $vmSize
		"computerName" = $computerName
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"loginUserName" = $loginUserName
		"loginPassword" = $loginPassword
		"saUserName" = $saUserName
		"saPassword" = $saPassword
		"dbBackupsStorageAccountName" = $dbBackupsStorageAccountName
		"dbBackupsStorageAccountKey" = $dbBackupsStorageAccountKey
		"databaseName" = $databaseName
		"dbMdfFileName" = $dbMdfFileName
		"dbLdfFileName" = $dbLdfFileName
		"dbBackupBlobName" = $dbBackupBlobName
		"databaseVolumeLabel" = $databaseVolumeLabel
		"environmentCode" = $ctx.environment + $ctx.slot
	}

	Ensure-DiskPresent -ctx $ctx -diskNamePrefix $dataDiskNamePrefix -sizeInGB $diskSizeInGB -accountType $diskType

	Ensure-ResourceGroup -ctx $ctx -category "testdbimage"
	Execute-Deployment -templateFile "arm-deploy-db-from-image.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Copy-DatabaseDiskFromStorageSubscription{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[string]$targetDiskName
	)

	$sourceSubscriptionId = $wsAcctInfo["subscriptions"]["s"]["subscriptionID"]
	$sourceResourceGroupName= "rg-dbdisks-ss0p"
	$managedDiskName = 'data1-dbdisk-' + $ctx.GetResourcePostfix($secondary)

	$targetSubscriptionId = $ctx.azureSub.Id
	$targetResourceGroupName = $ctx.GetResourceGroupName("disks", $secondary)
	
	Select-AzureRmSubscription -SubscriptionId $sourceSubscriptionId

	$managedDisk = Get-AzureRMDisk -ResourceGroupName $sourceResourceGroupName -DiskName $managedDiskName

	Select-AzureRmSubscription -SubscriptionId $targetSubscriptionId

	$diskConfig = New-AzureRmDiskConfig -SourceResourceId $managedDisk.Id -Location $managedDisk.Location -CreateOption Copy 
	New-AzureRmDisk -Disk $diskConfig -DiskName $targetDiskName -ResourceGroupName $targetResourceGroupName
}

function Copy-DiskToStorageSubscription{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[string]$sourceResourceGroupName,
		[string]$sourceDiskName,
		[string]$targetResourceCategory,
		[string]$targetDiskName
	)
	
	$managedDisk = Get-AzureRMDisk -ResourceGroupName $sourceResourceGroupName -DiskName $sourceDiskName

	Set-DataPlatformContext -ctx $ctx

	$targetResourceGroupName = $ctx.GetDataPlatformSubscriptionResourceGroupName($targetResourceCategory, $secondary)

	Ensure-ResourceGroupWithName -ctx $ctx -secondary:$secondary -resourceGroupName $targetResourceGroupName

	$diskConfig = New-AzureRmDiskConfig -SourceResourceId $managedDisk.Id -Location  $managedDisk.Location -CreateOption Copy 
	New-AzureRmDisk -Disk $diskConfig -DiskName $targetDiskName -ResourceGroupName $targetResourceGroupName 

	Revert-Context -ctx $ctx
}

<#
function Copy-DiskFromStorageSubscription{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[string]$sourceDiskName,
		[string]
	)
	
	$managedDisk = Get-AzureRMDisk -ResourceGroupName $sourceResourceGroupName -DiskName $sourceDiskName

	Set-DataPlatformContext -ctx $ctx

	$targetResourceGroupName = $ctx.GetDataPlatformSubscriptionResourceGroupName("dbdiskcopies", $secondary)
	$targetDiskName = $sourceDiskName + "-" + $ctx.GetDataPlatformResourcePostfix($secondary)

	Ensure-ResourceGroupWithName -ctx $ctx -secondary:$secondary -resourceGroupName $targetResourceGroupName

	$diskConfig = New-AzureRmDiskConfig -SourceResourceId $managedDisk.Id -Location $managedDisk.Location -CreateOption Copy 
	New-AzureRmDisk -Disk $diskConfig -DiskName $targetDiskName -ResourceGroupName $targetResourceGroupName

	Revert-Context -ctx $ctx
}
#>

function Deploy-StandaloneServerFromReferenceOsDisk{
	param(
		[Context]$ctx,
		[string]$vmSize = "Standard_B4ms",
		[string]$computerName = "www",
		[switch]$web,
		[switch]$db
	)

	Write-Host "In:  " $MyInvocation.MyCommand 

	if ($web -and $db){
		throw "Must select either web or db, not both"
	}

	if (!$web -and !$db){
		throw "Must select either web or db"
	}

	$resourceGroupName = $ctx.GetResourceGroupName("testwebimage", $secondary)

	$keyVaultName = $ctx.GetKeyVaultName($false)

	$parameters = $null
	if ($web){
		$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"
		$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey"

		$fileShareStorageAccountKey = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey"
		$octoApiKey                 = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoApiKey"
		$octoUrl                    = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoUrl"
		$webAdminUserName           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName"
		$webAdminPassword           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword"
		$webSslCertificateId        = Get-KeyVaultSecretId -KeyVaultName $keyVaultName -SecretName "WebSslCertificate"

		$fileStgAcctName = $ctx.GetStorageAccountName("files", $usage)
		$fileShareName = "workspace-file-storage"

		$parameters = @{
			"resourceNamePostfix" = "dd0p"
			"adminUserName" = $webAdminUserName
			"adminPassword" =$webAdminPassword
			"vmSize" = $vmSize
			"computerName" = $computerName
			"sslCertificateUrl" = $webSslCertificateId
			"fileShareKey" = $fileShareStorageAccountKey
			"fileStgAcctName" = $fileStgAcctName
			"fileShareName" = $fileShareName
			"octoUrl" = $octoUrl
			"octoApiKey" = $octoApiKey
			"octoEnvironment" = "WP0P"
		}
	}

	$template = "arm-deploy-web-from-osdisk.json"

	Ensure-ResourceGroup -ctx $ctx -category "testwebimage"
	Execute-Deployment -templateFile $template -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}
