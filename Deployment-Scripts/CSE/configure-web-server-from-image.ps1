param(
	[string]$fileStgAcctName,
	[string]$fileShareKey,
	[string]$fileShareName,
	[string]$octoUrl,
	[string]$octoApiKey,
	[string]$octoEnvironment
)

Function Write-Log
{
	Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
}

Write-Log "In config web server from image"
Write-Log $("fileStgAcctName: " + $fileStgAcctName)
Write-Log $("fileShareKey: " + $fileShareKey)
Write-Log $("fileShareName: " + $fileShareName)
Write-Log $("octoUrl: " + $octoUrl)
Write-Log $("octoApiKey: " + $octoApiKey)
Write-Log $("octoEnvironment: " + $octoEnvironment)

.\create-user-account.ps1 -username $fileStgAcctName -password $fileShareKey
.\configure-file-share.ps1 -fileStgAcctName $fileStgAcctName -fileShareKey $fileShareKey -fileShareName $fileShareName
.\install-web-app-with-octo-dsc.ps1 -octoUrl $octoUrl -octoApiKey $octoApiKey -octoEnvironment $octoEnvironment

Write-Log "All done configuration!"