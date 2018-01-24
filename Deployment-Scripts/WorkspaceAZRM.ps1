$currentDir = "D:\Workspace\Workspace"

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
			c = "Canary"
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
	<#
	static [string] GetenvironmentWithoutInstance($environment){
		return $environment.Substring(0, 1)
	}

	static [string] Getslot($environment){
		return $environment.Substring(1, 1)
	}
	#>
	static [string] GetFacilityLocation($facility){
		return [EnvironmentAndFacilitiesInfo]::facilitiesInfo['locationMap'][$facility]
	}

	static [string]GetPeerfacility($facility){
		return [EnvironmentAndFacilitiesInfo]::facilitiesInfo['peerFacilityMap'][$facility]
	}
}

$wsAcctInfo = @{
	"profileFile" = "workspace.json"
	"subscriptionName" = "WS Test"
	"subscription" = "w"
}

$mhAcctInfo = @{
	"profileFile" = "heydt.json"
	"subscriptionName" = "Visual Studio Enterprise"
	"subscription" = "mh"
}

$loginAccounts = @{
	$wsAcctInfo['subscription'] = $wsAcctInfo
	$mhAcctInfo['subscription'] = $mhAcctInfo
}

$loginAccount = $loginAccounts['w']

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
	[string]$sharedResourcePostfix
	[string]$sharedPeerResourcePostfix
	[string]$location
	[string]$peerLocation
	[string]$vnetCidrPrefix
	[string]$peerVnetCidrPrefix
	[object]$azureCtx
	[object]$azureSub

	
	Validate(){
		if ($this.azureCtx -eq $null) { throw "must have an azure context" }
		if ($this.azureSub -eq $null) { throw "must have an azure subscription" }
		if ($this.subscription -eq $null) { throw "subscription cannot be null" }
		if ($this.slot -eq $null) { throw "slot cannot be null" }
		if ($this.facility -eq $null) { throw "facility cannot be null" }
		if ($this.peerfacility -eq $null) { throw "peerfacility cannot be null" }
		if ($this.resourcePostfix -eq $null) { throw "resourcePostfix cannot be null" }
		if ($this.peerResourcePostfix -eq $null) { throw "peerResourcePostfix cannot be null" }
		if ($this.sharedResourcePostfix -eq $null) { throw "sharedResourcePostfix cannot be null" }
		if ($this.sharedPeerResourcePostfix -eq $null) { throw "sharedPeerResourcePostfix cannot be null" }
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

	[string] GetSharedResourceGroupName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.sharedResourcePostfix
		}
		else{
			$postfix = $this.sharedPeerResourcePostfix
		}
		return "rg-" + $resourceType + "-" + $postfix
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

	[string] GetSharedStorageAccountName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.sharedResourcePostfix
		}
		else{
			$postfix = $this.sharedPeerResourcePostfix
		}
		return "stg" + $resourceType + $postfix	
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
			return $this.sharedResourcePostfix
		}
		return $this.sharedPeerResourcePostfix
	}

	static [string] BuildSharedResourcePostfix([Context]$ctx, $usePeer){
		if (!$usePeer){
			return $ctx.subscription + "s0" + $ctx.facility
		}
		return $ctx.subscription + "s0" + $ctx.peerfacility
	}

	static [object] GetFacilityUsages($primary, $secondary){
		if (!$primary -and !$secondary){ return @($false, $true) }
		if ($primary -and $secondary){ return @($false, $true) }
		if ($primary -and !$secondary){ return @($false) }
		return @($true)
	}

	<#
	[string] Getslot(){
		return $this.environment.Substring(1, 1)
	}
	#>
	[string] GetKeyVaultName($usePeer){
		$keyVaultName = "kv-svc-" + $this.GetResourcePostfix($usePeer)
		return $keyVaultName
	}

	[string] GetEnvironment(){
		return $this.environment.Substring(0, 1)
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
		$ctx.sharedResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $false)
		$ctx.sharedPeerResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $true)
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

function Login-WorkspacePrimaryProd{
	param(
		[int]$instanceId = -1
	)
	# instance -1 means use the newest environment in azure
	# this will require a query of resources in azure
	# for now, this defaults to 0
	if ($instanceId -eq -1){
		$instanceId = 0
		}
	$ctx = Login-WorkspaceAzureAccount -environment "w" -slot 0 -facility "p" -subscription "w"
	return $ctx
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
	Write-Host "In: " $MyInvocation.MyCommand $environment $slot $facility $subscription

	$profileFile = $currentDir + "\Deployment-Scripts\" + $loginAccount['profileFile']

	Write-Host "Logging into azure account"
	$azureCtx = Import-AzureRmContext -Path $profileFile
	Write-Host "Successfully loaded the profile file: " $profileFile

	Try{
		Write-Host "Setting subscription..."
		$azureSub = Get-AzureRmsubscription �subscriptionName $loginAccount['subscriptionName'] | Select-AzureRmsubscription
		Write-Host "Set Azure subscription for session complete"
		Write-Host $azureSub.Name $azureSub.subscription

	}
	Catch{
		Write-Host "subscription set failed"
		Write-Host $_
	}

	$ctx = [Context]::new()
	$ctx.azureCtx = $azureCtx
	$ctx.azureSub = $azureSub
	$ctx.environment = $environment
	$ctx.slot = $slot
	$ctx.facility = $facility
	$ctx.peerfacility = [EnvironmentAndFacilitiesInfo]::GetPeerfacility($facility)
	$ctx.subscription = $subscription
	$ctx.resourcePostfix = [Context]::BuildResourcePostfix($ctx, $false)
	$ctx.peerResourcePostfix = [Context]::BuildResourcePostfix($ctx, $true)
	$ctx.sharedResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $false)
	$ctx.sharedPeerResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $true)
	$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facility)
	$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerfacility)
	$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environment, $ctx.slot, $ctx.facility)
	$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environment,$ctx.slot, $ctx.peerfacility)

	#Dump-Ctx $ctx
	#$ctx.Validate()

	Write-Host "Out: " $MyInvocation.MyCommand 

	return $ctx
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

<#
function Construct-ResourcePostfix{
	param(
		[Parameter(Mandatory=$true)]
		[string]$environment,
		[Parameter(Mandatory=$true)]
		[string]$facility,
		[Parameter(Mandatory=$true)]
		[string]$subscription
	)

	return $subscription + $environment + $facility
}

function Get-FacilityLocation{
	param(
		[Parameter(Mandatory=$true)]
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $facility

	if (!$facilitiesLocationMap.ContainsKey($facility)){
		throw "Facility not found: " + $facility
	}

	Write-Host "Out: " $MyInvocation.MyCommand $facility

	return $facilitiesLocationMap[$facility]
}

function Create-ResourceGroup{
	param(
		[Parameter(Mandatory=$true)]
		[string]$environment,
		[Parameter(Mandatory=$true)]
		[string]$facility,
		[Parameter(Mandatory=$true)]
		[string]$resourceCategory
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $resourceCategory

	$resourceGroupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory $resourceCategory
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	Write-Host "Out: " $MyInvocation.MyCommand $resourceGroupName
}
#>
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
		New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
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
		[hashtable]$parameters
	)
	Write-Host "In: " $MyInvocation.MyCommand $templateFile $resourceGroupName

	#Ensure-LoggedIntoAzureAccount -ctx $ctx

	Write-Host "Executing template deployment: " $resourceGroupName $templateFile
	#Dump-Hash $parameters

	#$templateFile = $currentDir + "\Deployment-Scripts\ARM\" + $templateFile
	Write-Host "Using template file: " $templateFile

	$items = Get-ChildItem -Path $currentDir -Include $templateFile -Recurse
	if ($items -eq $null) { throw "Could not find template: " + $templateFile}
	$fullTemplateFileName = $items[0]
	
	$name = ((Get-ChildItem $fullTemplateFileName).BaseName + '-' + $resourceGroupName + "-" + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))
	Write-Host "Deployment name: " $name
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
		[string]$loginPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey $dbAdminUserName

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

	$resourceGroupName = $ctx.GetResourceGroupName("db", $secondary)
	Execute-Deployment -templateFile "arm-db-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-Web{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
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
		[int]$scaleSetCapacity = 2
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "web" -secondary:$secondary

	$parameters = $ctx.GetTags($secondary, "WEB")
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
	$parameters["vmSku"] = "Standard_DS1_v2"
	$parameters["scaleSetCapacity"] = $scaleSetCapacity

	$resourceGroupName = $ctx.GetResourceGroupName("web", $secondary) 
	Execute-Deployment -templateFile "arm-vmssweb-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

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


function Check-IfDatabaseDiskIsPresent{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary
	)

	Ensure-LoggedIntoAzureAccount -ctx $ctx
	$diskname = "data1-sql1-db-" + $ctx.GetResourcePostfix($secondary) # wsp0d
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
		[string]$diskNamePrefix,
		[int]$sizeInGB,
		[string]$accountType="StandardLRS"
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $sizeInGB $accountType

	$diskName = $diskNamePrefix + "-" + $ctx.GetResourcePostfix($usage)
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

	$diskPresent = Check-IfDatabaseDiskIsPresent -ctx $ctx -secondary:$secondary 
	if (!$diskPresent){
		Write-Host "Disk did not exist - Creating"
		#Deploy-DatabaseDiskViaInitVM -ctx $ctx -secondary:$secondary
		Create-Disk -ctx $ctx -secondary:$secondary -sizeInGB $sizeInGB -diskNamePrefix $diskNamePrefix -accountType $accountType
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

	$diskName = $diskNamePrefix + "-" + $ctx.GetResourcePostfix($usage)
	$virtualMachineName = $vmNamePrefix + "-" + $ctx.GetEnvironment($usage)
	$vmResourceGroupName = $ctx.GetResourceGroupName("db", $secondary)
	$virtualMachine = Get-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $virtualMachineName

	Write-Host "Attempting to remove disk:" $diskName $virtualMachineName
	Remove-AzureRmVMDataDisk -VM $virtualMachine -Name $diskName
	Write-Host "Updating VM:"$vmResourceGroupName $virtualMachineName
	Update-AzureRmVM -ResourceGroupName $vmResourceGroupName -VM $virtualMachine

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Deploy-DatabaseDiskViaInitVM{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary,
		[string]$databaseServerId="sql1",
		[string]$diskName="data1",
		[string]$dataDiskSku="Standard_LRS",
		[int]$dataDiskSizeInGB=64,
		[string]$adminUserName="wsadmin",
		[string]$adminPassword="Workspace!DbDiskInit!2018",
		[switch]$onlyIfDiskNotAvailable
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	if ($onlyIfDiskNotAvailable){
		$diskIsAvailable = Check-IfDatabaseDiskIsPresent -ctx $ctx -secondary:$secondary
		if ($diskIsAvailable) { return }
	}

	Ensure-ResourceGroup -ctx $ctx -category "dbdi" -secondary:$secondary
	Ensure-ResourceGroup -ctx $ctx -category "disks" -secondary:$secondary

	$diskResourceGroupName = $ctx.GetResourceGroupName("disks", $secondary)

	$parameters = @{
		"resourceNamePostfix" = $ctx.GetResourcePostfix($secondary)
		"diskResourceGroupName" = $diskResourceGroupName
		"diskName" = $diskName
		"dataDiskSku" = $dataDiskSku
		"dataDiskSizeInGB" = $dataDiskSizeInGB
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"databaseServerId" = $databaseServerId
	}

	$deployResourceGroupName = $ctx.GetResourceGroupName("dbdi", $secondary)
	$deploymentName = Execute-Deployment -templateFile "arm-db-disk-init-vm-deploy.json" -resourceGroup $deployResourceGroupName -parameters $parameters

	$deployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $deployResourceGroupName -Name $deploymentName
	$outputs = $deployment.Outputs

	$vmName = $outputs["vmName"].Value
	$dataDiskName = $outputs["dataDiskName"].Value
	$VirtualMachine = Get-AzureRmVM -ResourceGroupName $deployResourceGroupName -Name $vmName
	Remove-AzureRmVMDataDisk -VM $VirtualMachine -Name $dataDiskName
	Update-AzureRmVM -ResourceGroupName $deployResourceGroupName -VM $VirtualMachine

	Remove-AzureRmResourceGroup -Name $deployResourceGroupName -Force | Out-Null

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)
}

function Create-KeyVault{
	param(
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "svc" -secondary:$secondary

	$resourcePostfix = $ctx.GetResourcePostfix($secondary)

	$keyVaultName = "kv-svc-" + $resourcePostfix

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $secondary)
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
	$secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText �Force
	$secretContentType = 'application/x-pkcs12'

	Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secret -ContentType $secretContentType -ErrorAction Stop

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
	$octoUrl = "http://pip-octo-wp0p.westus.cloudapp.azure.com" 

	$octoApiKey = "API-THVVH8LYEZOHYUCI7J6JESNXW"
	$dataDogApiKey = "5ecc232442a6fa39de3c1b5f189e135d"
	$pfxfile = "workspace.pfx"
	$pfxfilePassword = "workspace"

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $secondary)
	$resourcePostfix = $ctx.GetResourcePostfix($secondary)
	$keyVaultName = "kv-svc-" + $resourcePostfix

	Add-LocalCertificateToKV -keyVaultName $keyVaultName -pfxFile $pfxfile -password $pfxfilePassword -secretName $webSslCertificateSecretName
	
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword" -SecretValue "Workspace!Web!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminPassword" -SecretValue "Workspace!Ftp!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword" -SecretValue "Workspace!Db!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminPassword" -SecretValue "Workspace!Jump!2018"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminPassword" -SecretValue "Workspace!Admin!2018"

	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName" -SecretValue "wsadmin"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword" -SecretValue "Workspace!DB!2017"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName" -SecretValue "wsapp"
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword" -SecretValue "Workspace!DB!2017"
	
	$diagAcctResourceGroupName = $ctx.GetResourceGroupName("diag", $secondary)
	$diagStorageAccountName = $ctx.GetStorageAccountName("diag", $secondary)
	$diagStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $diagAcctResourceGroupName -AccountName $diagStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey" -SecretValue $diagStgAcctKeys.Value[0]

	$installersAcctResourceGroupName = $ctx.GetSharedResourceGroupName("installers", $secondary)
	$installersStorageAccountName = $ctx.GetSharedStorageAccountName("installers", $secondary)
	$installersStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $installersAcctResourceGroupName -AccountName $installersStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey" -SecretValue $installersStgAcctKeys.Value[0]

	$fileShareAcctResourceGroupName = $ctx.GetResourceGroupName("files", $secondary)
	$fileShareStorageAccountName = $ctx.GetStorageAccountName("files", $secondary)
	$fileShareStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $fileShareAcctResourceGroupName -AccountName $fileShareStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey" -SecretValue $fileShareStgAcctKeys.Value[0]

	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoUrl" -SecretValue $octoUrl
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoApiKey" -SecretValue $octoApiKey
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey" -SecretValue $dataDogApiKey

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
			#Write-Host $jobs.State
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
				Write-Host $data
			}
		}

		Write-Host "Checking jobs again a 5 seconds" $jobs.Name
		Wait-Job -Job $jobs -Timeout 5
	}
	
	Write-Host "Jobs ended" $jobs.Name

	foreach ($job in $jobs){
		if ($job.HasMoreData){
			$data = Receive-Job $job
			Write-Host $data
		}
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
		[bool]$includeServices,
		[string]$category,
		[string]$name,
		[scriptblock]$scriptToRun
	)

	Write-Host "====>" $environment $facility $subscription $usage $includeServices $category

	$arguments = New-Object System.Collections.ArrayList
	$arguments.Add($ctx.environment) | Out-Null
	$arguments.Add($ctx.slot) | Out-Null
	$arguments.Add($ctx.facility) | Out-Null
	$arguments.Add($ctx.subscription) | Out-Null
	$arguments.Add($usage) | Out-Null
	$arguments.Add($includeServices) | Out-Null
	$arguments.Add($category) | Out-Null

	$preamble = {
		param(
			[string]$environment, 
			[string]$slot,
			[string]$facility, 
			[string]$subscription, 
			[bool]$usage,
			[bool]$includeServices,
			[string]$category
		)
		. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
		$newctx = Login-WorkspaceAzureAccount -environment $environment -slot $slot -facility $facility -subscription $subscription
	}

	$scriptBlock = [scriptblock]::Create($preamble.ToString() + " " + $scriptToRun.ToString())

	$jobName = $name
	if ($jobName -eq $null){
		$jobName = $((Get-PSCallStack)[1].Command) + "-" + $ctx.GetResourcePostfix($usage)
	}

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
		[switch]$computeOnly,
		[array]$computeElements=@("db", "web", "ftp", "jump", "ftp", "admin")
	)
	
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true)

	Dump-Ctx $ctx

	$facilities = [Context]::GetFacilityUsages($primary, $secondary)
	Ensure-LoggedIntoAzureAccount -ctx $ctx
	
	$jobs = New-Object System.Collections.ArrayList
	if (!$computeOnly){
		if (!$excludeNetwork -and !$vpnOnly){
			foreach ($usage in $facilities){

				$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
				    	-usage $usage `
						-name $("Deploy-VNET-" + $ctx.GetResourcePostfix($usage)) `
						-scriptToRun {
		 					Deploy-VNet -ctx $newctx -secondary:$usage
						}
				$jobs.Add($job) | Out-Null
			}

			Wait-ForJobsToComplete $jobs
		}     
	}

	if ($networkOnly) { return }

	$jobs.Clear()

	if ($vpnOnly -and !$excludeVPN -and !$computeOnly -and !$excludeNetwork){

		if (!$excludeNetwork -and !$excludeVPN -or $vpnOnly){
				$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
				    	-usage $usage `
						-name $("Deploy-VNET-" + $ctx.GetResourcePostfix($usage)) `
						-scriptToRun {
							Deploy-VPN -ctx $new ctx
						}
				$jobs.Add($job) | Out-Null
		}
	}


	if ("db" -in $computeElements){
		foreach ($usage in $facilities){

			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
								   -usage $usage `
								   -name $("Deploy-DB-" + $ctx.GetResourcePostfix($usage)) `
								   -scriptToRun {
 									    Write-Host "Starting Deploy-DB subtask"
										Ensure-DiskPresent -ctx $newctx -secondary:$usage -diskNamePrefix  "data1-sql1" -sizeInGB 64
										Ensure-DiskPresent -ctx $newctx -secondary:$usage -diskNamePrefix  "init1-sql1" -sizeInGB 64
									   
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
									   
										Deploy-DB -ctx $newctx -secondary:$usage `
												  -diagnosticStorageAccountKey $diagStorageAccountKey `
												  -dataDogApiKey $dataDogApiKey `
												  -installersStgAcctKey $installersStorageAccountKey -installersStgAcctName $installersStorageAccountName `
												  -adminUserName $dbAdminUserName -adminPassword $dbAdminPassword `
												  -saUserName $dbSaUserName -saPassword $dbSaPassword `
												  -loginUserName $dbLoginUserName -loginPassword $dbLoginPassword 

									    Delete-DiskFromVM -ctx $ctx -secondary:$secondary -diskNamePrefix "init1-db1" -vmNamePrefix "db1-db"

 									    Write-Host "Ending Deploy-DB subtask"
									}
			$jobs.Add($job)
		}
	}

	if ("web" -in $computeElements){
		$fileShareName = "workspace-file-storage"

		foreach ($usage in $facilities){

			$job = Start-ScriptJob -environment $ctx.environment -slot $ctx.slot -facility $ctx.facility -subscription $ctx.subscription `
						-usage $usage `
						-name $("Deploy-WEB-" + $ctx.GetResourcePostfix($usage)) `
						-scriptToRun {
							$keyVaultName = $newctx.GetKeyVaultName($usage)

							$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey"
							$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey"
							$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey"

							$fileShareStorageAccountKey = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey"
							$octoApiKey                 = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoApiKey"
							$octoUrl                    = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoUrl"
							$webAdminUserName           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName"
							$webAdminPassword           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword"
							$webSslCertificateId        = Get-KeyVaultSecretId -KeyVaultName $keyVaultName -SecretName "WebSslCertificate"

							$fileStgAcctName = $newctx.GetStorageAccountName("files", $usage)
							$fileShareName = "workspace-file-storage"

							Write-Host "Using octourl:" $octoUrl

							Deploy-Web -ctx $newctx -secondary:$usage `
									   -diagnosticStorageAccountKey $diagStorageAccountKey `
									   -dataDogApiKey $dataDogApiKey `
									   -scaleSetCapacity $using:webScaleSetSize `
									   -adminUserName $webAdminUserName -adminPassword $webAdminPassword -sslCertificateUrl $webSslCertificateId `
									   -octoUrl $octoUrl -octoApiKey $octoApiKey `
									   -fileShareKey $fileShareStorageAccountKey -fileStgAcctName $fileStgAcctName -fileShareName $fileShareName
						}
			$jobs.Add($job)
		}
	}

	if ("ftp" -in $computeElements){
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
			$jobs.Add($job)
		}
	}

	if ("jump" -in $computeElements){
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
			$jobs.Add($job)
		}
	}

	if ("admin" -in $computeElements){
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
			$jobs.Add($job)
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

function Create-All{
	param(
		[Context]$ctx
	)

	Create-Base -ctx $ctx
	Create-Core -ctx $ctx
}

function Teardown-Core{
	param(
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeServices
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.environment $ctx.facility $ctx.subscription $primary $secondary $includeServices

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$jobs = New-Object System.Collections.ArrayList
	$usages = [Context]::GetFacilityUsages($primary, $secondary)

	foreach ($usage in $usages){
		$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
			    		       -usage $usage -includeServices:$includeServices `
							   -name $("TeardownCE-" + $ctx.GetResourcePostfix($usage)) `
 						       -scriptToRun {
								   Teardown-CoreEntities -ctx $newctx -secondary:$usage -includeServices:$includeServices 
							   }
		$jobs.Add($job) | Out-Null
	}
	
	write-Host $MyInvocation.MyCommand "waiting for" $jobs.Count "jobs"
	Wait-ForJobsToComplete $jobs

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true)
}

function Teardown-Base{
	param(
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeFiles
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.environment $ctx.facility $ctx.subscription $primary $secondary $includeServices $includeFiles

	$jobs = New-Object System.Collections.ArrayList
	$usages = [Context]::GetFacilityUsages($primary, $secondary)

	foreach ($usage in $usages){
		Teardown-DiagnosticsEntities -ctx $ctx -secondary:$usage
		if ($includeFiles -or $all) { Teardown-AzureFilesEntities -ctx $ctx -secondary:$usage }
	}

	Write-Host "Out: " $MyInvocation.MyCommand
}
function Teardown-All{
	param(
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary,
		[switch]$includeDatabaseDisk=$false
	)

	$jobs = New-Object System.Collections.ArrayList
	$usages = [Context]::GetFacilityUsages($primary, $secondary)

	foreach ($usage in $usages){
		Teardown-Base -ctx $ctx -secondary:$usage  
		Teardown-Core -ctx $ctx -secondary:$usage 

		# has to be done afer core, and technically after the database is downed
		if ($includeDatabaseDisk) { Teardown-DatabaseDisk -ctx $ctx -secondary:$usage }
	}
}

function Teardown-CoreEntities{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[switch]$includeServices
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.environment $ctx.facility $ctx.subscription $secondary $includeServices

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	if ($includeServices){
		$group2 = @("svc")
	}
	else
	{
		$group2 = @()
	}

	$group1 = @("admin", "jump", "ftp", "web", "db")
	Write-Host $group1.Count

	$group3 = @("vnet")
	$groups = $group1, $group2, $group3

	foreach ($group in $groups){
		$jobs = New-Object System.Collections.ArrayList
		foreach ($category in $group){
			Write-Host "Category:" $category
			$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
				    				-usage $secondary -includeServices:$includeServices `
									-name $("Teardown-CoreEntities" + "-" + $ctx.GetResourcePostfix($usage) + "-" + $category) `
									-category $category `
									-scriptToRun {
										Teardown-ResourceCategory -ctx $newctx -secondary:$usage -category $category
									}
			Write-Host "Adding job to queue"
			$jobs.Add($job) | Out-Null
			Write-Host "added job"
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

	$location = $ctx.GetLocation($secondary)

	foreach ($rc in $resourceCategories){
		$resourceGroupName = $ctx.GetResourceGroupName($rc, $secondary)
		$storageAccountName = $ctx.GetStorageAccountName($rc, $secondary)
		Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category $rc
		Ensure-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	}

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
<#
function Create-ServicesEntities{
	param(
		[Context]$ctx,
		[match]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "svc" -secondary:$secondary

	Deploy-ServicesVnetEntities -ctx $ctx -secondary:$secondary
	Build-KeyVault -ctx $ctx -secondar:$secondary

	Write-Host "Out: " $MyInvocation.MyCommand 
}
#>
function Create-Base{
	param(
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $primary $secondary

	$usages = [Context]::GetFacilityUsages($primary, $secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	foreach ($usage in $usages){
		Create-BaseEntities -ctx $ctx -secondary:$usage
	}

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Create-BaseEntities{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Create-DiagnosticsEntities   -ctx $ctx -secondary:$secondary
	Create-AzureFilesEntities    -ctx $ctx -secondary:$secondary
	Build-KeyVault               -ctx $ctx -secondary:$secondary
	Deploy-DatabaseDiskViaInitVM -ctx $ctx -secondary:$secondary -onlyIfDiskNotAvailable
	#Create-ServicesEntities      -ctx $ctx -secondary:$secondary

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
	$resourceGroupName = $ctx.GetResourceGroupName("files", $secondary)
	$storageAccountName = $ctx.GetStorageAccountName("files", $secondary)

	Ensure-ResourceGroup -ctx $ctx -category "files" -secondary:$secondary
	Ensure-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	Create-AzureFilesShare -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

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
		[string]$resourceGroupName,
		[string]$storageAccountName
	)
	Write-Host "In: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-StorageAccount  -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

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
		$($env + "0-vnet-" + $postfix) = $false
		$($env + "1-vnet-" + $postfix) = $false
		$($env + "2-vnet-" + $postfix) = $false
		$($env + "3-vnet-" + $postfix) = $false
		$($env + "4-vnet-" + $postfix) = $false
		$($env + "5-vnet-" + $postfix) = $false
		$($env + "6-vnet-" + $postfix) = $false
		$($env + "7-vnet-" + $postfix) = $false
	}

	$vnetNames = Get-AzureRmVirtualNetwork | Where-Object {$_.Name.EndsWith($postfix)} | Select-Object -Property Name -ExpandProperty Name

	$vnetNames | ForEach-Object -Process { $utilized[$_] = $true }
	$utilized | Where-Object {$_.Value}

	$free = $utilized.GetEnumerator() | Where-Object { !$_.Value } | Select-Object -ExpandProperty Name

	$next = $free | Sort-Object | Select-Object -First 1
	$next.split('-')[0][1]
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
		[int]$ftpScaleSetSize=2
	)

	Write-Host "Starting deploy of next environment" $ctx.environment $ctx.facility $ctx.subscription $primary $secondary $includeBase

	$instanceId = Find-OpenDeploymentSlotNumber $ctx

	Write-Host "Next environment slot is: " $instanceId

	$newCtx = Create-NextEnvironmentSlotContext -ctx $ctx -instanceId $instanceId

	if ($includeBase) { Create-Base -ctx $newCtx }
	Create-Core -ctx $newCtx -primary:$primary -secondary:$secondary -webScaleSetSize $webScaleSetSize -ftpScaleSetSize $ftpScaleSetSize

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
		[switch]$secondar
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
