param(
	[string]$installersStgAcctKey = "RTroekJPVf2/9tMyTfJ+LTrup0IwZIDyuus13KoQX0QuH3MCTBLt0wawD0Air2bMYF03JDV0sRSYuqYypSBxbg==",
	[string]$installersStgAcctName = "stginstallersss0p",
	[string]$saUserName = "wsadmin",
	[string]$saPassword = "Workspace!DB!2018",
	[string]$loginUserName = "wsapp",
	[string]$loginPassword = "Workspace!DB!2018",
	[string]$sysUserName = "wsapp",
	[string]$sysPassword = "Workspace!DB!2018"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
} 

Write-Log("In configure-sql-server-image")

. .\move-dvd.ps1 -drive "Z:"
. .\install-sql-server.ps1 `
	-installersStgAcctName $installersStgAcctName -installersStgAcctKey ]$installersStgAcctKey `
	-loginUserName $loginUserName -loginPassword $loginPassword `
	-saUsername $saUserName -saPassword $saPassword `
	-sysUserName $sysUserName -sysPassword $sysPassword
. .\install-smss.ps1 -installersStgAcctName $installersStgAcctName -installersStgAcctKey $installersStgAcctKey

Write-Log("Done configure-sql-server-image")
