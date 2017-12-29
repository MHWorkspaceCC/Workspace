function Deploy-WebVMSS {
	param(
		[string]$environment,
		[string]$facility
	)

	$suffix = "-ws" + $environment + $facility

	$vmssIpConfigName = "ipconfig-vmss-web" + $suffix
	$vmssNicConfigName = "nic-vmss-web" + $suffix

	$lbName = "lb-web" + $suffix
	$rgWebVmssName = "rg-web" + $suffix
	
	$location = ""
	if ($facility -eq "pr"){ $location = "westus" }
	elseif ($facility -eq "dr"){ $location = "eastus"}

	$rgVnetName = "rg-vnet" + $suffix
	$vnetName = "vn1-vnet" + $suffix
	$subnetName = "sn-web" + $suffix

	$imageRefPub = "MicrosoftWindowsServer"
	$imageRefOff = "WindowsServer"
	$imageRefSku = "2016-Datacenter"
	$imageRefVer = "latest"

	$adminUserName = "adminuser"
	$adminPassword = "Workspace!cc"
	$vmssComputerNamePrefix = "webvmssvm"

	$vmssName = "vmss-web" + $suffix

	$certificateUrl = "https://kv-svc" + $suffix + ".vault.azure.net/secrets/vmssweb/73ba1ddd6f654593bcdd7ad6cbdf3a11"
	$certStore = "MyCerts"
	$vaultName = "kv-svc" + $suffix

	$numberOfInstances = 1
	$skuName = "Standard_DS1_v2"

	Write-Output "Creating vmss config"
	$vmssConfig = New-AzureRmVmssConfig -Location $location -SkuCapacity $numberOfInstances -SkuName $skuName -UpgradePolicyMode Automatic -ErrorAction Stop
	Write-Output "Created vmss config"

	Write-Output "Getting key vault"
	$vault = Get-AzureRmKeyVault -VaultName $vaultName -ErrorAction Stop

	Write-Output "Creating VMSS Cert Config"
	$certConfig = New-AzureRmVmssVaultCertificateConfig -CertificateUrl $certificateUrl -CertificateStore $certStore -ErrorAction Stop

	Write-Output "Adding cert config to VMSS config"
	Add-AzureRmVmssSecret -VirtualMachineScaleSet $vmssConfig -SourceVaultId $vault.ResourceId -VaultCertificate $certConfig -ErrorAction Stop | Out-Null

	 $extensionParameters = @{
		 "fileUris" = (
 			"https://raw.githubusercontent.com/mheydt/deploy-vmss/master/Deploy-Vmss/CSE/Install-OctopusDSC.ps1",
 			"https://raw.githubusercontent.com/mheydt/deploy-vmss/master/Deploy-Vmss/CSE/install-and-configure-iis.ps1",
 			"https://raw.githubusercontent.com/mheydt/deploy-vmss/master/Deploy-Vmss/CSE/configure-file-share.ps1",
			"https://raw.githubusercontent.com/mheydt/deploy-vmss/master/Deploy-Vmss/CSE/install-web-app-with-octo-dsc.ps1",
 			"https://raw.githubusercontent.com/mheydt/deploy-vmss/master/Deploy-Vmss/CSE/configure-web-server.ps1");
		 "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File configure-web-server.ps1"
	 }

	Write-Output "Adding vmss extension (iis)"
	$vmssConfig | Add-AzureRmVmssExtension `
		-Name "ConfigureWebVMSS" `
		-Publisher "Microsoft.Compute" `
		-Type "CustomScriptExtension" `
		-TypeHandlerVersion 1.8 `
		-Setting $extensionParameters `
		-ErrorAction Stop | Out-Null
	Write-Output "Added extension"

	Write-Output "Getting LB"
	$loadBalancer = Get-AzureRmLoadBalancer -Name $lbName -ResourceGroupName $rgWebVmssName -ErrorAction Stop
	Write-Output "Got LB"

	Write-Output "Gettting LB Backend Pool"
	$backendPool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $loadBalancer -Name "LB-Backend" -ErrorAction Stop
	Write-Output "Got LB Backend Pool"

	Write-Output "Gettting LB Inbound NAT Pool"
	$inboundNATPool1 = Get-AzureRmLoadBalancerInboundNatPoolConfig -LoadBalancer $loadBalancer -Name "RDP" -ErrorAction Stop
	Write-Output "Got LB Inbound NAT Pool"

	Write-Output "Getting vNet"
	$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgVnetName -ErrorAction Stop
	Write-Output "Got vNet"

	Write-Output "Getting Subnet"
	$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -ErrorAction Stop
	Write-Output "Got Subnet"

	Write-Output "Creating VMSS IP Config"
	$vmssIpConfig = New-AzureRmVmssIpConfig -Name $vmssIpConfigName -LoadBalancerBackendAddressPoolsId $backendPool.Id -SubnetId $subnet.Id -LoadBalancerInboundNatPoolsId $inboundNATPool1.Id -ErrorAction Stop
	Write-Output "Created VMSS IP Config"

	# Attach the virtual network to the IP object
	Write-Output "Creating NIC"
	$nicConfig = Add-AzureRmVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmssConfig -Name $vmssNicConfigName -Primary $true -IPConfiguration $vmssIpConfig -ErrorAction Stop
	Write-Output "Created NIC"

	# Reference a virtual machine image from the gallery
	Write-Output "Setting storage profile"
	Set-AzureRmVmssStorageProfile $vmssConfig -ImageReferencePublisher $imageRefPub -ImageReferenceOffer $imageRefOff -ImageReferenceSku $imageRefSku -ImageReferenceVersion $imageRefVer -ErrorAction Stop | Out-Null
	Write-Output "Set storage profile"

	# Set up information for authenticating with the virtual machine
	Write-Output "Setting os profile"
	Set-AzureRmVmssOsProfile $vmssConfig -AdminUsername $adminUserName -AdminPassword $adminPassword -ComputerNamePrefix $vmssComputerNamePrefix -ErrorAction Stop | Out-Null
	Write-Output "Set os profile"

	# Create the scale set with the config object (this step might take a few minutes)
	Write-Output "Creating the VMSS"
	$vmss = New-AzureRmVmss -ResourceGroupName $rgWebVmssName -Name $vmssName -VirtualMachineScaleSet $vmssConfig  -ErrorAction Stop
	Write-Output "Created vmss"
	$vmss
}

$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$profileFile = $currentDir + "\Deployment-Scripts\azureprofile.json"

Import-AzureRmContext -Path $profileFile #| Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

$subscriptionName = "Visual Studio Enterprise"
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  #| Out-Null
Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green

Deploy-WebVMSS "pd" "pr"