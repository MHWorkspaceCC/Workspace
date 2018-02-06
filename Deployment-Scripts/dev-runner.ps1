
. .\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "d" -slot 0 -facility "p" 
Create-Core -ctx $ctx 
