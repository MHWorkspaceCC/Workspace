#
# configure_jump_server.ps1
#

param(
	[string]$installersStgAcctKey,
	[string]$installersStgAcctName,
	[string]$containerName = "sqlserver",
	[string]$ssmsInstallBlobName = "SSMS-Setup-ENU.exe"
)

Function Write-Log
{
   Param ([string]$logstring)

   Add-Content -Path "c:\config.log" -Value $logstring
   Write-Host $logstring
} 

Try
{
	Write-Log("In configure jump")
	Write-Log("Installers key: " + $installersStgAcctKey)
	Write-Log("installersStgAcctName: " + $installersStgAcctName)
	Write-Log("ssmsInstallBlobName: " + $ssmsInstallBlobName)
	Write-Log("destinationSSMS: " + $destinationSSMS)
	Write-Log "All done!"

	Write-Log("Trusting PSGallery")
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
	Write-Log("Installing AzureRM, xSqlServer, and SqlServer")
	Install-Module -Name AzureRM -Repository PSGallery

	Write-Log("Starting copy of installer files")
	$destinationSSMS = "d:\SSMS-Setup-ENU.exe"
	$storageContext = New-AzureStorageContext -StorageAccountName $installersStgAcctName -StorageAccountKey $installersStgAcctKey
	Write-Log("Starting copy of SSMS installer")
	Get-AzureStorageBlobContent -Blob $ssmsInstallBlobName -Container $containerName -Destination $destinationSSMS -Context $storageContext

	Write-Log("Installing SSMS")
	Start-Process $destinationSSMS "/install /quiet /norestart /log d:\ssms-log.txt" -Wait
	Write-Log("Installed SSMS")

	Remove-Item -Path $destinationSSMS
    Remove-Item -Path d:\ssms-*.txt
}
Catch
{
	Write-Log "Exception"
	Write-Log $_.Exception.Message
}