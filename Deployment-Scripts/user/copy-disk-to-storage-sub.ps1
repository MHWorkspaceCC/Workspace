
. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "t" -environment "p" -slot 0 -facility "p" 

Copy-DiskToStorageSubscription -ctx $ctx -sourceDiskName "sql1-vm-db-tp0p_disk1_2a60ea6df78d4cc293c19016709f3db8" -sourceResourceGroupName "RG-TESTDBIMAGE-TP0P"
