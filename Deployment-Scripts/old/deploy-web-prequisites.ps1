function Deploy-WebVMSS-Prerequisites {
	param(
		[string]$environment,
		[string]$facility
	)

	$suffix = "-ws" + $environment + $facility

	$rgNetName = "rg-vnet" + $suffix
	$rgWebVmssName = "rg-web" + $suffix

	$subnetName = "sn-web" + $suffix
	$vnetName = "vn1-vnet" + $suffix

	$pipName = "pip-web" + $suffix
	$lbName = "lb-web" + $suffix

	$vmssIpConfigName = "ipconfig-vmss-web" + $suffix
	$vmssNicConfigName = "nic-vmss-web" + $suffix

	$vmssName = "vmss-web" + $suffix

	$pipsRgName = "rg-pips" + $suffix

	$port = 443

	$subscriptionName = "Visual Studio Enterprise"

	$location = ""
	if ($facility -eq "pr"){ $location = "westus" }
	elseif ($facility -eq "dr"){ $location = "eastus"}

	# get destination vnet and subnet
	Write-Output "Getting vnet"
	$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgNetName -ErrorAction Stop
	Write-Output "Got vNet"

	Write-Output "Getting subnet"
	$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -ErrorAction Stop
	Write-Output "Got subnet"

	Write-Output "Creating resource group"
	$rgWebVmss = Get-AzureRmResourceGroup -Name $rgWebVmssName 
	Write-Output "Got RG"

	Write-Output "Getting pip"
	$pip = Get-AzureRmPublicIpAddress -Name $pipName -ResourceGroupName $pipsRgName -ErrorAction Stop
	Write-Output "Get pip"

	$frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name "LB-Frontend" -PublicIpAddress $pip -ErrorAction Stop 
	Write-Output "Created front end IP config"

	$backendPool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name "LB-backend" -ErrorAction Stop
	Write-Output "Created backend pool config"

	$probe = New-AzureRmLoadBalancerProbeConfig -Name "HealthProbe" -Protocol Tcp -Port $port -IntervalInSeconds 15 -ProbeCount 2 -ErrorAction Stop
	Write-Output "Created lb probe config"

	$inboundNATRule1= New-AzureRmLoadBalancerRuleConfig -Name "webserver" -FrontendIpConfiguration $frontendIP -Protocol Tcp -FrontendPort $port -BackendPort $port -IdleTimeoutInMinutes 15 -Probe $probe -BackendAddressPool $backendPool -ErrorAction Stop
	Write-Output "Created lb web server rule config"

	$inboundNATPool1 = New-AzureRmLoadBalancerInboundNatPoolConfig -Name "RDP" -FrontendIpConfigurationId $frontendIP.Id -Protocol TCP -FrontendPortRangeStart 53380 -FrontendPortRangeEnd 53390 -BackendPort 3389 -ErrorAction Stop
	Write-Output "Created lb rdp rule config"

	$lb = New-AzureRmLoadBalancer -ResourceGroupName $rgWebVmssName -Location $location -Name $lbName -FrontendIpConfiguration $frontendIP -LoadBalancingRule $inboundNATRule1 -InboundNatPool $inboundNATPool1 -BackendAddressPool $backendPool -Probe $probe -ErrorAction Stop
	Write-Output "Created load balancer"
}

$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$profileFile = $currentDir + "\Deployment-Scripts\azureprofile.json"

Import-AzureRmContext -Path $profileFile #| Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

$subscriptionName = "Visual Studio Enterprise"
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  #| Out-Null
Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green


Deploy-WebVMSS-Prerequisites "pd" "pr"