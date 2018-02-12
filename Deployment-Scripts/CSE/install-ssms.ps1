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

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

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
Remove-Item -Path $($tempLocation + "log*.txt")
Remove-Item -Path $($tempLocation + "*.bak")

Write-Log("Done installing SSMS")

