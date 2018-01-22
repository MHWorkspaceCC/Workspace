$currentDir = "D:\Workspace\Workspace"

$facilitiesLocationMap = @{
	"p" = "westus"
	"d" = "eastus"
}

$locationPostfixMap = @{
	"primary" = "pr"
	"dr" = "dr"
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

	static [string] CalculateVnetCidrPrefix($envCode, $facCode){
		if ($envCode.Length -ne 2){
			throw "Environment code length must be two characters"
		}
		$code = $envCode.Substring(0,1)
		if (![EnvironmentAndFacilitiesInfo]::environmentsInfo['validCodes'] -contains $code){
			throw "Invalid environment code.  Must be one of: " + [EnvironmentAndFacilitiesInfo]::environmentsInfo['validCodes']
		}
		
		$instanceNumber = $envCode.Substring(1, 1)
		if (![EnvironmentAndFacilitiesInfo]::environmentsInfo['validCodes'] -contains $instanceNumber){
			throw "Instance number must be in" + [EnvironmentAndFacilitiesInfo]::environmentsInfo['validCodes'] + ".  Given was: " + $instanceNumber
		}

		$cidr1 = [EnvironmentAndFacilitiesInfo]::environmentsInfo['cidrValues'][$code] 
		$cidr2 = [int]$instanceNumber
		$cidr3 = [EnvironmentAndFacilitiesInfo]::facilitiesInfo['cidrValues'][$facCode]
		$cidrValue = ($cidr1 -shl 5) + ($cidr2 -shl 2) + $cidr3

		return "10." + ("{0}" -f $cidrValue) + "."
	}

	static [string] GetEnvironmentCodeWithoutInstance($environmentCode){
		return $environmentCode.Substring(0, 1)
	}

	static [string] GetEnvironmentInstance($environmentCode){
		return $environmentCode.Substring(1, 1)
	}

	static [string] GetFacilityLocation($facilityCode){
		return [EnvironmentAndFacilitiesInfo]::facilitiesInfo['locationMap'][$facilityCode]
	}

	static [string]GetPeerFacilityCode($facilityCode){
		return [EnvironmentAndFacilitiesInfo]::facilitiesInfo['peerFacilityMap'][$facilityCode]
	}
}

$wsAcctInfo = @{
	"profileFile" = "workspace.json"
	"subscriptionName" = "WS Test"
	"subscriptionCode" = "ws"
}

$mhAcctInfo = @{
	"profileFile" = "heydt.json"
	"subscriptionName" = "Visual Studio Enterprise"
	"subscriptionCode" = "mh"
}

$loginAccounts = @{
	$wsAcctInfo['subscriptionCode'] = $wsAcctInfo
	$mhAcctInfo['subscriptionCode'] = $mhAcctInfo
}

$loginAccount = $loginAccounts['ws']

$fileSharesName = "workspace-file-storage"
$fileSharesQuota = 512

Class Context{
	[string]$environmentCode
	[string]$facilityCode
	[string]$environment
	[string]$environmentInstance
	[string]$subscriptionCode
	[string]$peerFacilityCode
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
		if ($this.environmentInstance -eq $null) { throw "environmentInstance cannot be null" }
		if ($this.environmentCode -eq $null) { throw "environmentCode cannot be null" }
		if ($this.facilityCode -eq $null) { throw "facilityCode cannot be null" }
		if ($this.subscriptionCode -eq $null) { throw "subscriptionCode cannot be null" }
		if ($this.peerFacilityCode -eq $null) { throw "peerFacilityCode cannot be null" }
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
			return $ctx.subscriptionCode + $ctx.environmentCode + $ctx.facilityCode
		}
		return $ctx.subscriptionCode + $ctx.environmentCode + $ctx.peerFacilityCode
	}

	[string] GetVnetCidrPrefix($usePeer = $false){
		if (!$usePeer){
			return $this.vnetCidrPrefix
		}
		return $this.peerVnetCidrPrefix
	}

	[string] GetFacilityCode($usePeer = $false){
		if (!$usePeer){
			return $this.facilityCode
		}
		return $this.peerFacilityCode
	}

	[string] GetSharedResourcePostfix($usePeer = $false){
		if (!$usePeer){
			return $this.sharedResourcePostfix
		}
		return $this.sharedPeerResourcePostfix
	}

	static [string] BuildSharedResourcePostfix([Context]$ctx, $usePeer){
		if (!$usePeer){
			return $ctx.subscriptionCode + "s0" + $ctx.facilityCode
		}
		return $ctx.subscriptionCode + "s0" + $ctx.peerFacilityCode
	}

	static [object] GetFacilityUsages($usePeer, $multiFacility){
		if ($multiFacility){ return @($false, $true) }
		return @($usePeer)
	}

	static [object] GetFacilityUsages2($primary, $secondary){
		if (!$primary -and !$secondary){ return @($false, $true) }
		if ($primary -and $secondary){ return @($false, $true) }
		if ($primary -and !$secondary){ return @($false) }
		return @($true)
	}

	[string] GetEnvironmentInstance(){
		return $this.environmentCode.Substring(1, 1)
	}

	[string] GetKeyVaultName($usePeer){
		$keyVaultName = "kv-svc-" + $this.GetResourcePostfix($usePeer)
		return $keyVaultName
	}

	[string] GetEnvironment(){
		return $this.environmentCode.Substring(0, 1)
	}

	static [Context]newEnvironmentContextFrom($fromCtx, $environment, $instanceId){
		$ctx = [Context]::new()
		$ctx.azureCtx = $fromCtx.azureCtx
		$ctx.azureSub = $fromCtx.azureSub
		$ctx.environment = $environment
		$ctx.environmentInstance = $instanceId
		$ctx.environmentCode = $environment + $instanceId
		$ctx.facilityCode = $fromCtx.facilityCode
		$ctx.peerFacilityCode = [EnvironmentAndFacilitiesInfo]::GetPeerFacilityCode($ctx.facilityCode)
		$ctx.subscriptionCode = $fromCtx.subscriptionCode
		$ctx.resourcePostfix = [Context]::BuildResourcePostfix($ctx, $false)
		$ctx.peerResourcePostfix = [Context]::BuildResourcePostfix($ctx, $true)
		$ctx.sharedResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $false)
		$ctx.sharedPeerResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $true)
		$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facilityCode)
		$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerFacilityCode)
		$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.facilityCode)
		$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.peerFacilityCode)

		return $ctx
	}

	[HashTable] GetTags($secondary, $role){
		return @{
			"environmentCode" = $this.environmentCode
			"environment" = $this.GetEnvironment()
			"instance" = $this.environmentInstance
			"facility" = $this.GetFacilityCode($secondary)
			"subscriptionCode" = $this.subscriptionCode
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
	$ctx = Login-WorkspaceAzureAccount -environmentCode $("p" + {0} -f $instanceId) -facilityCode "p" -subscriptionCode "ws"
	return $ctx
}

function Login-WorkspaceAzureAccount{
	param(
		[Parameter(Mandatory=$true)]
		[string]$environmentCode,
		[Parameter(Mandatory=$true)]
		[string]$facilityCode,
		[Parameter(Mandatory=$true)]
		[string]$subscriptionCode
	)
	Write-Host "In: " $MyInvocation.MyCommand $environmentCode $facilityCode $subscriptionCode

	$profileFile = $currentDir + "\Deployment-Scripts\" + $loginAccount['profileFile']

	Write-Host "Logging into azure account"
	$azureCtx = Import-AzureRmContext -Path $profileFile
	Write-Host "Successfully loaded the profile file: " $profileFile

	Try{
		Write-Host "Setting subscription..."
		$azureSub = Get-AzureRmSubscription –SubscriptionName $loginAccount['subscriptionName'] | Select-AzureRmSubscription
		Write-Host "Set Azure Subscription for session complete"
		Write-Host $azureSub.Name $azureSub.Subscription

	}
	Catch{
		Write-Host "Subscription set failed"
		Write-Host $_
	}

	$ctx = [Context]::new()
	$ctx.azureCtx = $azureCtx
	$ctx.azureSub = $azureSub
	$ctx.environmentCode = $environmentCode
	$ctx.environment = $ctx.GetEnvironment()
	$ctx.environmentInstance = $ctx.GetEnvironmentInstance()
	$ctx.facilityCode = $facilityCode
	$ctx.peerFacilityCode = [EnvironmentAndFacilitiesInfo]::GetPeerFacilityCode($facilityCode)
	$ctx.subscriptionCode = $subscriptionCode
	$ctx.resourcePostfix = [Context]::BuildResourcePostfix($ctx, $false)
	$ctx.peerResourcePostfix = [Context]::BuildResourcePostfix($ctx, $true)
	$ctx.sharedResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $false)
	$ctx.sharedPeerResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $true)
	$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facilityCode)
	$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerFacilityCode)
	$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.facilityCode)
	$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.peerFacilityCode)

	Dump-Ctx $ctx
	$ctx.Validate()

	Write-Host "Out: " $MyInvocation.MyCommand $environmentCode $facilityCode $subscriptionCode

	return $ctx
}

function Dump-Ctx{
	param(
		[Parameter(Mandatory=$true)]
		[Context] $ctx
	)
	<#
	Write-Host 'environmentCode:' $ctx.environmentCode
	Write-Host 'environment:' $ctx.environment
	Write-Host 'environmentInstance:' $ctx.environmentInstance
	Write-Host 'facilityCode:' $ctx.facilityCode
	Write-Host 'peerFacilityCode:' $ctx.peerFacilityCode
	Write-Host 'subscriptionCode:' $ctx.subscriptionCode
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
		$ctx2 = Login-WorkspaceAzureAccount -environmentCode $ctx.environmentCode -facilityCode $ctx.facilityCode -subscriptionCode $ctx.subscriptionCode
		$ctx.azureCtx = $ctx2.azureCtx
		$ctx.azureSub = $ctx2.azureSub
	}
}


function Construct-ResourcePostfix{
	param(
		[Parameter(Mandatory=$true)]
		[string]$environmentCode,
		[Parameter(Mandatory=$true)]
		[string]$facilityCode,
		[Parameter(Mandatory=$true)]
		[string]$subscriptionCode
	)

	return $subscriptionCode + $environmentCode + $facilityCode
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

	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment
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

	Write-Host "Out: " $MyInvocation.MyCommand $templateFile $resourceGroupName

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

	Write-Host "Out: " $MyInvocation.MyCommand $facility $resourceGroupName $storageAccountName
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


	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment $storageAccountName
}

function Deploy-VNet{
	param(
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $ctx.facilityCode $secondary

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "vnet"

	$parameters = $ctx.GetTags($secondary, "VNET")
	$parameters["vnetName"] = $ctx.environmentCode
	$parameters["vnetCidrPrefix"] = $ctx.GetVnetCidrPrefix($secondary)

	$resourceGroupName = $ctx.GetResourceGroupName("vnet", $secondary)
	Execute-Deployment -templateFile "arm-vnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand 
}
<#
function Deploy-PIPs {
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "pips"

	$parameters = $ctx.GetTags($secondary, "PIPS")
	$parameters["vnetCidrPrefix"] = $ctx.GetVnetCidrPrefix($secondary)

	$resourceGroupName = $ctx.GetResourceGroupName("pips", $secondary)
	Execute-Deployment -templateFile "arm-pips-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)
}

function Deploy-NSGs {
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[switch]$secondary
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

 	Ensure-ResourceGroup -ctx $ctx -secondary:$secondary -category "nsgs"

	$parameters = $ctx.GetTags($secondary, "NSG")
	$parameters["vnetCidrPrefix"] = $ctx.GetVnetCidrPrefix($secondary)
	$parameters["resourceNamePostfix"] = $ctx.GetResourcePostfix($secondary)

	$resourceGroupName = $ctx.GetResourceGroupName("nsgs", $secondary)
	Execute-Deployment -templateFile "arm-nsgs-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)
}
#>
function Deploy-VPN{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "vnet"

	$parameters = $ctx.GetTags($false, "VNET")
	$parameters["peerFacility"] = $ctx.peerFacilityCode
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
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) $diagnosticStorageAccountKey $dataDogApiKey

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "jump" -secondary:$secondary

	$parameters = $ctx.GetTags($secondary, "JUMP")
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
	$parameters["dataDogApiKey"] = $dataDogApiKey
	$parameters["adminUserName"] = $adminUserName
	$parameters["adminPassword"] = $adminPassword

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

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)
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
		[string]$adminPassword="Workspace!DbDiskInit!2018"
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

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
<#
function Get-KeyVault{
	param(
		[string]$facility,
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	$resourcePostfix = $ctx.GetResourcePostfix("svc", $usePeer)
	$keyVaultName = "kv-svc-" + $resourcePostfix

	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility
	return $keyVault
}
#>
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

<#
function Add-WebSslSelfSignedCertToKeyVault{
	param(
		[string]$facility,
		[string]$environment,
		[string]$certName
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $certName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$keyVaultName = "kv-svc-" + $resourcePostfix

	Write-Host "Creatting certificate policy"
	$policy = New-AzureKeyVaultCertificatePolicy -SubjectName "CN=www.workspace.ccc" -IssuerName Self -SecretContentType "application/x-pkcs12" -ValidityInMonths 12

	Write-Host "Adding certificate"
	$certificateOperation = Add-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certName -CertificatePolicy $policy
	
	$enabled = $false
	while (!$enabled){
		$certificate = Get-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certName 
		$enabled = $certificate.Enabled
		if (!$enabled){
			Write-Host "Waiting for certificate to be available"
			Start-Sleep -m 500
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $certName

	return $certificate
}

function Add-WebSslCertToKeyVault{
	param(
		[string]$facility,
		[string]$environment,
		[string]$certName
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $certName

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$keyVaultName = "kv-svc-" + $resourcePostfix

	Write-Host "Creatting certificate policy"
	$policy = New-AzureKeyVaultCertificatePolicy -SubjectName "CN=www.workspace.ccc" -IssuerName Self -SecretContentType "application/x-pkcs12" -ValidityInMonths 12

	Write-Host "Adding certificate"
	$certificateOperation = Add-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certName -CertificatePolicy $policy
	
	$enabled = $false
	while (!$enabled){
		$certificate = Get-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certName 
		$enabled = $certificate.Enabled
		if (!$enabled){
			Write-Host "Waiting for certificate to be available"
			Start-Sleep -m 500
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $certName

	return $certificate
}
#>

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
	$secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText –Force
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
	$octoUrl = "http://pip-octo-" + $postfix + "." + $region + ".cloudapp.azure.com" 

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
		[string]$environmentCode, 
		[string]$facilityCode, 
		[string]$subscriptionCode, 
		[bool]$usage,
		[bool]$includeServices,
		[string]$category,
		[string]$name,
		[scriptblock]$scriptToRun
	)

	Write-Host "====>" $environmentCode $facilityCode $subscriptionCode $usage $includeServices $category

	$arguments = New-Object System.Collections.ArrayList
	$arguments.Add($ctx.environmentCode) | Out-Null
	$arguments.Add($ctx.facilityCode) | Out-Null
	$arguments.Add($ctx.subscriptionCode) | Out-Null
	$arguments.Add($usage) | Out-Null
	$arguments.Add($includeServices) | Out-Null
	$arguments.Add($category) | Out-Null

	$preamble = {
		param(
			[string]$environmentCode, 
			[string]$facilityCode, 
			[string]$subscriptionCode, 
			[bool]$usage,
			[bool]$includeServices,
			[string]$category
		)
		. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
		$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
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

	$facilities = [Context]::GetFacilityUsages2($primary, $secondary)
	Ensure-LoggedIntoAzureAccount -ctx $ctx
	
	$jobs = New-Object System.Collections.ArrayList
	if (!$computeOnly){
		if (!$excludeNetwork -and !$vpnOnly){
			foreach ($usage in $facilities){

				$job = Start-ScriptJob -environmentCode $ctx.environmentCode -facilityCode $ctx.facilityCode -subscriptionCode $ctx.subscriptionCode `
				    	-usage $usage `
						-scriptToRun {
		 					Deploy-VNet -ctx $newctx -secondary:$usage
						}
<#
				$job = Start-Job -Name $("Deploy-VNet-" + $ctx.GetResourcePostfix($usage)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode,$usage -ScriptBlock {
					param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode, [switch]$secondary)
					Write-Host $environmentCode, $facilityCode, $subscriptionCode, $secondary
					. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
					$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
					Deploy-VNet -ctx $newctx -secondary:$secondary
				}
				#>
				$jobs.Add($job) | Out-Null
			}

			Wait-ForJobsToComplete $jobs
		}     

		if (!$excludeNetwork -and !$excludeVPN -or $vpnOnly){
			$scriptBlocksToRun2.Add({
				Deploy-VPN -ctx $ctx
			})
		}

		if ($networkOnly -or $vpnOnly){
			return
		}
	}

	$jobs.Clear()

	<#
	# at this point, this only uses values in the primary KV
	$keyVaultNameThis = $ctx.GetKeyVaultName($false)
	$keyVaultNamePeer = $ctx.GetKeyVaultName($true)

	$diagStorageAccountKeyThis = Get-KeyVaultSecret -KeyVaultName $keyVaultNameThis -SecretName "DiagStorageAccountKey"
	$diagStorageAccountKeyPeer = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePeer -SecretName "DiagStorageAccountKey"

	$dataDogApiKeyThis = Get-KeyVaultSecret -KeyVaultName $keyVaultNameThis -SecretName "DataDogApiKey"
	$dataDogApiKeyPeer = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePeer -SecretName "DataDogApiKey"
	#>

	if ("db" -in $computeElements){
		foreach ($usage in $facilities){
		<#
		$installersStorageAccountKeyThis = Get-KeyVaultSecret -KeyVaultName $keyVaultNameThis -SecretName "InstallersStorageAccountKey"
		$installersStorageAccountKeyPeer = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePeer -SecretName "InstallersStorageAccountKey"
		#>
		<#
		foreach ($usage in $facilities){
			if (!$usage) { 
				$keyVaultName = $keyVaultNameThis
				$diagStorageAccountKey = $diagStorageAccountKeyThis
				$installersStorageAccountName = $ctx.GetSharedStorageAccountName("installers", $false)
				$installersStorageAccountKey = $installersStorageAccountKeyPeer
				$dataDogApiKey = $dataDogApiKeyThis
			}
			else { 
				$keyVaultName = $keyVaultNamePeer
				$diagStorageAccountKey = $diagStorageAccountKeyPeer
				$installersStorageAccountName = $ctx.GetSharedStorageAccountName("installers", $true)
				$installersStorageAccountKey = $installersStorageAccountKeyPeer
				$dataDogApiKey = $dataDogApiKeyPeer
			}
			#>
			<#
			$dbSaUserName    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaUserName"
			$dbSaPassword    = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbSaPassword"
			$dbLoginUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginUserName"
			$dbLoginPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbLoginPassword"
			$dbAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminName"
			$dbAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DbServerAdminPassword"
			#>

			$job = Start-ScriptJob -environmentCode $ctx.environmentCode -facilityCode $ctx.facilityCode -subscriptionCode $ctx.subscriptionCode `
								   -usage $usage `
								   -name $("Deploy-WEB-" + $ctx.GetResourcePostfix($usage)) `
								   -scriptToRun {
										$keyVaultName = $newctx.GetKeyVaultName($usage)

										$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey"
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
									}
			<#
			$job = Start-Job -Name $("Deploy-DB-" + $ctx.GetResourcePostfix($usage)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode,$usage -ScriptBlock {
				param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode, [switch]$secondary)
				. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
				$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
				Deploy-DB -ctx $newctx -secondary:$secondary `
						  -diagnosticStorageAccountKey $using:diagStorageAccountKey `
						  -dataDogApiKey $using:dataDogApiKey `
						  -installersStgAcctKey $using:installersStorageAccountKey -installersStgAcctName $using:installersStorageAccountName `
						  -adminUserName $using:dbAdminUserName -adminPassword $using:dbAdminPassword `
						  -saUserName $using:dbSaUserName -saPassword $using:dbSaPassword `
						  -loginUserName $using:dbLoginUserName -loginPassword $using:dbLoginPassword 
			}
			#>
			$jobs.Add($job)
		}
	}

	if ("web" -in $computeElements){
		$fileShareName = "workspace-file-storage"

		foreach ($usage in $facilities){
			<#
			if (!$usage) { 
				$keyVaultName = $keyVaultNameThis
				$diagStorageAccountKey = $diagStorageAccountKeyThis
				$fileStgAcctName = $ctx.GetStorageAccountName("files", $false)
				$dataDogApiKey = $dataDogApiKeyThis
			}
			else { 
				$keyVaultName = $keyVaultNamePeer
				$diagStorageAccountKey = $diagStorageAccountKeyPeer
				$fileStgAcctName = $ctx.GetStorageAccountName("files", $true)
				$dataDogApiKey = $dataDogApiKeyPeer
			}#>

			$job = Start-ScriptJob -environmentCode $ctx.environmentCode -facilityCode $ctx.facilityCode -subscriptionCode $ctx.subscriptionCode `
						-usage $usage `
						-name $("Deploy-DB-" + $ctx.GetResourcePostfix($usage)) `
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

							$fileStgAcctName = $newctx.GetStorageAccountName("files", $false)
							$fileShareName = "workspace-file-storage"

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
			<#
			$fileShareStorageAccountKey = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey"
			$octoApiKey                 = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoApiKey"
			$octoUrl                    = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "OctoUrl"
			$webAdminUserName           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminName"
			$webAdminPassword           = Get-KeyVaultSecret   -KeyVaultName $keyVaultName -SecretName "WebVmssServerAdminPassword"
			$webSslCertificateId        = Get-KeyVaultSecretId -KeyVaultName $keyVaultName -SecretName "WebSslCertificate"

			$job = Start-Job -Name $("Deploy-WEB-" + $ctx.GetResourcePostfix($usage)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode,$usage -ScriptBlock {
				param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode, [switch]$secondary)
				. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
				$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
				Deploy-Web -ctx $newctx -secondary:$secondary `
						   -diagnosticStorageAccountKey $using:diagStorageAccountKey `
						   -dataDogApiKey $using:dataDogApiKey `
						   -scaleSetCapacity $using:webScaleSetSize `
						   -adminUserName $using:webAdminUserName -adminPassword $using:webAdminPassword -sslCertificateUrl $using:webSslCertificateId `
						   -octoUrl $using:octoUrl -octoApiKey $using:octoApiKey `
						   -fileShareKey $using:fileShareStorageAccountKey -fileStgAcctName $using:fileStgAcctName -fileShareName $using:fileShareName
				#>

	}

	if ("ftp" -in $computeElements){
		foreach ($usage in $facilities){
			if (!$usage) { 
				$keyVaultName = $keyVaultNameThis
				$diagStorageAccountKey = $diagStorageAccountKeyThis
				$dataDogApiKey = $dataDogApiKeyThis
			}
			else { 
				$keyVaultName = $keyVaultNamePeer
				$diagStorageAccountKey = $diagStorageAccountKeyPeer
				$dataDogApiKey = $dataDogApiKeyPeer
			}

			$ftpAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminName"
			$ftpAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FtpVmssServerAdminPassword"

			$job = Start-Job -Name $("Deploy-FTP-" + $ctx.GetResourcePostfix($usage)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode,$usage -ScriptBlock {
				param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode, [switch]$secondary)
				. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
				$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
				Deploy-FTP -ctx $newctx -secondary:$secondary `
						   -diagnosticStorageAccountKey $using:diagStorageAccountKey `
						   -dataDogApiKey $using:dataDogApiKey `
						   -scaleSetCapacity $using:ftpScaleSetSize `
						   -adminUserName $using:ftpAdminUserName -adminPassword $using:ftpAdminPassword
			}
			$jobs.Add($job)
		}
	}

	if ("jump" -in $computeElements){
		foreach ($usage in $facilities){
			if (!$usage) { 
				$keyVaultName = $keyVaultNameThis
				$diagStorageAccountKey = $diagStorageAccountKeyThis
				$dataDogApiKey = $dataDogApiKeyThis
			}
			else { 
				$keyVaultName = $keyVaultNamePeer
				$diagStorageAccountKey = $diagStorageAccountKeyPeer
				$dataDogApiKey = $dataDogApiKeyPeer
			}

			$jumpAdminUserName =  Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminName"
			$jumpAdminPassword =  Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "JumpServerAdminPassword"

			$job = Start-Job -Name $("Deploy-JUMP-" + $ctx.GetResourcePostfix($usage)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode,$usage -ScriptBlock {
				param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode, [switch]$secondary)
				. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
				$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
				Deploy-Jump -ctx $newctx -secondary:$secondary `
							-diagnosticStorageAccountKey $using:diagStorageAccountKey `
							-dataDogApiKey $using:dataDogApiKey `
							-adminUserName $using:jumpAdminUserName -adminPassword $using:jumpAdminPassword
			}
			$jobs.Add($job)
		}
	}

	if ("admin" -in $computeElements){
		foreach ($usage in $facilities){
			if (!$usage) { 
				$keyVaultName = $keyVaultNameThis
				$diagStorageAccountKey = $diagStorageAccountKeyThis
				$dataDogApiKey = $dataDogApiKeyThis
			}
			else { 
				$keyVaultName = $keyVaultNamePeer
				$diagStorageAccountKey = $diagStorageAccountKeyPeer
				$dataDogApiKey = $dataDogApiKeyPeer
			}

			$adminAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminName"
			$adminAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "AdminServerAdminPassword"

			$job = Start-Job -Name $("Deploy-ADMIN-" + $ctx.GetResourcePostfix($usage)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode,$usage -ScriptBlock {
				param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode, [switch]$secondary)
				. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
				$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
				Deploy-Admin -ctx $newctx -secondary:$secondary `
							 -diagnosticStorageAccountKey $using:diagStorageAccountKey `
							 -dataDogApiKey $using:dataDogApiKey `
							 -adminUserName $using:adminAdminUserName -adminPassword $using:adminAdminPassword
			}
			$jobs.Add($job)
		}
	}

	Wait-ForJobsToComplete $jobs

	Write-Host "Out: " $MyInvocation.MyCommand 
}

function Invoke-ParallelScriptBlocks{
	param(
		[array]$scriptBlocks
	)

	$scriptBlocks | Invoke-Parallel -ScriptBlock { 
		Write-Host "Starting block: " $_
		Invoke-Command -ScriptBlock $_ 
		Write-Host "Done block: " $_
	}
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
	Write-Host "In: " $MyInvocation.MyCommand $ctx.environmentCode $ctx.facilityCode $ctx.subscriptionCode $primary $secondary $includeServices

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$jobs = New-Object System.Collections.ArrayList
	$usages = [Context]::GetFacilityUsages2($primary, $secondary)

	foreach ($usage in $usages){
		
		$job = Start-ScriptJob -environmentCode $ctx.environmentCode -facilityCode $ctx.facilityCode -subscriptionCode $ctx.subscriptionCode `
			    		       -usage $usage -includeServices:$includeServices `
						       -scriptToRun {
								   Teardown-CoreEntities -ctx $newctx -secondary:$usage -includeServices:$includeServices 
							   }
		$jobs.Add($job) | Out-Null
	}
	
	write-Host $MyInvocation.MyCommand "waiting for" $jobs.Count "jobs"
	Wait-ForJobsToComplete $jobs

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true)
}

function Teardown-All{
	param(
		[Context]$ctx,
		[switch]$includeServices
	)
	Teardown-Base -ctx $ctx -includeServices:$includeServices
	Teardown-Core -ctx $ctx -includeServices:$includeServices
}

function Teardown-CoreEntities{
	param(
		[Context]$ctx,
		[switch]$secondary,
		[switch]$includeServices
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.environmentCode $ctx.facilityCode $ctx.subscriptionCode $secondary $includeServices

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
			$job = Start-ScriptJob -environmentCode $ctx.environmentCode -facilityCode $ctx.facilityCode -subscriptionCode $ctx.subscriptionCode `
				    				-usage $secondary -includeServices:$includeServices `
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

	$job = Start-Job -Name $($MyInvocation.MyCommand + "-" + $ctx.GetResourcePostfix($secondary)) -ArgumentList $ctx.environmentCode,$ctx.GetFacilityCode($usage),$ctx.subscriptionCode -ScriptBlock {
		param([string]$environmentCode, [string]$facilityCode, [string]$subscriptionCode)
		. D:\Workspace\Workspace\Deployment-Scripts\WorkspaceAZRM.ps1
		$newctx = Login-WorkspaceAzureAccount -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
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

function Teardown-SvcInEnvironment{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$facilities = @("primary", "dr")
	$group1 = @("svc")

	foreach ($rc in $group1){
		foreach ($facility in $facilities){
			Teardown-ResourceCategoryInFacility -environment $environment -facility $facility -resourceCategory $rc
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment
}

function Teardown-DatabaseDisk{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility

	Teardown-ResourceCategory -environment $environment -facility $facility -resourceCategory "disks"

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility
}

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

function Create-Base{
	param(
		[Context]$ctx,
		[switch]$primary,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $primary $secondary

	$usages = [Context]::GetFacilityUsages2($primary, $secondary)

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

	Deploy-DatabaseDiskViaInitVM -ctx $ctx -secondary:$secondary
	Create-DiagnosticsEntities   -ctx $ctx -secondary:$secondary
	Create-AzureFilesEntities    -ctx $ctx -secondary:$secondary
	Create-ServicesEntities      -ctx $ctx -secondary:$secondary

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
	$ctx = Login-WorkspaceAzureAccount -environmentCode "p0" -facilityCode "p" -subscriptionCode "ws"
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
	$usages = [Context]::GetFacilityUsages2($primary, $secondary)
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

	$usages = [Context]::GetFacilityUsages2($primary, $secondary)
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

	$usages = [Context]::GetFacilityUsages2($primary, $secondary)
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

	$usages = [Context]::GetFacilityUsages2($primary, $secondary)
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
	$next.split('-')[0]
}

function Create-NextEnvironmentInstanceContext{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx,
		[Parameter(Mandatory=$true)]
		[string]$instanceId
	)

	$newCtx = [Context]::newEnvironmentContextFrom($ctx, $ctx.environment, $instanceId)
	return $newCtx
}

function Deploy-NextEnvironmentInstance{
	param(
		[Parameter(Mandatory=$true)]
		[Context]$ctx
	)

	$instancdId = Find-OpenDeploymentSlotNumber $ctx
	$newCtx = Create-NextEnvironmentContext -ctx $ctx -instanceId $instanceId

	Create-Core -ctx $newCtx

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
	$usages = [Context]::GetFacilityUsages2($primary, $secondary)
	foreach ($usage in $usages){
		$resourceGroupName = $ctx.GetResourceGroupName($category, $usage)
		$scaleSetName = $ctx.GetScaleSetName($category, $usage)
		$vmss = Get-AzureRmVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $scaleSetName
		$vmss.sku.capacity = $size
		Update-AzureRmVmss -ResourceGroupName $resourceGroupNam -Name $scaleSetName -VirtualMachineScaleSet $vmss
	}
}
