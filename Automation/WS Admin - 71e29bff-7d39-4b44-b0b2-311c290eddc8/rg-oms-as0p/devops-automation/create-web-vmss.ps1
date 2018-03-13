function Create-WsWebVMSS{
    param(
		[switch]$secondary,
		[string]$diagnosticStorageAccountName,
		[string]$diagnosticStorageAccountKey,
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
		[string]$vmSku,
		[switch]$simulate
    )

    if ($diagnosticStorageAccountName -eq $null){
        $diagnosticStorageAccountName = Get-WsAvDefaultDiagAcctName -secondary:$secondary
    }
    if ($diagnosticStorageAccountKey -eq $null){
        $diagnosticStorageAccountKey = Get-WsAvDefaultDiagAcctKey -secondary:$secondary
    }
    if ($adminUserName -eq $null){
        $adminUserName = Get-WsAvDefaultAdminUsername 
    }
    if ($adminPassword -eq $null){
        $adminPassword = Get-WsAvDefaultAdminPassword
    }
    if ($octoUrl -eq $null){
        $octoUrl = Get-WsAvOctoUrl
    }
    if ($octoApiKey -eq $null){
        $octoApiKey = Get-WsAvOctoApiKey
    }
    if ($vmSku -eq $null){
        $vmSku = Get-WsAvWebVmSku
    }

    if ($fileStgAcctName -eq $null){
        $fileStgAcctName = Get-WsAvFilesStgAcctName -secondary:$secondary
    }
    if ($fileStgAcctKey -eq $null){
        $fileStgAcctKey = Get-WsFilesStgAcctKey -secondary:$secondary
    }

    $parameters = @{}
    Add-WsCurrentContextTagsToParameters -parameters $parameters -secondary:$secondary -role "Web"

    $parameters["diagStorageAccountName"] = $diagnosticStorageAccountName
	$parameters["diagStorageAccountKey"] = $diagnosticStorageAccountKey
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

    $resourceGroupName = Get-WsResourceGroupName -resourceCategory "web" -secondary:$secondary

    $templateName = "deploy-web-from-image"
    if (!$dontUseImage) { $templateName = "deploy-web" }

    Execute-WsArmTemplate -templateName $templateName $parameters -simulate:$simulate
} 



