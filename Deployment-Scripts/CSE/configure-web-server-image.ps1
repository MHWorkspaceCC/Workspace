param(
)

Function Write-Log
{
	Param ([string]$logstring)

	$Logfile = "c:\config.log"
	Add-content $Logfile -value $logstring
	Write-Host $logstring
}

Write-Log "In config"
Write-Log $("fileStgAcctName: " + $fileStgAcctName)
Write-Log $("fileShareKey: " + $fileShareKey)
Write-Log $("fileShareName: " + $fileShareName)

. .\move-dvd.ps1
#. .\create-user-account.ps1 -username $fileStgAcctName -password $fileShareKey
#. .\configure-file-share.ps1 -fileStgAcctName $fileStgAcctName -fileShareKey $fileShareKey -fileShareName $fileShareName
. .\install-net45.ps1
. .\install-iis.ps1 -www -mgmt -aspnet45 -removeDefaultSite
. .\install-octopusdsc.ps1

Write-Log "All done configuration!"