. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "p" -slot 0 -facility "p" 

Ensure-ResourceGroupWithName -ctx $ctx -resourceGroupName "rg-vaults-tp0p"
New-AzureRmKeyVault -VaultName "fookv" -ResourceGroupName "rg-vaults-tp0p" -Location "westus" -EnabledForDeployment
Set-AzureRmKeyVaultAccessPolicy -VaultName "fookv" -ResourceGroupName "rg-vaults-tp0p"

#Create-Core -$ctx
#Build-WebServerImageBase -ctx $ctx

#Create-WebServerImage -ctx $ctx
#Deploy-StandaloneWebServerFromImage -ctx $ctx

#Copy-DiskToStorageSubscription -ctx $ctx -sourceDiskName "osdisk-wwwib-vm-web-dd0p" -sourceResourceGroupName "RG-WEBIMAGEBUILD2-DD0P" `
#    -targetResourceCategory "diskcopies" -targetDiskName "os-web"

#Deploy-StandaloneServerFromReferenceOsDisk -ctx $ctx -web
Create-Core -ctx $ctx -webScaleSetSize 1 -computeOnly -forceKeyVault -computeElements(@("web")) -primary 
#Create-Core -ctx $ctx -computeOnly -computeElements(@("db")) -primary 
#Deploy-StandaloneDatabaseServerFromImage -ctx $ctx