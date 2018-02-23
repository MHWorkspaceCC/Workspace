. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "p" -slot 0 -facility "p" 
#Build-WebServerImageBase -ctx $ctx

#Create-WebServerImage -ctx $ctx
#Deploy-StandaloneWebServerFromImage -ctx $ctx

#Copy-DiskToStorageSubscription -ctx $ctx -sourceDiskName "osdisk-wwwib-vm-web-dd0p" -sourceResourceGroupName "RG-WEBIMAGEBUILD2-DD0P" `
#    -targetResourceCategory "diskcopies" -targetDiskName "os-web"

#Deploy-StandaloneServerFromReferenceOsDisk -ctx $ctx -web
Create-Core -ctx $ctx -webScaleSetSize 1 -computeOnly -computeElements(@("web")) -primary
