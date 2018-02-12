
. .\WorkspaceAZRM.ps1

#$azureSub = Get-AzureRmsubscription -SubscriptionId "8cc982bb-0877-4c51-aa28-6325a012e486" | Select-AzureRmsubscription
#Get-AzureRmSubscription
#Save-AzureRmProfile -Path .\workspacecc.json
$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "d" -slot 0 -facility "p" 

#Create-Core -ctx $ctx -vmSize "Standard_D2_v3" -computerName "d2v3"
#Create-Core -ctx $ctx -vmSize "Standard_D2s_v3" -computerName "d2sv3"
#Create-Core -ctx $ctx -vmSize "Standard_D4s_v3" -computerName "d4sv3"
#Create-DevVM -ctx $ctx -vmSize "Standard_B2ms" -computerName "b2ms"
Build-DevMachineImage -ctx $ctx -vmSize "Standard_B2ms" -computerName "b2ms"
#Create-DevVM -ctx $ctx -vmSize "Standard_B4ms" -computerName "b4ms"
#Create-DevVM -ctx $ctx -vmSize "Standard_D2s_v3" -computerName "d2sv3"
#Create-DevVM -ctx $ctx -vmSize "Standard_D4s_v3" -computerName "d4sv3"
#Create-DevVmImage -ctx $ctx

