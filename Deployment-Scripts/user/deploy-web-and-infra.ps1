. ..\WorkspaceAZRM.ps1
$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "p" -slot 0 -facility "p" 
Create-Core -ctx $ctx -computeElements("web") -excludeVPN -computeOnly -primary
