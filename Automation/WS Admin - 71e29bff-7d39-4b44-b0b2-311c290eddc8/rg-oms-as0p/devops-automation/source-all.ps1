if (!$sourced_all_sourced) {
    $sourced_all_sourced = $true
    Write-Verbose "Sourced:" $MyInvocation.InvocationName

. .\core.ps1
. .\arm-template-retrievers.ps1
. .\execute-arm-template.ps1 
. .\automation-variable-access.ps1
. .\create-web-vmss.ps1
. .\deploy-vnet.ps1
. .\ensure-resource-group.ps1

} #end sourced