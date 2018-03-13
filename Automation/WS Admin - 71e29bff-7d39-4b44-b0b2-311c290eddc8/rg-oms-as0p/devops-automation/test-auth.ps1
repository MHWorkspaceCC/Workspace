. .\core.ps1
. .\core.ps1

Login-WsAutomation
Set-WsContext -subscription "a" -environment "p" -slot 0 -facility "p"

<#

#Get all ARM resources from all resource groups
$ResourceGroups = Get-AzureRmResourceGroup 

foreach ($ResourceGroup in $ResourceGroups)
{    
   Write-Output ("Showing resources in resource group " + $ResourceGroup.ResourceGroupName)
   $Resources = Find-AzureRmResource -ResourceGroupNameContains $ResourceGroup.ResourceGroupName | Select ResourceName, ResourceType
   ForEach ($Resource in $Resources)
   {
      Write-Output ($Resource.ResourceName + " of type " +  $Resource.ResourceType)
   }
   Write-Output ("")
} 
#>