#
# Script.ps1
#
#
# deploy_vmss_web_lb_config.ps1
#

$rgNetName = "rg-vnet-ws-pd-pri"
$rgWebVmssName = "rg-vmss-web-ws-pd-pri"

$location = "WestUS"

$subnetName = "sn-web-ws-pd-pri"
$vnetName = "vnet-ws-pd-pri"

$pipName = "pip-vmss-web-ws-pd-pri"
$lbName = "lb-vmss-web-ws-pd-pri"

$vmssIpConfigName = "cfg-ip-vmss-web-ws-pd-pri"
$vmssNicConfigName = "cfg-nic-vmss-web-ws-pd-pri"

$vmssName = "vmss-web-ws-pd-pri"

$port = 443

Import-AzureRmContext -Path "C:\dev\Deploy-Vmss\Deploy-Vmss\azureprofile1.json” | Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green
  
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  | Out-Null
Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green

# get destination vnet and subnet
Write-Output "Getting vnet"
$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgNetName -ErrorAction Stop
Write-Output "Got vNet"

Write-Output "Getting subnet"
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -ErrorAction Stop
Write-Output "Got subnet"

Write-Output "Creating resource group"
$rgWebVmss = New-AzureRmResourceGroup -Name $rgWebVmssName -Location $location
Write-Output " Created RG"

Write-Output "Creating pip"
$pip = New-AzureRmPublicIpAddress -Name $pipName -Location $location -ResourceGroupName $rgWebVmssName -AllocationMethod Dynamic -ErrorAction Stop
Write-Output "Created pip"

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

$lb = New-AzureRmLoadBalancer -ResourceGroupName $rgWebVmssName -Name $lbName -Location $location -FrontendIpConfiguration $frontendIP -LoadBalancingRule $inboundNATRule1 -InboundNatPool $inboundNATPool1 -BackendAddressPool $backendPool -Probe $probe -ErrorAction Stop
Write-Output "Created load balancer"

