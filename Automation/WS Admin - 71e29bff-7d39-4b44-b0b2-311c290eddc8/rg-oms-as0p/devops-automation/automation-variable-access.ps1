function Get-WsAutomationVariable{
    param(
        [string]$name,
        [string]$resourceGroupName = "rg-oms-as0p",
        [string]$automationAccountName = "devops-automation"
    ) 

    Get-AzureRmAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $name
}

function Get-WsAvDefaultDiagAcctName{
    param(
        [switch]$secondary
    )
    
    $name = "default-storage-acct-name"
    if (!$secondary) { $name = $name + "-primary" }
    else { $name = $name + "-secondary" }

    $var = Get-WsAutomationVariable -name $name
    $var.Value
}

function Get-WsAvDefaultDiagAcctKey{
    param(
        [switch]$secondary
    )
    
    $name = "default-storage-acct-key"
    if (!$secondary) { $name = $name + "-primary" }
    else { $name = $name + "-secondary" }

    $var = Get-WsAutomationVariable -name $name
    $var.Value
}

function Get-WsAvDefaultAdminUsername {
    $var = Get-WsAutomationVariable -name "admin-username-default"
    $var.Value
}

function Get-WsAvDefaultAdminPassword {
    $var = Get-WsAutomationVariable -name "admin-password-defaul"
    $var.Value
}

function Get-WsAvOctoUrl {
    $var = Get-WsAutomationVariable -name "octo-url"
    $var.Value
}

function Get-WsAvOctoApiKey {
    $var = Get-WsAutomationVariable -name "octo-api-key"
    $var.Value
}

function Get-WsAvWebVmSku {
    $var = Get-WsAutomationVariable -name "vm-sku-web"
    $var.Value
}

function Get-WsAvDbVmSku {
    $var = Get-WsAutomationVariable -name "vm-sku-db"
    $var.Value
}

function Get-WsAvFilesStgAcctName{
    param(
        [switch]$secondary
    )

    $resourcePostfix = Get-WsResourcePostfix -secondary:$secondary

    $name = $null
    if ($resourcePostfilx[1] -eq 'p'){
        $variableName = "files-stg-acct-name-prod"
        if (!$secondary) { $variableName = $variableName + "-primary" }
        else { $variableName = $variableName + "-secondary" }
        $var = Get-WsAutomationVariable -name $variableName
        $name = $var.Value
    } else {
        $name = "files-stg-acct-name-" + $resourcePostfix
    }

    return $name
}