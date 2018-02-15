. ..\WorkspaceAZRM.ps1
$ctx = Login-WorkspaceAzureAccount -subscription "t" -environment "p" -slot 0 -facility "p" 
Create-Core -ctx $ctx -computeOnly -computeElements @("db", "jump") -primary