
. .\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "d" -slot 0 -facility "p" 
#Build-WebServerImageBase -ctx $ctx

#Create-WebServerImage -ctx $ctx
Deploy-StandaloneWebServerFromImage -ctx $ctx