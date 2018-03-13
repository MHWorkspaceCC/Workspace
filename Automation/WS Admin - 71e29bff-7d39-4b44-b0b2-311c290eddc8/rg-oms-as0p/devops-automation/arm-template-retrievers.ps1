function Get-ArmTemplateContent{
    param(
        [string]$templateName,
        [string]$resourceGroupName = "rg-oms-as0p",
        [string]$automationAccountName = "devops-automation"
    )

    $name = "url-arm-" + $templateName

    $var = Get-WsAutomationVariable -name $templateName
    $url = $var.Value

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
    $content = $response.Content
    $content
} 