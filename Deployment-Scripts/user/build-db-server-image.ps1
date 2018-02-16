
. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "t" -environment "p" -slot 0 -facility "p" 
#Build-KeyVault -ctx $ctx 
Build-DatabaseServerImageBase -ctx $ctx

#Create-DatabaseServerImage -ctx $ctx
#Deploy-StandaloneDatabaseServerFromImage -ctx $ctx