. .\core.ps1
. .\deploy-vnet.ps1

Login-WsAutomation
Set-WsContext -subscription "a" -environment "p" -slot 0 -facility "p" 

Deploy-Vnet