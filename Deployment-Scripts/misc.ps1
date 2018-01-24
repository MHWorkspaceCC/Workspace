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
