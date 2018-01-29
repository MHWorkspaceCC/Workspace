#
# runner.ps1
#

. .\Deployment-Scripts\WorkspaceAZRM.ps1
 
#Execute-Deployment -templateFile "arm-vnet-deploy.json"
#$ctx = Login-WorkspacePrimaryProd
$ctx = Login-WorkspaceAzureAccount -subscription "w" -environment "p" -slot 0 -facility "p"
Create-Core -ctx $ctx -webScaleSetSize 1 -ftpScaleSetSize 1 -excludeVPN -computeElements @("db") -primary
#Delete-DiskFromVM -ctx $ctx -secondary:$secondary -diskNamePrefix "init1-sql1-db" -vmNamePrefix "sql1-db"
#Cancel-ActiveDeployments -ctx $ctx
#Cancel-ActiveDeployments -ctx $ctx
#Create-Core -ctx $ctx -baseOnly -excludeNetwork 
#Teardown-Core -ctx $ctx -includeDisks #-computeOnly -computeElements @("svc")  #-forceProdFilesRemoval 
#Deploy-NextEnvironmentInstance -ctx $ctx -includeBase -webScaleSetSize 1 -ftpScaleSetSize 1 -computeElements @("web", "db")
#Build-KeyVault -ctx $ctx 
#Build-KeyVault -ctx $ctx -secondary

<#	
	$jobs = New-Object System.Collections.ArrayList

	$job = Start-ScriptJob -environment $ctx.environment -facility $ctx.facility -subscription $ctx.subscription `
				    -usage $false `
					-name $("Build-KeyVault" + "-" + $ctx.GetResourcePostfix($secondary)) `
					-scriptToRun {
Create-KeyVaultSecrets -ctx $newctx -secondary:$false
#						Build-KeyVault -ctx $newctx -secondary:$secondary
					}
	$jobs.Add($job) | Out-Null
	
	Wait-ForJobsToComplete $jobs


#Create-KeyVaultSecrets -ctx $ctx -secondary:$false



#Create-Base -ctx $ctx #-secondary
#Build-KeyVault -ctx $ctx
#Build-KeyVault -ctx $ctx -secondary
#Teardown-Base -ctx $ctx -all
#Create-Core -ctx $ctx -networkOnly -excludeVPN

#Teardown-Core -ctx $ctx -filesOnly
#Teardown-All -ctx $ctx -includeDatabaseDisk
#Create-Core -ctx $ctx -computeElements @("web") -excludeVPN -excludeNetwork
#Create-Core -ctx $ctx -secondary -computeOnly -computeElements @("ftp") -ftpScaleSetSize 1
#Build-KeyVault -ctx $ctx -secondary

#Teardown-ResourceCategories -ctx $ctx -category "test"
#Build-KeyVault -ctx $ctx
#Build-KeyVault -ctx $ctx -secondary

#Create-Core -ctx $ctx -excludeNetwork -webScaleSetSize 1 -ftpScaleSetSize 1 -excludeVPN -peerOnly -computeElements @("ftp")
#Set-WebScaleSetSize -ctx $ctx -size 1 -multi
#Deploy-ServicesVnetEntities -ctx $ctx
#Delete-AllResourcesInRole -ctx $ctx -category "svc" -role "OCTO"
#Deploy-OctoServer -ctx $ctx
#Stop-ComputeResources -ctx $ctx #-usePeer $true #-includeServicesVMs
#Start-ComputeResources -ctx $ctx

#Write-AllWorkspaceEntitiesToCSV
#$ctx = Login-WorkspaceAzureAccount -environmentCode "p1" -facilityCode "p" -subscriptionCode "ws"
#Start-ComputeResources -ctx $ctx
#Create-All -ctx $ctx
#Create-Base -ctx $ctx
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
#Teardown-Diagnostics -ctx $ctx
					
#Add-CertificateToKV -facility "primary" -environment "prod" -pfxFile "workspace.pfx" -password "workspace" -secretName "foo"

#Create-KeyVaultSecrets -facility "primary" -environment "prod"
#Write-AllWorkspaceEntitiesToCSV