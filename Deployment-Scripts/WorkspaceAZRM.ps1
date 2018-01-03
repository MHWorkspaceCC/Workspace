$loggedIn = $false

$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$templateFileLocation = $currentDir

$facilitiesLocationMap = @{
	"primary" = "westus"
	"dr" = "eastus"
}

$locationPostfixMap = @{
	"primary" = "pr"
	"dr" = "dr"
}

$facilitiesPostfixCodeMap = @{
	"primary" = "pr"
	"dr" = "dr"
}

$environmentsPostfixCodeMap = @{
	"prod" = "pd"
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


$environmentsInfo = @{
	"validCodes" = "pdtsqc"
	"codeNameMap" = @{
		"p" = "Production"
		"d" = "Development"
		"t" = "Test"
		"s" = "Staging"
		"q" = "QA"
		"c" = "Canary"
	}
	"ciderValue" = @{
		"p" = 0 -shl 4
		"d" = 1 -shl 4 
		"t" = 2 -shl 4
		"s" = 3 -shl 4
		"q" = 4 -shl 4
		"c" = 5 -shl 4
	}
}

$facilityInfo = @{
	"validCodes" = "pd"
	"codeNameMap" = @{
		"p" = "Primary"
		"d" = "Disaster Recovery"
	}
	"ciderValue" = @{
		"p" = 0 -shl 2
		"d" = 1 -shl 2 
	}
	"locationMap" = @{
		"p" = "westus"
		"d" = "eastus"
	}
}

function Construct-ResourcePostfix{
	param(
		[string]$environment,
		[string]$facility
	)

	return "ws" + $environmentsPostfixCodeMap[$environment] + $facilitiesPostfixCodeMap[$facility]
}

function Ensure-LoggedIntoAzureAccount{
	if (!$loggedIn)
	{
		Login-AzureAccount
	}
}

function Login-AzureAccount{
	if (!$loggedIn){
		$profileFile = $currentDir + "\Deployment-Scripts\" + "azureprofile.json"

		Write-Host "Logging into azure account"
		Import-AzureRmContext -Path $profileFile | Out-Null
		Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

		Write-Host "Setting subscription..."
		$subscriptionName = "Visual Studio Enterprise"
		Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  | Out-Null
		Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green

		$global:loggedIn = $true
	}
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
		[string]$facility,
		[string]$groupName
	)
	Write-Host "In: " $MyInvocation.MyCommand $facility $groupName -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$location = Get-FacilityLocation -facility $facility
	
	$rg = Get-AzureRmResourceGroup -Name $groupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue

	if (!$rg)
	{
		Write-Host "Resource group did not exist.  Creating..."
		New-AzureRmResourceGroup -Name $groupName -Location $location
		Write-Host "Created " $groupName
	}
	else
	{
		Write-Host $groupName "already exists"
	}

	Write-Host "Out: " $MyInvocation.MyCommand $facility $groupName -ForegroundColor Green
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

function Create-StorageAccount{
	param(
		[string]$facility,
		[string]$environment,
		[string]$resourceCategory
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $environment $resouceCategory -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory $resourceCategory
	$storageAccountName = Construct-StorageAccountName -environment $environment -facility $facility -resourceCategory $resourceCategory

	$parameters = @{
		"storageAccountName" = $storageAccountName
	}

	Execute-Deployment -templateFile "arm-stgaccount-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment $storageAccountName -ForegroundColor Green
}

function Ensure-StorageAccount{
	param(
		[string]$facility,
		[string]$environment,
		[string]$resourceCategory
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $environment $resouceCategory -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory $resourceCategory
	$storageAccountName = Construct-StorageAccountName -environment $environment -facility $facility -resourceCategory $resourceCategory

	$account = Get-AzureStorageAccount -StorageAccountName $storageAccountName
	if (!$account)
	{
		Write-Host "Storage account did not exist.  Creating..."
		Create-StorageAccount -facility $facility -environment $environment -resourceCategory $resourceCategory
		Write-Host "Created: " $storageAccountName
	}
	else
	{
		Write-Host $groupName "already exists"
	}


	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment $storageAccountName -ForegroundColor Green
}

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

function Deploy-VNet{
	param(
		[string]$location,
		[string]$facility,
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

	Execute-Deployment -templateFile "arm-vnet-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $westVnetCidrPrefix $eastVnetCidrPrefix -ForegroundColor Green
}

function Deploy-PIPs {
	param(
		[string]$environment,
		[string]$facility
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $resourceCategory -ForegroundColor Green

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "pips"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
	}

	Execute-Deployment -templateFile "arm-pips-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Deploy-NSGs {
	param(
		[string]$environment,
		[string]$facility
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "nsgs"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
	}

	Execute-Deployment -templateFile "arm-nsgs-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
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

function Check-EnvironmentCode{
	param([string]$environmentCode)

	if ($environmentCode.Length -ne 2){
		throw "Environment code length must be two characters"
	}
	$code = $environmentCode[0]
	if (!$environmentsInfo['validCodes'] -contains $code){
		throw "Invalid environment code.  Must be one of: " + $environmentsInfo['validCodes']
	}

	$instanceNumber = $environmentCode[1]
	if (!"0123456789" -contains $instanceNumber){
		throw "Instance number must be in 0123456789.  Given was: " + $instanceNumber
	}

	$environmentConfig = @{
		"code" = $environmentCode
		"instanceId" = $instanceNumber
		"name" = $environmentsInfo['codeNameMap'][$code]
		"ciderValue" = $environmentsInfo['ciderValue'][$code]
	}

	return $environmentConfig
}

function Check-FacilityCode{
	param([string]$facilityCode)

	if ($facilityCode.Length -ne 1){
		throw "Environment code length must be exactly one character"
	}

	$code = $facilityCode[0]
	if (!$facilityInfo['validCodes'] -contains $code){
		throw "Invalid facility code.  Must be one of: " + $facilityInfo['validCodes']
	}

	$facilityConfig = @{
		"code" = $facilityCode
		"name" = $facilityCode['codeNameMap'][$code]
		"ciderValue" = $facilityInfo['ciderValue'][$code]
		"location" = $facilityInfo['locationMap'][$code]
	}

	return $facilityConfig
}

Check-EnvironmentAndFacility{
	param(
		[string]$environmentCode,
		[string]$facilityCode
	)

	$environmentConfig = Check-EnvironmentCode -environmentCode $environmentCode
	$facilityConfig = Check-EnvironmentCode -environmentCode $facilityCode

	return @{
		"environmentConfig" = $environmentConfig
		"facilityConfig" = $facilityConfig
		"ciderPrefix" = "10." + ($environmentConfig['cidrValue'] + $facilityConfig['cidrValue')
	}
}

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
		[string]$facility,
		[string]$environment,
		[string]$databaseServerId="sql1",
		[string]$diskName="data1",
		[string]$dataDiskSku="Standard_LRS",
		[int]$dataDiskSizeInGB=32,
		[string]$adminUserName="wsadmin",
		[string]$adminPassword="Workspace!DbDiskInit!2018"
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "disks"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$parameters = @{
		"environment" = $environmentsPostfixCodeMap[$environment]
		"facility" = $facilitiesPostfixCodeMap[$facility]
		"databaseServerId" = $databaseServerId
		"diskName" = $diskName
		"dataDiskSku" = $dataDiskSku
		"dataDiskSizeInGB" = $dataDiskSizeInGB
		"adminUserName" = $adminUserName
		"adminPassword" = $adminPassword
	}

	Execute-Deployment -templateFile "arm-db-disk-init-vm-deploy.json" -resourceGroup $resourceGroupName -parameters $parameters

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $diagnosticStorageAccountKey $dataDogApiKey -ForegroundColor Green
}

function Create-KeyVault{
	param(
		[string]$facility,
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$location = Get-FacilityLocation -facility $facility

	$keyVaultName = "kv-svc-" + $resourcePostfix

	$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
	if (!$keyVault)
	{
		Write-Host "Did not find KeyVault, so trying to create..."
		$keyVault = New-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -Location $location -EnabledForDeployment
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

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

function Add-LocalCertificateToKV{
	param(
		[string]$facility,
		[string]$environment,
		[string]$pfxFile,
		[string]$password,
		[string]$secretName
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $certName $pfxFile -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$keyVaultName = "kv-svc-" + $resourcePostfix

	$pfxFilePath = $currentDir + "\Deployment-Scripts\" + $pfxFile
	$flag = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
	$collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection 
	$collection.Import($pfxFilePath, $password, $flag)
	$pkcs12ContentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12
	$clearBytes = $collection.Export($pkcs12ContentType)
	$fileContentEncoded = [System.Convert]::ToBase64String($clearBytes)
	$secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText –Force
	$secretContentType = 'application/x-pkcs12'

	Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $Secret -ContentType $secretContentType

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $certName $pfxFile -ForegroundColor Green
}


function Create-KeyVaultSecrets{
	param(
		[string]$facility,
		[string]$environment
	)

	Write-Host "In: " $MyInvocation.MyCommand $facility $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$webSslCertificateSecretName = "WebSslCertificate"
	$octoUrl = "https://pip-octo-wspdpr.westus.cloudapp.azure.com" 
	$octoApiKey = "API-SFVPQ7CI5DELMEXG0Y3XZKLE8II"
	$dataDogApiKey = "691f4dde2b1a5e9a9fd5f06aa3090b87"

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "svc"
	$resourcePostfix = Construct-ResourcePostfix -environment $environment -facility $facility
	$keyVaultName = "kv-svc-" + $resourcePostfix

	Add-LocalCertificateToKV -facility $facility -environment $environment -pfxFile "workspace.pfx" -password "workspace" -secretName $webSslCertificateSecretName

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
	
	$diagAcctResourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "diag"
	$diagStorageAccountName = Construct-StorageAccountName -environment $environment -facility $facility -resourceCategory "diag"
	$diagStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $diagAcctResourceGroupName -AccountName $diagStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DiagStorageAccountKey" -SecretValue $diagStgAcctKeys.Value[0]

	$installersAcctResourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "installers"
	$installersStorageAccountName = Construct-StorageAccountName -environment $environment -facility $facility -resourceCategory "installers"
	$installersStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $installersAcctResourceGroupName -AccountName $installersStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "InstallersStorageAccountKey" -SecretValue $installersStgAcctKeys.Value[0]

	$fileShareAcctResourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "files"
	$fileShareStorageAccountName = Construct-StorageAccountName -environment $environment -facility $facility -resourceCategory "files"
	$fileShareStgAcctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $installersAcctResourceGroupName -AccountName $installersStorageAccountName
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "FileShareStorageAccountKey" -SecretValue $fileShareStgAcctKeys.Value[0]

	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoUrl" -SecretValue $octoUrl
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "OctoApiKey" -SecretValue $octoApiKey
	Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "DataDogApiKey" -SecretValue $dataDogApiKey

	Write-Host "Out: " $MyInvocation.MyCommand $facility $environment -ForegroundColor Green
}


function Build-KeyVault{
	param(
		[string]$facility,
		[string]$environment
	)
	
	Create-KeyVault -environment $environment -facility $facility
	Create-KeyVaultSecrets -environment $environment -facility $facility
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
		[string]$environment,
		[string]$vnetPrimaryCidrPrefix = "10.1.",
		[string]$vnetDrCidrPrefix = "10.2."
	)
	
	Write-Host "In: " $MyInvocation.MyCommand $environment  -ForegroundColor Green
	Write-Host "Environment: " $environment
	Write-Host "Primary CIDR Prefix: " $vnetPrimaryCidrPrefix
	Write-Host "DR CIDR Prefix: " $vnetDrCidrPrefix

	Ensure-LoggedIntoAzureAccount

	$resourcePostfixPR = Construct-ResourcePostfix -environment $environment -facility "primary"
	$resourcePostfixDR = Construct-ResourcePostfix -environment $environment -facility "dr"
	$keyVaultNamePR = "kv-svc-" + $resourcePostfixPR
	$keyVaultNameDR = "kv-svc-" + $resourcePostfixDR

	$dbAdminUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DbServerAdminName").SecretValueText
	$dbAdminPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DbServerAdminPassword").SecretValueText
	$webAdminUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "WebVmssServerAdminName").SecretValueText
	$webAdminPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "WebVmssServerAdminPassword").SecretValueText
	$ftpAdminUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "FtpVmssServerAdminName").SecretValueText
	$ftpAdminPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "FtpVmssServerAdminPassword").SecretValueText
	$jumpAdminUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "JumpServerAdminName").SecretValueText
	$jumpAdminPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "JumpServerAdminPassword").SecretValueText
	$adminAdminUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "AdminServerAdminName").SecretValueText
	$adminAdminPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "AdminServerAdminPassword").SecretValueText
	$dbSaUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DbSaUserName").SecretValueText
	$dbSaPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DbSaPassword").SecretValueText
	$dbLoginUserName = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DbLoginUserName").SecretValueText
	$dbLoginPassword = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DbLoginPassword").SecretValueText

	$diagStorageAccountKey = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DiagStorageAccountKey").SecretValueText
	$installersStorageAccountKey = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "InstallersStorageAccountKey").SecretValueText
	$fileShareStorageAccountKey = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "FileShareStorageAccountKey").SecretValueText

	$webSslCertificatePR = Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "WebSslCertificate"
	$webSslCertificateIdPR = $webSslCertificatePR.Id

	$octoApiKey = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "OctoApiKey").SecretValueText
	$octoUrl = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "OctoUrl").SecretValueText
	$dataDogApiKey = $(Get-AzureKeyVaultSecret -VaultName $keyVaultNamePR -Name "DataDogApiKey").SecretValueText
	$webVmCustomData = "{'octpApiKey': '" + $octoApiKey + "', 'octoUrl': " + $octoUrl + "', 'fileShareKey': '" + $fileShareStorageAccountKey + "'}"
	$dbVmCustomData = "{'installersStgAcctKey': '" + $fileShareStorageAccountKey + "', 'dbSaUserName': '" + $dbSaUserName + "', 'dbSaPassword': '" + $dbSaPassword + "'}"

	$webVmCustomDataBytes = [System.Text.Encoding]::UTF8.GetBytes($webVmCustomData)
	$webVmCustomDataB64 = [System.Convert]::ToBase64String($webVmCustomDataBytes)
	$dbVmCustomDataBytes = [System.Text.Encoding]::UTF8.GetBytes($dbVmCustomData)
	$dbVmCustomDataB64 = [System.Convert]::ToBase64String($dbVmCustomDataBytes)

	$fileStgAcctNamePR = Construct-StorageAccountName -facility "primary" -environment $environment -resourceCategory "files"
	$fileStgAcctNameDR = Construct-StorageAccountName -facility "primary" -environment $environment -resourceCategory "files"
	$fileShareName = "workspace-file-storage"

	#Ensure-AllResourceGroups -environment $environment -facility "primary" 
	#Ensure-AllResourceGroups -environment $environment -facility "dr" 

	#Deploy-NSGs -facility "primary" -environment $environment
	#Deploy-NSGs -facility "dr"      -environment $environment
	#Deploy-PIPs -facility "primary" -environment $environment
	#Deploy-PIPs -facility "dr"      -environment $environment
	#Deploy-VNet -facility "primary" -environment $environment -westVnetCidrPrefix $vnetPrimaryCidrPrefix -eastVnetCidrPrefix $vnetDrCidrPrefix
	#Deploy-VNet -facility "dr"      -environment $environment -westVnetCidrPrefix $vnetPrimaryCidrPrefix -eastVnetCidrPrefix $vnetDrCidrPrefix
	
	#Deploy-VPN -facility "primary" -environment $environment -westVnetCidrPrefix $vnetPrimaryCidrPrefix -eastVnetCidrPrefix $vnetDrCidrPrefix

	# need to make sure we have these storage accounts
	#Ensure-StorageAccount -facility "primary" -environment $environment -resourceCategory "bootdiag"
	#Ensure-StorageAccount -facility "dr" -environment $environment -resourceCategory "bootdiag"
	#Ensure-StorageAccount -facility "primary" -environment $environment -resourceCategory "diag"
	#Ensure-StorageAccount -facility "dr" -environment $environment -resourceCategory "diag"

	Deploy-DB -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $dbAdminUserName -adminPassword $dbAdminPassword -installersStgAcctKey $installersStorageAccountKey -vmCustomData $dbVmCustomDataB64 -saUserName $dbSaUserName -saPassword $dbSaPassword -loginUserName $dbLoginUserName -loginPassword $dbLoginPassword
	Deploy-Web -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $webAdminUserName -adminPassword $webAdminPassword -sslCertificateUrl $webSslCertificateIdPR -vmCustomData $webVmCustomDataB64 -octoUrl $octoUrl -octoApiKey $octoApiKey -fileShareKey $fileShareStorageAccountKey -fileStgAcctName $fileStgAcctNamePR -fileShareName $fileShareName
	#Deploy-Ftp -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -adminUserName $ftpAdminUserName -adminPassword $ftpAdminPassword
	#Deploy-Jump -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -dataDogApiKey $dataDogApiKey -adminUserName $jumpAdminUserName -adminPassword $jumpAdminPassword
	#Deploy-Admin -facility "primary" -environment $environment -diagnosticStorageAccountKey $diagStorageAccountKey -dataDogApiKey $dataDogApiKey -dataDogApiKey $dataDogApiKey -adminUserName $adminAdminUserName -adminPassword $adminAdminPassword
}

function Teardown-Core{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Teardown-CoreInFacility -environment $environment -facility "primary"
	Teardown-CoreInFacility -environment $environment -facility "dr" 

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Teardown-CoreInFacility{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$group1 = @("admin", "jump", "ftp", "web", "db")
	$group2 = @("vnet", "pips", "nsgs")
	$groups = @($group1, $group2)

	foreach ($group in $groups){
		foreach ($rc in $group){
			Teardown-ResourceCategory -environment $environment -facility $facility -resourceCategory $rc
		}
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Create-DiagnosticsEntities{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Create-DiagnosticsEntitiesInFacility -environment $environment -facility "primary"
	Create-DiagnosticsEntitiesInFacility -environment $environment -facility "dr"

	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Create-DiagnosticsEntitiesInFacility{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupNameBD = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory "bootdiag"
	$resourceGroupNameD = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory "diag"

	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupNameBD
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupNameD

	Ensure-StorageAccount -facility $facility -environment $environment -resourceCategory "bootdiag"
	Ensure-StorageAccount -facility $facility -environment $environment -resourceCategory "diag"

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
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

function Teardown-ResourceCategoryInFacility{
	param(
		[string]$environment,
		[string]$facility,
		[string]$resourceCategory
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility $resourceCategory -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory $resourceCategory

	Write-Host "Getting resource group: " $resourceGroupName
	$rg = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue

	if (!$rg)
	{
		Write-Host "Resource group did not exist: " $resourceGroupName
	}
	else
	{
		Write-Host "Deleting resource group: " $resourceGroupName
		Remove-AzureRmResourceGroup -Name $resourceGroupName -Force | Out-Null
		Write-Host "Deleted resource group: " $resourceGroupName
	}

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility $resourceCategory -ForegroundColor Green
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
		[string]$facility,
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory "svc"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName

	Build-KeyVault -facility $facility -environment $environment

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-BaseEnvironment{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Create-BaseEnvironmentInFacility -environment $environment "primary"
	Create-BaseEnvironmentInFacility -environment $environment "dr"

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-BaseEnvironmentInFacility{
	param(
		[string]$facility,
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Create-Diagnostics -environment $environment -facility $facility
	Create-ServicesEntities -facility $facility -environment $environment
	Create-AzureFilesEntities -facility $facility -environment $environment

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-AzureFilesEntities{
	param(
		[string]$environment
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	Create-AzureFilesEntitiesInFacility -environment $environment -facility "primary"
	Create-AzureFilesEntitiesInFacility -environment $environment -facility "dr"
	
	Write-Host "Out: " $MyInvocation.MyCommand $environment -ForegroundColor Green
}

function Create-AzureFilesEntitiesInFacility{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -facility $facility -environment $environment -resourceCategory "files"
	Ensure-ResourceGroup -facility $facility -groupName $resourceGroupName
	Ensure-StorageAccount -environment $environment -facility $facility -resourceCategory "files"
	Create-AzureFilesShareInFacility -environment $environment -facility $facility

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

function Create-AzureFilesShareInFacility{
	param(
		[string]$environment,
		[string]$facility
	)
	Write-Host "In: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green

	Ensure-LoggedIntoAzureAccount

	$resourceGroupName = Construct-ResourceGroupName -environment $environment -facility $facility -resourceCategory "files"
	$storageAccountName = Construct-StorageAccountName -environment $environment -facility $facility -resourceCategory "files"
	$storageAccounttKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName
	$storageAccountKey = $storageAccounttKeys.Value[0]

	$context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
	New-AzureStorageShare -Name "workspace-file-storage" -Context $context
	Set-AzureStorageShareQuota -ShareName "workspace-file-storage" -Context $context -Quota 10 # 10GB quota 

	Write-Host "Out: " $MyInvocation.MyCommand $environment $facility -ForegroundColor Green
}

#Create-AzureFilesEntitiesInFacility -environment "prod" -facility "primary"
#Create-ServicesEntities -environment "prod" -facility "primary"
#Remove-KeyVault -environment "prod" -facility "primary"
#Build-KeyVault -environment "prod" -facility "primary"
#Rebuild-KeyVault -environment "prod" -facility "primary"
Create-Core -environment "prod" -vnetPrimaryCidrPrefix "10.1." -vnetDrCidrPrefix "10.2."
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
#Teardown-EntireEnvironment -environment "prod"
					
#Add-CertificateToKV -facility "primary" -environment "prod" -pfxFile "workspace.pfx" -password "workspace" -secretName "foo"

#Create-KeyVaultSecrets -facility "primary" -environment "prod"
