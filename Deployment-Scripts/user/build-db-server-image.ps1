
. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "t" -environment "p" -slot 0 -facility "p" 
Build-DatabaseServerImageBase -ctx $ctx

#Create-WebServerImage -ctx $ctx
#Deploy-StandaloneWebServerFromImage -ctx $ctx