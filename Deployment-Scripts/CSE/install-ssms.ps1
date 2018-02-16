param(
    [string]$installersStgAcctName="stginstallersss0p",
    [string]$installersStgAcctKey="RTroekJPVf2/9tMyTfJ+LTrup0IwZIDyuus13KoQX0QuH3MCTBLt0wawD0Air2bMYF03JDV0sRSYuqYypSBxbg==",
    [string]$installContainerName="sqlserver",
    [string]$installBlobName="SSMS-Setup-ENU.exe",
    [string]$tempLocation="D:\",
    [string]$destinationInstallerName="SSMS-Setup-ENU.exe"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
} 

Write-Log("In install-ssms")

Write-Log("installersStgAcctName: " + $installersStgAcctName)
Write-Log("installersStgAcctKey: " + $installersStgAcctKey)
Write-Log("installContainerName: " + $installContainerName)
Write-Log("installBlobName: " + $installBlobName)
Write-Log("tempLocation: " + $tempLocation)
Write-Log("destinationInstallerName: " + $destinationInstallerName)

Write-Log("Trusting PSGallery")
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Log("Importing AzureRM")
Install-Module -Name AzureRM -Repository PSGallery 

$localInstallerPath = $tempLocation + $destinationInstallerName

Write-Log("Starting copy of installer files")
$storageContext = New-AzureStorageContext -StorageAccountName $installersStgAcctName -StorageAccountKey $installersStgAcctKey
Write-Log("Starting copy of SSMS installer")
Get-AzureStorageBlobContent -Blob $installBlobName -Container $installContainerName -Destination $localInstallerPath -Context $storageContext

Write-Log("Installing SSMS")
Start-Process $localInstallerPath "/install /quiet /norestart /log d:\ssms-log.txt" -Wait
Write-Log("Installed SSMS")

Write-Log("Cleaning up installer files")
Remove-Item -Path $localInstallerPath
get-childitem $tempLocation -include ssms*.txt | foreach ($_) { remove-item $_.fullname} 

Write-Log("Done install-ssms")

