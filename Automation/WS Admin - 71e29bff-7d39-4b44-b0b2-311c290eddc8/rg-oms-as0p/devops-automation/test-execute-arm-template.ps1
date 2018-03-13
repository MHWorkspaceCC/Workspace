. .\execute-arm-template.ps1
. .\arm-template-retrievers.ps1

$parameters = @{}
Execute-WsArmTemplate -templateName "deploy-web-from-image" $parameters 