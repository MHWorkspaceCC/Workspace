param(
	[string]$octoUrl,
	[string]$octoApiKey,
	[string]$fileShareKey,
	[string]$fileStgAcctName,
	[string]$fileShareName,
	[string]$octoEnvironment
)

Function Write-Log
{
	Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
}

Write-Log "In config"
Write-Log $("octoUrl: " + $octoUrl)
Write-Log $("octoApiKey: " + $octoApiKey)
Write-Log $("fileShareKey: " + $fileShareKey)
Write-Log $("fileStgAcctName: " + $fileStgAcctName)
Write-Log $("fileShareName: " + $fileShareName)
Write-Log $("octoEnvironment: " + $octoEnvironment)

Write-Log "Trusting PSGallery"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Log "Installing OctopusDSC..."
. .\Install-OctopusDSC.ps1

Write-Log "Installing and configuring IIS"
. .\install-and-configure-iis.ps1 -fileShareKey $fileShareKey -fileStgAcctName $fileStgAcctName

Write-Log "Configuring file shares"
. .\configure-file-share.ps1 -fileShareKey $fileShareKey -fileShareName $fileShareName -fileStgAcctName $fileStgAcctName

Write-Log "Installing Web App with Octopus DSC"
. .\install-web-app-with-octo-dsc.ps1 -octoUrl $octoUrl -octoApiKey $octoApiKey -environment $octoEnvironment

Write-Log "All done configuration!"