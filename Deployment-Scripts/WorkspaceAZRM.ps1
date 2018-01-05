$loggedIn = $false

$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$templateFileLocation = $currentDir

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
	}

	static $facilityPeersMap = @{
		"p" = "d"
		"d" = "p"
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
	[string]$subscriptionCode
	[string]$peerFacilityCode
	[string]$resourcePostfix
	[string]$peerResourcePostfix
	[string]$sharedResourcePostfix
	[string]$sharedpeerResourcePostfix
	[string]$location
	[string]$peerLocation
	[string]$vnetCidrPrefix
	[string]$peerVnetCidrPrefix

	[string] CreateResourceGroupName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.resourcePostfix
		}
		else{
			$postfix = $this.peerResourcePostfix
		}
		return "rg-" + $resourceType + "-" + $postfix
	}

	[string] CreateSharedResourceGroupName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.sharedResourcePostfix
		}
		else{
			$postfix = $this.sharedpeerResourcePostfix
		}
		return "rg-" + $resourceType + "-" + $postfix
	}

	[string] CreateStorageAccountName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.resourcePostfix
		}
		else{
			$postfix = $this.peerResourcePostfix
		}
		return "rg" + $resourceType + $postfix	
	}

	[string] CreateSharedStorageAccountName($resourceType, $usePeer=$false){
		if (!$usePeer){
			$postfix = $this.sharedResourcePostfix
		}
		else{
			$postfix = $this.sharedpeerResourcePostfix
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

	Ensure-LoggedIntoAzureAccount

	$ctx = [Context]::new()
	$ctx.environmentCode = $environMentCode
	$ctx.facilityCode = $facilityCode
	$ctx.peerFacilityCode = [EnvironmentAndFacilitiesInfo]::facilityPeersMap[$facilityCode]
	$ctx.subscriptionCode = $subscriptionCode
	$ctx.resourcePostfix = Construct-ResourcePostfix -environmentCode $environmentCode -facilityCode $facilityCode -subscriptionCode $subscriptionCode
	$ctx.peerResourcePostfix = Construct-ResourcePostfix -environmentCode $environmentCode -facilityCode $facilityPeersMap[$facilityCode] -subscriptionCode $subscriptionCode
	$ctx.sharedResourcePostfix = Construct-ResourcePostfix -environmentCode "al" -facilityCode $facilityCode -subscriptionCode $subscriptionCode
	$ctx.sharedpeerResourcePostfix = Construct-ResourcePostfix -environmentCode "al" -facilityCode $facilityPeersMap[$facilityCode] -subscriptionCode $subscriptionCode
	$ctx.location = $facilitiesLocationMap[$facilityCode]
	$ctx.peerLocation = $facilitiesLocationMap[$ctx.peerFacilityCode]
	$ctx.vnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.facilityCode)
	$ctx.peerVnetCidrPrefix = [EnvironmentAndFacilitiesInfo]::CalculateVnetCidrPrefix($ctx.environmentCode, $ctx.peerFacilityCode)

	return $ctx
}

function Ensure-LoggedIntoAzureAccount{
	if (!$loggedIn)
	{
		Login-AzureAccount
		if (!$global:loggedIn){
			throw "Could not log in to azure"
		}
	}
}

function Login-AzureAccount{
	if ($loggedIn){
		return
	}

	$profileFile = $currentDir + "\Deployment-Scripts\" + $loginAccount['profileFile']

	Write-Host "Logging into azure account"
	Import-AzureRmContext -Path $profileFile | Out-Null
	Write-Host "Successfully loaded the profile file: " $profileFile -ForegroundColor Green

	Write-Host "Setting subscription..."
	Get-AzureRmSubscription –SubscriptionName $loginAccount['subscriptionName'] | Select-AzureRmSubscription | Out-Null
	Write-Host "Set Azure Subscription for session complete" -ForegroundColor Green

	$global:loggedIn = $true
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
		[string]$category,
		[bool]$usePeer=$false,
		[string]$location,
		[string]$resourceGroupName
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx $usePeer $location $groupName -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	if ($ctx -ne $null){
		$resourceGroupName = $ctx.CreateResourceGroupName($category, $usePeer)
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

	Ensure-LoggedIntoAzureAccount

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
	Write-Host "In: " $MyInvocation.MyCommand -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Write-Host "Executing template deployment: " $resourceGroupName $templateFile
	Write-Host "Using parameters: " + $parameters

	$templateFile = $currentDir + "\Deployment-Scripts\ARM\" + $templateFile
	
	New-AzureRmResourceGroupDeployment `
		-Name ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
		-ResourceGroupName $resourceGroupName `
		-TemplateFile $templateFile `
		-TemplateParameterObject $parameters `
		-Force -Verbose `
		-ErrorVariable errorMessages

	if ($errorMessages) {
		Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
	}

	Write-Host "Out: " $MyInvocation.MyCommand -ForegroundColor Green
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

	Ensure-LoggedIntoAzureAccount

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

	Ensure-LoggedIntoAzureAccount

	$account = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue
	if (!$account)
	{
		Write-Host "Storage account did not exist.  Creating..."
		Deploy-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
		Write-Host "Created: " $storageAccountName
	}
	else
	{
		Write-Host $groupName "already exists"
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

	Ensure-LoggedIntoAzureAccount

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

	Ensure-LoggedIntoAzureAccount

	Ensure-ResourceGroup -ctx $ctx -usePeer $usePeer -category "vnet"

	$parameters = @{
		"vnetName" = $ctx.environmentCode
		"vnetCidrPrefix" = $ctx.GetVnetCidrPrefix($usePeer)
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
	}

	$resourceGroupName = $ctx.CreateResourceGroupName("vnet", $usePeer)
	Execute-Deployment -templateFile "arm-vnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $westVnetCidrPrefix $eastVnetCidrPrefix -ForegroundColor Green
}

function Deploy-PIPs {
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = $ctx.CreateResourceGroupName("pips", $usePeer)
	$location = $ctx.GetLocation($usePeer)
	Ensure-ResourceGroup -location $location -groupName $resourceGroupName

	$parameters = @{
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
	}

	Execute-Deployment -templateFile "arm-pips-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}

function Deploy-NSGs {
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = $ctx.CreateResourceGroupName("nsgs", $usePeer)
	$location = $ctx.GetLocation($usePeer)
	Ensure-ResourceGroup -location $location -groupName $resourceGroupName

	$parameters = @{
		"vnetCidrPrefix" = $ctx.GetVnetCidrPrefix($usePeer)
		"resourceNamePostfix" = $ctx.GetResourcePostfix($usePeer)
	}

	Execute-Deployment -templateFile "arm-nsgs-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}

function Deploy-VPN{
	param(
		[string]$facility,
		[string]$environment,
		[string]$westVnetCidrPrefix,
		[string]$eastVnetCidrPrefix
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $westVnetCidrPrefix $eastVnetCidrPrefix -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "vnet"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
		"westVnetCidrPrefix" = $westVnetCidrPrefix
		"eastVnetCidrPrefix" = $eastVnetCidrPrefix
	}

	Execute-Deployment -templateFile "arm-vpn-deploy.json" -resourceGroupName $resourceGroupName -parameters $parameters
	#Execute-Deployment -templateFile "arm-vpn-connections-deploy.json" -resourceGroupName $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $westVnetCidrPrefix $eastVnetCidrPrefix -ForegroundColor Green
}

function Deploy-DB{
	param(
		[string]$facility,
		[string]$environment,
		[string]$diagnosticStorageAccountKey,
		[string]$installersStgAcctKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword,
		[string]$saUserName,
		[string]$saPassword,
		[string]$vmCustomData,
		[string]$loginUserName,
		[string]$loginPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey $dbAdminUserName -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "db"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
		"installersStgAcctKey" = $installersStgAcctKey
		"saUserName" = $saUserName
		"saPassword" = $saPassword
		"vmCustomData" = $vmCustomData
		"loginUserName" = $loginUserName
		"loginPassword" = $loginPassword
	}

	Execute-Deployment -templateFile "arm-db-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-Web{
	param(
		[string]$environment,
		[string]$facility,
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
		[string]$fileShareName
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "web"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
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
	}

	Execute-Deployment -templateFile "arm-vmssweb-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

<#
TODO: Put this stuff in the context
function Check-EnvironmentCode{
	param([string]$environmentCode)

	return $environmentConfig
}

function Check-FacilityCode{
	param([string]$facilityCode)

	if ($facilityCode.Length -ne 1){
		throw "Environment code length must be exactly one character"
	}

	if (!$facilityInfo['validCodes'] -contains $code){
		throw "Invalid facility code.  Must be one of: " + $facilityInfo['validCodes']
	}

	$facilityConfig = @{
		"code" = $facilityCode
		"name" = $facilityInfo['codeNameMap'][$facilityCode]
		"cidrValue" = $facilityInfo['cidrValues'][$facilityCode]
		"location" = $facilityInfo['locationMap'][$facilityCode]
	}

	return $facilityConfig
}

function Check-EnvironmentAndFacility{
	param(
		[string]$environmentCode,
		[string]$facilityCode
	)

	$environmentConfig = Check-EnvironmentCode -environmentCode $environmentCode
	$facilityConfig = Check-FacilityCode -facilityCode $facilityCode
	$cidr1 = $environmentConfig['cidrValue'] 
	$cidr2 = $facilityConfig['cidrValue']
	$cidr = $cidr1 + $cidr2

	Write-Host $([Convert]::ToString($cidr, 2))

	$result = @{
		"environmentConfig" = $environmentConfig
		"facilityConfig" = $facilityConfig
		"cidrPrefix" = "10." + $cidr + "."
	}

	return $result
}
#>
function Deploy-Ftp{
	param(
		[string]$environment,
		[string]$facility,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "ftp"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
	}

	Execute-Deployment -templateFile "arm-vmssftp-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-Jump{
	param(
		[string]$facility,
		[string]$environment,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "jump"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
	}

	Execute-Deployment -templateFile "arm-jump-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Deploy-Admin{
	param(
		[string]$facility,
		[string]$environment,
		[string]$diagnosticStorageAccountKey,
		[string]$dataDogApiKey,
		[string]$adminUserName,
		[string]$adminPassword
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "admin"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
		"diagStorageAccountKey" = $diagnosticStorageAccountKey
		"dataDogApiKey" = $dataDogApiKey
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
	}

	Execute-Deployment -templateFile "arm-admin-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
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

	Ensure-LoggedIntoAzureAccount

	Ensure-ResourceGroup -ctx $ctx -category "dbdi"
	Ensure-ResourceGroup -ctx $ctx -category "disks"

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

	$deployResourceGroupName = $ctx.CreateResourceGroupName("dbdi", $usePeer)
	Execute-Deployment -templateFile "arm-db-disk-init-vm-deploy.json" -resourceGroup $deployResourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.GetResourcePostfix($usePeer) -ForegroundColor Green
}

function Create-KeyVault{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = $ctx.CreateResourceGroupName("svc", $usePeer)
	$location = $ctx.GetLocation($usePeer)
	Ensure-ResourceGroup -location $location -groupName $resourceGroupName

	$resourcePostfix = $ctx.GetResourcePostfix($usePeer)

	$keyVaultName = "kv-svc-" + $resourcePostfix

	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
	if (!$keyVault)
	{
		Write-Host "Did not find KeyVault, so trying to create..."
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

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$keyVaultName = "kv-svc-" + $resourcePostfix

	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
	return $keyVault
}

function Remove-KeyVault{
	param(
		[string]$facility,
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$keyVaultName = "kv-svc-" + $resourcePostfix
	$location = Get-FacilityLocation -facility $facility

	$keyVault = Remove-AzureRmKeyVault -Force -VaultName $keyVaultName -Location $location -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
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

	Ensure-LoggedIntoAzureAccount

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

	Ensure-LoggedIntoAzureAccount

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
	
	$text = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName).SecretValueText

	Write-Host "Out: " $MyInvocation.MyCommand $KeyVaultName $SecretName -ForegroundColor Green 

	return $text
}

function Add-LocalCertificateToKV{
	param(
		[string]$keyVaultName,
		[string]$pfxFile,
		[string]$password,
		[string]$secretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $keyVaultName $certName $pfxFile -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$pfxFilePath = $currentDir + "\Deployment-Scripts\" + $pfxFile
	$flag = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
	$collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection 
	$collection.Import($pfxFilePath, $password, $flag)
	$pkcs12ContentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12
	$clearBytes = $collection.Export($pkcs12ContentType)
	$fileContentEncoded = [System.Convert]::ToBase64String($clearBytes)
	$secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText –Force
	$secretContentType = 'application/x-pkcs12'

	Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secret -ContentType $secretContentType

	Write-Host "Out: " $MyInvocation.MyCommand $keyVaultName $certName $pfxFile -ForegroundColor Green
}


function Create-KeyVaultSecrets{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)

	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$webSslCertificateSecretName = "WebSslCertificate"
	$octoUrl = "https://pip-octo-wspdpr.westus.cloudapp.azure.com" 
	$octoApiKey = "API-SFVPQ7CI5DELMEXG0Y3XZKLE8II"
	$dataDogApiKey = "691f4dde2b1a5e9a9fd5f06aa3090b87"
	$pfxfile = "workspace.pfx"
	$pfxfilePassword = "workspace"

	$resourceGroupName = $ctx.CreateResourceGroupName("svc", $usePeer)
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
	
	$diagAcctResourceGroupName = $ctx.CreateResourceGroupName("diag", $usePeer)
	$diagStorageAccountName = $ctx.CreateStorageAccountName("diag", $usePeer)
	$diagStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $diagAcctResourceGroupName -AccountName $diagStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey" -SecretValue $diagStgAcctKeys.Value[0]

	$installersAcctResourceGroupName = $ctx.CreateSharedResourceGroupName("installers", $usePeer)
	$installersStorageAccountName = $ctx.CreateSharedStorageAccountName("installers", $usePeer)
	$installersStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $installersAcctResourceGroupName -AccountName $installersStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey" -SecretValue $installersStgAcctKeys.Value[0]

	$fileShareAcctResourceGroupName = $ctx.CreateResourceGroupName("files", $usePeer)
	$fileShareStorageAccountName = $ctx.CreateStorageAccountName("files", $usePeer)
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
		[string]$facility,
		[string]$environment
	)
	
	Remove-KeyVault -environment $environment -facility $facility
	Build-KeyVault -environment $environment -facility $facility
}

function Create-Core{
	param(
		[Context]$ctx
	)
	
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $ctx.vnetCidrPrefix $ctx.peerVnetCidrPrefix -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount
	<#
	$keyVaultNamePR = "kv-svc-" + $ctx.GetResourcePostfix($false)
	$keyVaultNameDR = "kv-svc-" + $ctx.GetResourcePostfix($true)

	# at this point, this only uses values in the primary KV
	$dbAdminUserName =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbServerAdminName"
	$dbAdminPassword =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbServerAdminPassword"
	$webAdminUserName =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "WebVmssServerAdminName"
	$webAdminPassword =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "WebVmssServerAdminPassword"
	$ftpAdminUserName =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "FtpVmssServerAdminName"
	$ftpAdminPassword =   Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "FtpVmssServerAdminPassword"
	$jumpAdminUserName =  Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "JumpServerAdminName"
	$jumpAdminPassword =  Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "JumpServerAdminPassword"
	$adminAdminUserName = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "AdminServerAdminName"
	$adminAdminPassword = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "AdminServerAdminPassword"
	$dbSaUserName =       Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbSaUserName"
	$dbSaPassword =       Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbSaPassword"
	$dbLoginUserName =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbLoginUserName"
	$dbLoginPassword =    Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DbLoginPassword"

	$diagStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DiagStorageAccountKey"
	$installersStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "InstallersStorageAccountKey"
	$fileShareStorageAccountKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "FileShareStorageAccountKey"

	$webSslCertificatePR = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "WebSslCertificate"
	$webSslCertificateIdPR = $webSslCertificatePR.Id

	$octoApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "OctoApiKey"
	$octoUrl = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "OctoUrl"
	$dataDogApiKey = Get-KeyVaultSecret -KeyVaultName $keyVaultNamePR -SecretName "DataDogApiKey"
	$webVmCustomData = "{'octpApiKey': '" + $octoApiKey + "', 'octoUrl': " + $octoUrl + "', 'fileShareKey': '" + $fileShareStorageAccountKey + "'}"
	$dbVmCustomData = "{'installersStgAcctKey': '" + $fileShareStorageAccountKey + "', 'dbSaUserName': '" + $dbSaUserName + "', 'dbSaPassword': '" + $dbSaPassword + "'}"

	$webVmCustomDataBytes = [System.Text.Encoding]::UTF8.GetBytes($webVmCustomData)
	$webVmCustomDataB64 = [System.Convert]::ToBase64String($webVmCustomDataBytes)
	$dbVmCustomDataBytes = [System.Text.Encoding]::UTF8.GetBytes($dbVmCustomData)
	$dbVmCustomDataB64 = [System.Convert]::ToBase64String($dbVmCustomDataBytes)

	$fileStgAcctNamePR = $ctx.CreateStorageAccountName("files", $false)
	$fileStgAcctNameDR = $ctx.CreateStorageAccountName("files", $true)
	#>
	#Deploy-NSGs -ctx $ctx
	#Deploy-NSGs -ctx $ctx -usePeer $true
	#Deploy-PIPs -ctx $ctx 
	#Deploy-PIPs -ctx $ctx -usePeer $true
	#Deploy-VNet -ctx $ctx -usePeer $false
	Deploy-VNet -ctx $ctx -usePeer $true

	#Deploy-VNet -facility "dr"      -environment $environment -westVnetCidrPrefix $vnetPrimaryCidrPrefix -eastVnetCidrPrefix $vnetDrCidrPrefix
	
	#Deploy-VPN -facility "primary" -environment $environment -westVnetCidrPrefix $vnetPrimaryCidrPrefix -eastVnetCidrPrefix $vnetDrCidrPrefix

	# need to make sure we have these storage accounts
	#Ensure-StorageAccount -facility "primary" -environment $environment -resourceCategory "bootdiag"
	#Ensure-StorageAccount -facility "dr" -environment $environment -resourceCategory "bootdiag"
	#Ensure-StorageAccount -facility "primary" -environment $environment -resourceCategory "diag"
	#Ensure-StorageAccount -facility "dr" -environment $environment -resourceCategory "diag"

	#Deploy-DB -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $dbAdminUserName -adminPassword $dbAdminPassword -installersStgAcctKey $installersStorageAccountKey -vmCustomData $dbVmCustomDataB64 -saUserName $dbSaUserName -saPassword $dbSaPassword -loginUserName $dbLoginUserName -loginPassword $dbLoginPassword
	#Deploy-Web -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $webAdminUserName -adminPassword $webAdminPassword -sslCertificateUrl $webSslCertificateIdPR -vmCustomData $webVmCustomDataB64 -octoUrl $octoUrl -octoApiKey $octoApiKey -fileShareKey $fileShareStorageAccountKey -fileStgAcctName $fileStgAcctNamePR -fileShareName $fileShareName
	#Deploy-Ftp -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $ftpAdminUserName -adminPassword $ftpAdminPassword
	#Deploy-Jump -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -dataDogApiKey $dataDogApiKey -adminUserName $jumpAdminUserName -adminPassword $jumpAdminPassword
	#Deploy-Admin -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -dataDogApiKey $dataDogApiKey -adminUserName $adminAdminUserName -adminPassword $adminAdminPassword
	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $ctx.vnetCidrPrefix $ctx.peerVnetCidrPrefix -ForegroundColor Green
}

function Teardown-Core{
	param(
		[Context]$ctx,
		[bool]$includeServices=$false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Teardown-CoreEntities -ctx $ctx -usePeer $false -includeServices $includeServices
	Teardown-CoreEntities -ctx $ctx -usePeer $true -includeServices $includeServices

	Write-Host "Out: " $MyInvocation.MyCommand $ctx -ForegroundColor Green
}

function Teardown-CoreEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[bool]$includeServices=$false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

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
			Delete-ResourceGroup -ctx $ctx -usePeer $peer -category $rc
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

	Ensure-LoggedIntoAzureAccount

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

	Ensure-LoggedIntoAzureAccount

	$resourceCategories = @("bootdiag", "diag")

	$location = $ctx.GetLocation($usePeer)

	foreach ($rc in $resourceCategories){
		$resourceGroupName = $ctx.CreateResourceGroupName($rc, $usePeer)
		$storageAccountName = $ctx.CreateStorageAccountName($rc, $usePeer)
		Ensure-ResourceGroup -location $location -groupName $resourceGroupName
		Ensure-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	}

	Write-Host "Out: " $MyInvocation.MyCommand $context.resourcePostfix $context.peerFacilityResourcePrefix $usePeer $multiFacility -ForegroundColor Green
}

function Teardown-DiagnosticsEntities{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Teardown-DiagnosticsEntitiesInFacility -environment $environment -facility $facility 

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Teardown-DiagnosticsEntitiesInFacility{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$group1 = @("bootdiag", "diag")

	foreach ($rc in $group1){
		Teardown-ResourceCategory -environment $environment -facility $facility -resourceCategory $rc
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Teardown-SvcInEnvironment{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$facilities = @("primary", "dr")
	$group1 = @("svc")

	foreach ($rc in $group1){
		foreach ($facility in $facilities){
			Teardown-ResourceCategoryInFacility -environment $environment -facility $facility -resourceCategory $rc
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Teardown-ResourceCategory{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[string]$category
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx $usePeer $category  -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = $ctx.CreateResourceGroupName($category, $usePeer)

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

	Write-Host "In: " $MyInvocation.MyCommand $ctx $usePeer $category  -ForegroundColor Green
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

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = $ctx.CreateResourceGroupName("svc", $usePeer)
	$location = $ctx.GetLocation($usePeer)
	Ensure-ResourceGroup -location $location -groupName $resourceGroupName

	Build-KeyVault -ctx $ctx

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}
function Create-BaseEnvironment{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false,
		[bool]$multiFacility=$true
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer $multiFacility -ForegroundColor Green

	$usages = $ctx.GetFacilityUsages$usePeer, $multiFacility)

	Ensure-LoggedIntoAzureAccount

	foreach ($usePeer in $usages){
		Create-BaseEnvironmentEntities -ctx $ctx -usePeer $usePeer
	}

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerFacilityResourcePrefix $usePeer $multiFacility -ForegroundColor Green
}

function Create-BaseEnvironmentEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer=$false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.resourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Ensure-ResourceGroup -ctx $ctx -category "disks"
	#Create-DiagnosticsEntities -ctx $ctx -usePeer $usePeer
	#Create-AzureFilesEntities -ctx $ctx -usePeer $usePeer
	#Create-ServicesEntities -ctx $ctx -usePeer $usePeer
	Deploy-DatabaseDiskViaInitVM -ctx $ctx -usePeer $usePeer

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-AzureFilesEntities{
	param(
		[Context]$ctx,
		[bool]$usePeer = $false
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$location = $ctx.GetLocation($usePeer)
	$resourceGroupName = $ctx.CreateResourceGroupName("files", $usePeer)
	$storageAccountName = $ctx.CreateStorageAccountName("files", $usePeer)

	Ensure-ResourceGroup -location $location -groupName $resourceGroupName
	Ensure-StorageAccount -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
	Create-AzureFilesShare -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

	Write-Host "Out: " $MyInvocation.MyCommand $ctx.resourcePostfix $ctx.peerResourcePostfix $usePeer -ForegroundColor Green
}
<#
function Create-AzureFilesEntitiesInFacility{
	param(
		[Context]$ctx,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $ctx -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

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

	Ensure-LoggedIntoAzureAccount

	$storageAccounttKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName
	$storageAccountKey = $storageAccounttKeys.Value[0]

	$context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
	New-AzureStorageShare -Name $fileSharesName -Context $context
	Set-AzureStorageShareQuota -ShareName $fileSharesName -Context $context -Quota $fileSharesQuota

	Write-Host "Out: " $MyInvocation.MyCommand $resourceGroupName $storageAccountName -ForegroundColor Green
}

$ctx = Login-WorkspacePrimaryProd
#Create-BaseEnvironment -ctx $ctx -multiFacility $true

#Create-AzureFilesEntitiesInFacility -environment "prod" -facility "primary"
#Create-ServicesEntities -environment "prod" -facility "primary"
#Remove-KeyVault -environment "prod" -facility "primary"
#Build-KeyVault -environment "prod" -facility "primary"
#Rebuild-KeyVault -environment "prod" -facility "primary"
#Create-Core -ctx $ctx 
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
Teardown-Core -ctx $ctx
					
#Add-CertificateToKV -facility "primary" -environment "prod" -pfxFile "workspace.pfx" -password "workspace" -secretName "foo"

#Create-KeyVaultSecrets -facility "primary" -environment "prod"

Class AzureResource
{
	[string]$Subscription
	[string]$ResourceType
	[string]$ResourceId
	[string]$ResourceGroup
	[string]$Location
	[string]$Name
	[string]$ServiceName
	[string]$VNet
	[string]$Subnet
	[string]$Size
	[string]$Status
}

function Get-AllAzureResources{
	Ensure-LoggedIntoAzureAccount
	Get-AzureRmResource
}

#Get-AllAzureResources