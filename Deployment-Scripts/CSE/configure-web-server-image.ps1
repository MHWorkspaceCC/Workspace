param(
)

Function Write-Log
{
	Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
}

Write-Log "In config"

. .\move-dvd.ps1
#. .\create-user-account.ps1 -username $fileStgAcctName -password $fileShareKey
#. .\configure-file-share.ps1 -fileStgAcctName $fileStgAcctName -fileShareKey $fileShareKey -fileShareName $fileShareName
. .\install-net45.ps1
. .\install-iis.ps1 -www -mgmt -aspnet45 -removeDefaultSite
. .\install-octopusdsc.ps1

Write-Log "All done configuration!"