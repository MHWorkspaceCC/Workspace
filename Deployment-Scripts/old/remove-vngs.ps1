$currentDir = (Get-Item -Path ".\" -Verbose).FullName
Write-Host "Current dir: " $currentDir

$profileFile = $currentDir + "\Deployment-Scripts\azureprofile.json"

Import-AzureRmContext -Path $profileFile #| Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

$subscriptionName = "Visual Studio Enterprise"
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription  #| Out-Null
Write-Host "Set Azure Subscription for session complete"  -ForegroundColor Green

$connections = Find-AzureRmResource -ResourceNameContains "conn-"
$gateways = Find-AzureRmResource -ResourceNameContains "vng-"
#Write-Host $connections
#Write-Host $gateways

workflow deleteVPN{
	param(
		[object[]] $connections,
		[object[]] $gateways
	)
	InlineScript { Write-Host "Starting deletion" }
	sequence{
		InlineScript { Write-Host "Deleting connections" }
		foreach -parallel ($connection in $connections)
		{
			InlineScript { Write-Host "deleting " + $connection }
			#Remove-AzureRmResource -ResourceId $connection.id
		}

		InlineScript { Write-Host "Starting deletion of gateways" }
		foreach -parallel ($gateway in $gateways)
		{
			Write-Output "deleting " + $gateway 
			Remove-AzureRmResource -ResourceId $connection.ResourceId
		}
	}
}
deleteVPN $connections $gateways
