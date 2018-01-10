$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$items = Get-ChildItem -Path $currentDir -Include "Invoke-Parallel.ps1" -Recurse
if ($items -eq $null) { throw "Could not find Invoke-Parallel.ps1"}
. $items.FullName

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

	[string] GetResourceGroupName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.resourcePostfix
		}
		else{
			$postfix = $this.peerResourcePostfix
		}
		return "rg-" + $resourceType + "-" + $postfix
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
			return $ctx.subscriptionCode + "al" + $ctx.facilityCode
		}
		return $ctx.subscriptionCode + "al" + $ctx.peerFacilityCode
	}

	static [object] GetFacilityUsages($usePeer, $multiFacility){
		if ($multiFacility){
			return @($false, $true)
		}
		if ($usePeer){
			return @($true)
		}
		return @($false)
	}

	[string] GetEnvironmentInstance(){
		return $this.environmentCode.Substring(1, 1)
	}

	[string] GetKeyVaultName($usePeer){
		$keyVaultName = "kv-svc-" + $this.GetResourcePostfix($false)
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
		$ctx.sharedPeerResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $false)
		$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facilityCode)
		$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerFacilityCode)
		$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.facilityCode)
		$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.peerFacilityCode)

		return $ctx
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
		[string]$environmentCode,
		[string]$facilityCode,
		[string]$subscriptionCode
	)
	Write-Host "In: " $MyInvocation.MyCommand $environmentCode $facilityCode $subscriptionCode -ForegroundColor Green

	$profileFile = $currentDir + "\Deployment-Scripts\" + $loginAccount['profileFile']

	Write-Host "Logging into azure account"
	$azureCtx = Import-AzureRmContext -Path $profileFile
	Write-Host "Successfully loaded the profile file: " $profileFile -ForegroundColor Green

	Write-Host "Setting subscription..."
	$azureSub = Get-AzureRmSubscription –SubscriptionName $loginAccount['subscriptionName'] | Select-AzureRmSubscription
	Write-Host "Set Azure Subscription for session complete" -ForegroundColor Green
	Write-Host $azureSub.Name $azureSub.Subscription

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
	$ctx.sharedPeerResourcePostfix = [Context]::BuildSharedResourcePostfix($ctx, $false)
	$ctx.location = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.facilityCode)
	$ctx.peerLocation = [EnvironmentAndFacilitiesInfo]::GetFacilityLocation($ctx.peerFacilityCode)
	$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.facilityCode)
	$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.peerFacilityCode)

	Dump-Ctx $ctx
	$ctx.Validate()

	Write-Host "Out: " $MyInvocation.MyCommand $environmentCode $facilityCode $subscriptionCode -ForegroundColor Green

	return $ctx
}

function Dump-Ctx{
	param([Context] $ctx)

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
}

function Ensure-LoggedIntoAzureAccount {
	param(
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
		[string]$environmentCode,
		[string]$facilityCode,
		[string]$subscriptionCode
	)

	return $subscriptionCode + $environmentCode + $facilityCode
}

function Get-FacilityLocation{
	param(
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $facility -ForegroundColor Green

	if (!$facilitiesLocationMap.ContainsKey($facility)){
		throw "Facility not found: " + $facility
	}

	Write-Host "Out: " $MyInvocation.MyCommand $facility -ForegroundColor Green

	return $facilitiesLocationMap[$facility]
}

function Create-ResourceGroup{
	param(
		[string]$environment,
		[string]$facility,
		[string]$resourceCategory
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $resourceCategory -ForegroundColor Green

	$resourceGroupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory $resourceCategory
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $resourceCategory -ForegroundColor Green
}

function Ensure-ResourceGroup{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$category,
		[string]$location,
		[string]$resourceGroupName
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx $usePeer $location $groupName -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	if ($ctx -ne $null){
		$resourceGroupName = $ctx.GetResourceGroupName($category, $usePeer)
		$location = $ctx.GetLocation($usePeer)
	}

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

	Write-Host "Out: " $MyInvocation.MyCommand $ctx $usePeer $location $groupName -ForegroundColor Green
}

function Ensure-AllResourceGroups{
	param(
		[string]$facility,
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	foreach ($resourceCategory in $resourceCategories){
		$groupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory $resourceCategory
		Ensure-ResourceGroup -facility $facility -groupName $groupName
	}

	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment -ForegroundColor Green
}

function Execute-Deployment{
	param(
		[string]$templateFile,
		[string]$resourceGroupName,
		[hashtable]$parameters
	)
	Write-Host "In: " $MyInvocation.MyCommand $templateFile $resourceGroupName -ForegroundColor Green

	#Ensure-LoggedIntoAzureAccount -ctx $ctx

	Write-Host "Executing template deployment: " $resourceGroupName $templateFile
	Write-Host "Using parameters: "
	#Dump-Hash $parameters

	#$templateFile = $currentDir + "\Deployment-Scripts\ARM\" + $templateFile
	Write-Host "Using template file: " $templateFile

	# try to find ARM template
	$items = Get-ChildItem -Path $currentDir -Include $templateFile -Recurse
	if ($items -eq $null) { throw "Could not find template: " + $templateFile}
	$fullTemplateFileName = $items[0]
	
	$name = ((Get-ChildItem $fullTemplateFileName).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))
	$result = New-AzureRmResourceGroupDeployment `
		-Name $name `
		-ResourceGroupName $resourceGroupName `
		-TemplateFile $fullTemplateFileName `
		-TemplateParameterObject $parameters `
		-Force -Verbose `
		-ErrorVariable errorMessages

	if ($errorMessages) {
		$exceptionMessage = 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
		Write-Output $exceptionMessage
		throw $exceptionMessage
	}

	Write-Host "Out: " $MyInvocation.MyCommand $templateFile $resourceGroupName -ForegroundColor Green

	return $name
}
<#
function Construct-ResourceGroupName{
	param(
		[string]$facility,
		[string]$environment,
		[string]$resourceCategory
		)
	return "rg-" + $resourceCategory + "-" + $( Construct-ResourcePostfix -facility $facility -environment $environment )
}

function Construct-StorageAccountName{
	param(
		[string]$facility,
		[string]$environment,
		[string]$resourceCategory
		)

	return "stg" + $resourceCategory + $( Construct-ResourcePostfix -facility $facility -environment $environment ) -replace "-", ""
}
#>
function Deploy-StorageAccount{
	param(
		[string]$resourceGroupName,
		[string]$storageAccountName
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $resourceGroupName $storageAccountName -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$parameters = @{
		"storageAccountName" = $storageAccountName
	}

	Execute-Deployment -templateFile "arm-stgaccount-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $facility $resourceGroupName $storageAccountName -ForegroundColor Green
}

function Ensure-StorageAccount{
	param(
		[string]$resourceGroupName,
		[string]$storageAccountName
	)

	Write-Host "In: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName -ForegroundColor Green

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


	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment $storageAccountName -ForegroundColor Green
}
<#
function Create-AllStorageAccounts{
	param(
		[string]$facility,
		[string]$environment
		)
	# note, this has changed as we don;'t need most due to using managed disks

	Write-Host "In: " $MyInvocation.MyCommand $facility $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	foreach ($resourceCategory in $resourceCategories){
		Create-StorageAccount -facility $facility -environment $environment -resourceCategory $resourceCategory
	}

	# TODO: make calls to create others not strictly tied to a resource category?  Such as files, installers

	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment $storageAccountName -ForegroundColor Green
}
#>
function Deploy-VNet{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $ctx.GetVnetCidrPrefix($usePeer) -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -usePeer $usePeer -category "vnet"

	$parameters = @{
		"vnetName" = $ctx.environmentCode
		"vnetCidrPrefix" = $ctx.GetVnetCidrPrefix($usePeer)
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
	}

	$resourceGroupName = $ctx.GetResourceGroupName("vnet", $usePeer)
	Execute-Deployment -templateFile "arm-vnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $westVnetCidrPrefix $eastVnetCidrPrefix -ForegroundColor Green
}

function Deploy-PIPs {
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -usePeer $usePeer -category "pips"

	$parameters = @{
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
	}

	$resourceGroupName = $ctx.GetResourceGroupName("pips", $usePeer)
	Execute-Deployment -templateFile "arm-pips-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}

function Deploy-NSGs {
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

 	Ensure-ResourceGroup -ctx $ctx -usePeer $usePeer -category "nsgs"

	$parameters = @{
		"vnetCidrPrefix" = $ctx.GetVnetCidrPrefix($usePeer)
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
	}

	$resourceGroupName = $ctx.GetResourceGroupName("nsgs", $usePeer)
	Execute-Deployment -templateFile "arm-nsgs-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}

function Deploy-VPN{
	param(
		[Context]$ctx
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true) -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "vnet"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"peerFacility" = $ctx.peerFacilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "VPN"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"peerResourceNamePostfix" = $ctx.GetResourcePostfix($true)
		"mainVnetCidrPrefix" = $ctx.vnetCidrPrefix
		"peerVnetCidrPrefix" = $ctx.peerVnetCidrPrefix
		"mainLocation" = $ctx.location
		"peerLocation" = $ctx.peerLocation
		"sharedKey" = "workspacevpn"
	}

	$resourceGroupName = $ctx.GetResourceGroupName("vnet", $usePeer)
	Execute-Deployment -templateFile "arm-vpn-deploy.json" -resourceGroupName $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true) -ForegroundColor Green
}

function Deploy-DB{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$diagnosticStorageAccountKey,
		[string]$installersStgAcctKey,
		[string]$installersStgAcctName,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[string]$saUserName,
		[string]$saPassword,
		[string]$vmCustomData,
		[string]$loginUserName,
		[string]$loginPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $diagnosticStorageAccountKey $dataDogApiKey $dbAdminUserName -ForegroundColor Green

	Dump-Ctx $ctx

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName("db", $usePeer)
	Ensure-ResourceGroup -ctx $ctx -category "db"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "DB"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"location" = $ctx.location

		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"installersStgAcctKey" = $installersStgAcctKey
		"installersStgAcctName" = $installersStgAcctName
		"saUserName" = $saUserName
		"saPassword" = $saPassword
		"vmCustomData" = $vmCustomData
		"loginUserName" = $loginUserName
		"loginPassword" = $loginPassword

		"vmSize" = "Standard_D1_v2"
		"dbServerName" = "sql1"
	}

	Execute-Deployment -templateFile "arm-db-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey $dbAdminUserName -ForegroundColor Green
}

function Deploy-Web{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[string]$sslCertificateUrl,
		[string]$octoUrl,
		[string]$octoApiKey,
		[string]$vmCustomData,
		[string]$fileShareKey,
		[string]$fileStgAcctName,
		[string]$fileShareName,
		[int]$scaleSetCapacity = 2
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "web"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "WEB"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"location" = $ctx.location

		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"sslCertificateUrl" = $sslCertificateUrl
		"sslCertificateStore" = "MyCerts"
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"octoUrl" = $octoUrl
		"octoApiKey" = $octoApiKey
		"vmCustomData" = $vmCustomData
		"fileShareKey" = $fileShareKey
		"fileStgAcctName" = $fileStgAcctName
		"fileShareName" = $fileShareName
		"vmSku" = "Standard_DS1_v2"
		"scaleSetCapacity" = $scaleSetCapacity
	}

	$resourceGroupName = $ctx.GetResourceGroupName("web", $usePeer) 
	Execute-Deployment -templateFile "arm-vmssweb-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-FTP{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[int]$scaleSetCapacity = 2
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "ftp"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "FTP"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"location" = $ctx.location

		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"vmSku" = "Standard_DS1_v2"
		"scaleSetCapacity" = $scaleSetCapacity
		"vmCustomData" = ""
	}

	$resourceGroupName = $ctx.GetResourceGroupName("ftp", $usePeer) 
	Execute-Deployment -templateFile "arm-vmssftp-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-Jump{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "jump"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "JUMP"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"location" = $ctx.location
		
		"vmCustomData" = ""
		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
	}

	$resourceGroupName = $ctx.GetResourceGroupName("jump", $usePeer)
	Execute-Deployment -templateFile "arm-jump-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-Admin{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -usePeer $usePeer -category "admin"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "ADMIN"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"location" = $ctx.location
		
		"vmCustomData" = ""
		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
	}

	$resourceGroupName = $ctx.GetResourceGroupName("admin", $usePeer)
	Execute-Deployment -templateFile "arm-admin-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-OctoServer{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -usePeer $secondary -category "svc"

	$parameters = @{
		"environmentCode" = $ctx.environmentCode
		"environment" = $ctx.environment
		"instance" = $ctx.environmentInstance
		"facility" = $ctx.facilityCode
		"subscriptionCode" = $ctx.subscriptionCode
		"Role" = "OCTO"
		"resourceNamePostfix" = $ctx.GetResourcePostfix($false)
		"location" = $ctx.location
	}

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	Execute-Deployment -templateFile "arm-octoserver-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $secondary -ForegroundColor Green
}

function Deploy-ServicesVnetEntities{
	param(
		[Context]$ctx,
		[switch]$secondary
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -usePeer $secondary -category "svc"

	$parameters = @{
		"vnetCidrPrefix" = $ctx.GetVnetCidrPrefix($secondary)
		"resourceNamePostfix" = $ctx.GetResourcePostfix($secondary)
		"vnetName" = "s0" 
	}
	
	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	Execute-Deployment -templateFile "arm-svcvnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($secondary) -ForegroundColor Green
}

function Deploy-DatabaseDiskViaInitVM{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$databaseServerId="sql1",
		[string]$diskName="data1",
		[string]$dataDiskSku="Standard_LRS",
		[int]$dataDiskSizeInGB=64,
		[string]$adminUserName="wsadmin",
		[string]$adminPassword="Workspace!DbDiskInit!2018"
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "dbdi" -usePeer $usePeer
	Ensure-ResourceGroup -ctx $ctx -category "disks" -usePeer $usePeer

	$diskResourceGroupName = $ctx.GetResourceGroupName("disks", $usePeer)

	$parameters = @{
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
		"diskResourceGroupName" = $diskResourceGroupName
		"diskName" = $diskName
		"dataDiskSku" = $dataDiskSku
		"dataDiskSizeInGB" = $dataDiskSizeInGB
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"databaseServerId" = $databaseServerId
	}

	$deployResourceGroupName = $ctx.GetResourceGroupName("dbdi", $usePeer)
	$deploymentName = Execute-Deployment -templateFile "arm-db-disk-init-vm-deploy.json" -resourceGroup $deployResourceGroupName -parameters $parameters

	$deployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $deployResourceGroupName -Name $deploymentName
	$outputs = $deployment.Outputs

	$vmName = $outputs["vmName"].Value
	$dataDiskName = $outputs["dataDiskName"].Value
	$VirtualMachine = Get-AzureRmVM -ResourceGroupName $deployResourceGroupName -Name $vmName
	Remove-AzureRmVMDataDisk -VM $VirtualMachine -Name $dataDiskName
	Update-AzureRmVM -ResourceGroupName $deployResourceGroupName -VM $VirtualMachine

	Remove-AzureRmResourceGroup -Name $deployResourceGroupName -Force | Out-Null

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green
}

function Create-KeyVault{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx "svc"

	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)

	$keyVaultName = "kv-svc-" + $resourcePostfix

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
	if (!$keyVault)
	{
		Write-Host "Did not find KeyVault, so trying to create..."
		$location = $ctx.GetLocation($usePeer)
		$keyVault = New-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -Location $location -EnabledForDeployment
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	return $keyVault
}

function Get-KeyVault{
	param(
		[string]$facility,
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	$resourcePostfix = $ctx.GetResourcePostfix("svc", $usePeer)
	$keyVaultName = "kv-svc-" + $resourcePostfix

	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
	return $keyVault
}

function Remove-KeyVault{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)
	$keyVaultName = "kv-svc-" + $resourcePostfix
	$location = $ctx.GetLocation($usePeer)

	$keyVault = Remove-AzureRmKeyVault -Force -VaultName $keyVaultName -Location $location -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue -InformationAction Continue

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green
	return $keyVault
}

<#
function Add-WebSslSelfSignedCertToKeyVault{
	param(
		[string]$facility,
		[string]$environment,
		[string]$certName
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $certName -ForegroundColor Green

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

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $certName -ForegroundColor Green

	return $certificate
}

function Add-WebSslCertToKeyVault{
	param(
		[string]$facility,
		[string]$environment,
		[string]$certName
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $certName -ForegroundColor Green

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

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $certName -ForegroundColor Green

	return $certificate
}
#>

function Set-KeyVaultSecret{
	param(
		[object]$KeyVaultName,
		[string]$SecretName,
		[string]$SecretValue
	)
	Write-Host "In: " $MyInvocation.MyCommand $KeyVaultName $SecretName -ForegroundColor Green

	$secureValue = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
	Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $secureValue 

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName -ForegroundColor Green 
}

function Get-KeyVaultSecret{
	param(
		[string]$KeyVaultName,
		[string]$SecretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $KeyVaultName $SecretName -ForegroundColor Green
	
	$text = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction Stop).SecretValueText

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName -ForegroundColor Green 

	return $text
}

function Get-KeyVaultSecretId{
	param(
		[string]$KeyVaultName,
		[string]$SecretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $KeyVaultName $SecretName -ForegroundColor Green
	
	$secret = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction Stop

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName $secret.Id -ForegroundColor Green 

	return $Secret.Id
}

function Add-LocalCertificateToKV{
	param(
		[string]$keyVaultName,
		[string]$pfxFile,
		[string]$password,
		[string]$secretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $keyVaultName $certName $pfxFile -ForegroundColor Green

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

	Write-Host "Out: " $MyInvocation.MyCommand $keyVaultName $certName $pfxFile -ForegroundColor Green
}


function Create-KeyVaultSecrets{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$webSslCertificateSecretName = "WebSslCertificate"
	$octoUrl = "https://pip-octo-wspdpr.westus.cloudapp.azure.com" 
	$octoApiKey = "API-SFVPQ7CI5DELMEXG0Y3XZKLE8II"
	$dataDogApiKey = "691f4dde2b1a5e9a9fd5f06aa3090b87"
	$pfxfile = "workspace.pfx"
	$pfxfilePassword = "workspace"

	$resourceGroupName = $ctx.GetResourceGroupName("svc", $usePeer)
	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)
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
	
	$diagAcctResourceGroupName = $ctx.GetResourceGroupName("diag", $usePeer)
	$diagStorageAccountName = $ctx.GetStorageAccountName("diag", $usePeer)
	$diagStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $diagAcctResourceGroupName -AccountName $diagStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey" -SecretValue $diagStgAcctKeys.Value[0]

	$installersAcctResourceGroupName = $ctx.GetSharedResourceGroupName("installers", $usePeer)
	$installersStorageAccountName = $ctx.GetSharedStorageAccountName("installers", $usePeer)
	$installersStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $installersAcctResourceGroupName -AccountName $installersStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey" -SecretValue $installersStgAcctKeys.Value[0]

	$fileShareAcctResourceGroupName = $ctx.GetResourceGroupName("files", $usePeer)
	$fileShareStorageAccountName = $ctx.GetStorageAccountName("files", $usePeer)
	$fileShareStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $fileShareAcctResourceGroupName -AccountName $fileShareStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey" -SecretValue $fileShareStgAcctKeys.Value[0]

	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoUrl" -SecretValue $octoUrl
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoApiKey" -SecretValue $octoApiKey
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey" -SecretValue $dataDogApiKey

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}


function Build-KeyVault{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	
	Create-KeyVault -ctx $ctx -usePeer $usePeer
	Create-KeyVaultSecrets -ctx $ctx -usePeer $usePeer
}

function Rebuild-KeyVault{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	
	Remove-KeyVault -ctx $ctx -usePeer $usePeer
	Build-KeyVault -ctx $ctx -usePeer $usePeer
}

function Create-Core{
	param(
		[Context]$ctx,
		[int]$webScaleSetSize=2,
		[int]$ftpScaleSetSize=2,
		[switch]$networkOnly,
		[switch]$excludeVPN,
		[switch]$excludeNetwork,
		[array]$computeElements=@("db", "web", "ftp", "jump", "ftp", "admin")
	)
	
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true) -ForegroundColor Green

	Dump-Ctx $ctx

	Ensure-LoggedIntoAzureAccount -ctx $ctx
	
	if (!$excludeNetwork){
		Deploy-NSGs -ctx $ctx -usePeer $false
		#Deploy-NSGs -ctx $ctx -usePeer $true
		Deploy-PIPs -ctx $ctx -usePeer $false
		#Deploy-PIPs -ctx $ctx -usePeer $true
		Deploy-VNet -ctx $ctx -usePeer $false
		#Deploy-VNet -ctx $ctx -usePeer $true

		if ($excludeVPN){
			Deploy-VPN -ctx $ctx
		}
	}

	if ($networkOnly){
		return
	}

	# at this point, this only uses values in the primary KV
	$keyVaultNamePR = $ctx.GetKeyVaultName($false)
	$keyVaultNameDR = $ctx.GetKeyVaultName($true)

	$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DiagStorageAccountKey"
	$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "InstallersStorageAccountKey"
	$fileShareStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "FileShareStorageAccountKey"

	$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DataDogApiKey"

	# Bring up the VNet along as the NSG's and PIPs

	$fileStgAcctNamePR = $ctx.GetStorageAccountName("files", $false)
	$fileStgAcctNameDR = $ctx.GetStorageAccountName("files", $true)
	$installersStorageAccountNamePR = $ctx.GetSharedStorageAccountName("installers", $false)
	$installersStorageAccountNameDR = $ctx.GetSharedStorageAccountName("installers", $true)
	$fileShareName = "workspace-file-storage"

	# Bring up services in each VNet (right now just primary)

	if ("db" -in $computeElements){
		$dbSaUserName =       Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbSaUserName"
		$dbSaPassword =       Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbSaPassword"
		$dbLoginUserName =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbLoginUserName"
		$dbLoginPassword =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbLoginPassword"
		$dbAdminUserName =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbServerAdminName"
		$dbAdminPassword =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbServerAdminPassword"
		$dbVmCustomData = "{'installersStgAcctKey': '" + $fileShareStorageAccountKey + "', 'dbSaUserName': '" + $dbSaUserName + "', 'dbSaPassword': '" + $dbSaPassword + "'}"
		$dbVmCustomDataBytes = [System.Text.Encoding]::UTF8.GetBytes($dbVmCustomData)
		$dbVmCustomDataB64 = [System.Convert]::ToBase64String($dbVmCustomDataBytes)
		Deploy-DB -ctx $ctx -usePeer $false -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $dbAdminUserName -adminPassword $dbAdminPassword -installersStgAcctKey $installersStorageAccountKey -installersStgAcctName $installersStorageAccountNamePR -vmCustomData $dbVmCustomDataB64 -saUserName $dbSaUserName -saPassword $dbSaPassword -loginUserName $dbLoginUserName -loginPassword $dbLoginPassword
	}

	if ("web" -in $computeElements){
		$octoApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "OctoApiKey"
		$octoUrl = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "OctoUrl"
		$webAdminUserName =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "WebVmssServerAdminName"
		$webAdminPassword =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "WebVmssServerAdminPassword"
		$webVmCustomData = "{'octpApiKey': '" + $octoApiKey + "', 'octoUrl': " + $octoUrl + "', 'fileShareKey': '" + $fileShareStorageAccountKey + "'}"
		$webVmCustomDataBytes = [System.Text.Encoding]::UTF8.GetBytes($webVmCustomData)
		$webVmCustomDataB64 = [System.Convert]::ToBase64String($webVmCustomDataBytes)
		$webSslCertificateIdPR = Get-KeyVaultSecretId -KeyVaultName $keyVaultNamePR -SecretName "WebSslCertificate"
		Deploy-Web -ctx $ctx -usePeer $false -scaleSetCapacity 1 -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $webAdminUserName -adminPassword $webAdminPassword -sslCertificateUrl $webSslCertificateIdPR -vmCustomData $webVmCustomDataB64 -octoUrl $octoUrl -octoApiKey $octoApiKey -fileShareKey $fileShareStorageAccountKey -fileStgAcctName $fileStgAcctNamePR -fileShareName $fileShareName
	}

	if ("ftp" -in $computeElements){
		$ftpAdminUserName =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "FtpVmssServerAdminName"
		$ftpAdminPassword =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "FtpVmssServerAdminPassword"
		Deploy-FTP -ctx $ctx -usePeer $false -scaleSetCapacity 1 -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $ftpAdminUserName -adminPassword $ftpAdminPassword
	}

	if ("jump" -in $computeElements){
		$jumpAdminUserName =  Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "JumpServerAdminName"
		$jumpAdminPassword =  Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "JumpServerAdminPassword"
		Deploy-Jump -ctx $ctx -usePeer $false -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $jumpAdminUserName -adminPassword $jumpAdminPassword
	}

	if ("admin" -in $computeElements){
		$adminAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "AdminServerAdminName"
		$adminAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "AdminServerAdminPassword"
		Deploy-Admin -ctx $ctx -usePeer $false -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $adminAdminUserName -adminPassword $adminAdminPassword
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($false) $ctx.GetResourcePostfix($true) $ctx.GetVnetCidrPrefix($false) $ctx.GetVnetCidrPrefix($true) -ForegroundColor Green
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
		[bool]$usePeer=$false,
		[string]$category
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $category  -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = $ctx.GetResourceGroupName($category, $usePeer)

	Write-Host "Getting resource group: " $resourceGroupName
	$rg = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue
	if ($rg -eq $null)
	{
		Write-Host "Resource group did not exist: " $resourceGroupName
	}
	else
	{
		Write-Host "Deleting resource group: " $resourceGroupName
		Remove-AzureRmResourceGroup -Name $resourceGroupName -Force | Out-Null
		Write-Host "Deleted resource group: " $resourceGroupName
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) $category  -ForegroundColor Green
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
		[bool]$includeServices=$false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Teardown-CoreEntities -ctx $ctx -usePeer $false -includeServices $includeServices 
	Teardown-CoreEntities -ctx $ctx -usePeer $true -includeServices $includeServices 

	Write-Host "Out: " $MyInvocation.MyCommand $ctx -ForegroundColor Green
}

function Teardown-All{
	param(
		[Context]$ctx,
		[bool]$includeServices=$false
	)
	Teardown-Base -ctx $ctx
	Teardown-Core -ctx $ctx
}

function Teardown-CoreEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[bool]$includeServices=$false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	if ($includeServices){
		$group2 = @("svc")
	}
	else
	{
		$group2 = @()
	}

	$group1 = @("admin", "jump", "ftp", "web", "db")
	$group3 = @("vnet", "pips", "nsgs")
	$groups = @($group1, $group2, $group3)

	foreach ($group in $groups){
		foreach ($rc in $group){
			Teardown-ResourceCategory -ctx $ctx -usePeer $usePeer -category $rc
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx $usePeer -ForegroundColor Green
}

<#
function Create-DiagnosticsEntitiesMultiFacility{
	param(
		[Context]$ctx
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerFacilityResourcePrefix -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Create-DiagnosticsEntitiesInFacility -environment $environment -facility "primary"
	Create-DiagnosticsEntitiesInFacility -environment $environment -facility "dr"

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerFacilityResourcePrefix -ForegroundColor Green
}
#>
function Create-DiagnosticsEntities{
	param(
		[Context]$context,
		[bool]$usePeer = $false
	)
	Write-Host "In: " $MyInvocation.MyCommand $context.resourcePostfix $context.peerFacilityResourcePrefix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceCategories = @("bootdiag", "diag")

	$location = $ctx.GetLocation($usePeer)

	foreach ($rc in $resourceCategories){
		$resourceGroupName = $ctx.GetResourceGroupName($rc, $usePeer)
		$storageAccountName = $ctx.GetStorageAccountName($rc, $usePeer)
		Ensure-ResourceGroup -ctx $ctx -usePeer $usePeer -category $rc
		Ensure-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	}

	Write-Host "Out: " $MyInvocation.MyCommand $context.resourcePostfix $context.peerFacilityResourcePrefix $usePeer $multiFacility -ForegroundColor Green
}

function Teardown-Diagnostics{
	param(
		[Context]$ctx
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Teardown-DiagnosticsEntities -ctx $ctx -usePeer $false
	Teardown-DiagnosticsEntities -ctx $ctx -usePeer $true

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Teardown-DiagnosticsEntities{
	param(
		[Context]$context,
		[bool]$usePeer = $false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$group1 = @("bootdiag", "diag")
	foreach ($rc in $group1){
		Teardown-ResourceCategory -ctx $ctx -usePeer $usePeer -category $rc
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green
}

function Teardown-SvcInEnvironment{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$facilities = @("primary", "dr")
	$group1 = @("svc")

	foreach ($rc in $group1){
		foreach ($facility in $facilities){
			Teardown-ResourceCategoryInFacility -environment $environment -facility $facility -resourceCategory $rc
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Teardown-DatabaseDisk{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Teardown-ResourceCategory -environment $environment -facility $facility -resourceCategory "disks"

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-ServicesEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Ensure-ResourceGroup -ctx $ctx -category "svc"

	Deploy-ServicesVnetEntities -ctx $ctx -secondary $usePeer
	Build-KeyVault -ctx $ctx

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}

function Create-Base{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[bool]$multiFacility=$true
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer $multiFacility -ForegroundColor Green

	$usages = [Context]::GetFacilityUsages($usePeer, $multiFacility)

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	foreach ($usage in $usages){
		Create-BaseEntities -ctx $ctx -usePeer $usage
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerFacilityResourcePrefix $usePeer $multiFacility -ForegroundColor Green
}

function Create-BaseEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.resourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	Deploy-DatabaseDiskViaInitVM -ctx $ctx -usePeer $usePeer
	Create-DiagnosticsEntities -ctx $ctx -usePeer $usePeer
	Create-AzureFilesEntities -ctx $ctx -usePeer $usePeer
	Create-ServicesEntities -ctx $ctx -usePeer $usePeer

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-AzureFilesEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$location = $ctx.GetLocation($usePeer)
	$resourceGroupName = $ctx.GetResourceGroupName("files", $usePeer)
	$storageAccountName = $ctx.GetStorageAccountName("files", $usePeer)

	Ensure-ResourceGroup -ctx $ctx -category "files" -usePeer $usePeer
	Ensure-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	Create-AzureFilesShare -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
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

<#
function Create-AzureFilesEntitiesInFacility{
	param(
		[Context]$ctx,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourceGroupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory "files"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName
	Ensure-StorageAccount -environment $environment -facility $facility -resourceCategory "files"
	Create-AzureFilesShareInFacility -environment $environment -facility $facility

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}
#>
function Create-AzureFilesShare{
	param(
		[string]$resourceGroupName,
		[string]$storageAccountName
	)
	Write-Host "In: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName -ForegroundColor Green

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

	Write-Host "Out: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName -ForegroundColor Green
}


function Stop-ComputeResources{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false,
		[bool]$multiFacility = $false
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx
	<#
	$usages = [Context]::GetFacilityUsages($usePeer, $multiFacility)
	$usages | Invoke-Parallel -ScriptBlock{
		Stop-ComputeVMs -ctx $ctx -usePeer $_
	}
	foreach ($usage in $usages)	{
		{  }
		{ Stop-ScaleSetVMs -ctx $ctx -usePeer $usage }
	}
	#>
}

function Stop-ComputeVMs{
	param(

		[Context]$context,
		[bool]$usePeer=$false
	)

	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)
	$allVirtualMachines = Get-AzureRmVM
	$virtualMachinesToStop =  $allVirtualMachines | Where-Object { $_.Name.EndsWith($resourcePostfix) }
	$virtualMachinesToStop | ForEach-Object -Process {
		Write-Host "Stopping VM: " $_.Name
		Stop-AzureRmVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force -InformationAction Continue
	}
}

function Stop-ScaleSetVMs{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)
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

function Start-ComputeResources{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false,
		[bool]$multiFacility = $false
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$usages = [Context]::GetFacilityUsages($usePeer, $multiFacility)
	foreach ($usage in $usages)	{
		Start-ComputeVMs -ctx $ctx -usePeer $usage
		Start-ScaleSetVMs -ctx $ctx -usePeer $usage
	}
}

function Start-ComputeVMs{
	param(
		[Context]$context,
		[bool]$usePeer=$false
	)

	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)
	$allVirtualMachines = Get-AzureRmVM
	$virtualMachinesToStop =  $allVirtualMachines | Where-Object { $_.Name.EndsWith($resourcePostfix) }
	$virtualMachinesToStop | ForEach-Object -Process {
		Write-Host "Starting VM: " $_.Name
		Start-AzureRmVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name
	}
}

function Start-ScaleSetVMs{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	
	Ensure-LoggedIntoAzureAccount -ctx $ctx

	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)
	$allScaleSets = Get-AzureRmVmss 
	$scaleSets = $allScaleSets | Where-Object { $_.Name.EndsWith($resourcePostfix) }
	foreach ($scaleSet in $scaleSets){
		$vmssVMs = Get-AzureRmVmssVM -ResourceGroupName $scaleSet.ResourceGroupName -VMScaleSetName $scaleSet.Name 
		foreach ($vmssVM in $vmssVMs){
			Write-Host "Starting VMSS VM: " $scaleSet.Name $vmssVMs.Name
			Start-AzureRmVmss -ResourceGroupName $scaleSets.ResourceGroupName -VMScaleSetName $scaleSet.Name -InstanceId $vmssVM.InstanceId
		}
	}
}

function Find-OpenDeploymentSlotNumber{
	# finds the first numeric deployment slot for an environment
	# this is defined by looking for the vnets and finding the first
	# open spot ?n-vnet-<postfix>, the lowest number n in 0-7 
	# where a vnet is not found

	param(
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
		[Context]$ctx,
		[string]$instanceId
	)

	$newCtx = [Context]::newEnvironmentContextFrom($ctx, $ctx.environment, $instanceId)
	return $newCtx
}

function Deploy-NextEnvironmentInstance{
	param(
		[Context]$ctx
	)

	$instancdId = Find-OpenDeploymentSlotNumber $ctx
	$newCtx = Create-NextEnvironmentContext -ctx $ctx -instanceId $instanceId

	Create-Core -ctx $newCtx

	return $newCtx
}

#Execute-Deployment -templateFile "arm-vnet-deploy.json"
#$ctx = Login-WorkspacePrimaryProd
#Create-Core -ctx $ctx -computeElements @("db", "web") -excludeNetwork -webScaleSetSize 2
$ctx = Login-WorkspaceAzureAccount -environmentCode "s0" -facilityCode "p" -subscriptionCode "ws"
Deploy-ServicesVnetEntities -ctx $ctx
Deploy-OctoServer -ctx $ctx

#Stop-ComputeResources -ctx $ctx
#Write-AllWorkspaceEntitiesToCSV
#$ctx = Login-WorkspaceAzureAccount -environmentCode "p1" -facilityCode "p" -subscriptionCode "ws"
#Start-ComputeResources -ctx $ctx
#Create-All -ctx $ctx
#Create-Base -ctx $ctx
#Create-Core -ctx $ctx
#Rebuild-KeyVault -ctx $ctx
#Deploy-VPN -ctx $ctx
#Teardown-Core -ctx $ctx

#Deploy-DatabaseDiskViaInitVM -ctx $ctx -usePeer $true
#Create-AzureFilesEntitiesInFacility -environment "prod" -facility "primary"
#Create-ServicesEntities -environment "prod" -facility "primary"
#Remove-KeyVault -environment "prod" -facility "primary"
#Build-KeyVault -environment "prod" -facility "primary"
#Rebuild-KeyVault -environment "prod" -facility "primary"
#Create-DiagnosticsInEnvironment -environment "prod"
#Teardown-DiagnosticsInEnvironment -environment "prod"
#Teardown-SvcInEnvironment -environment "prod"
#Deploy-DatabaseDiskViaInitVM -facility "primary" -environment "prod" -databaseServerId "sql1" -diskName "data2"
<#
Export-ModuleMember -Function Teardown-EntireRegionAndFacility
#>
#Teardown-EntireRegionAndFacility -environment "prod" -facility "primary"
#Teardown-EntireRegionAndFacility -environment "prod" -facility "dr"

#Bringup-Environment -environment "prod" 
#Teardown-EntireEnvironment -environment "p0"
#Teardown-Core -ctx $ctx
#Teardown-Diagnostics -ctx $ctx
					
#Add-CertificateToKV -facility "primary" -environment "prod" -pfxFile "workspace.pfx" -password "workspace" -secretName "foo"

#Create-KeyVaultSecrets -facility "primary" -environment "prod"
#Write-AllWorkspaceEntitiesToCSV