#
# get_sqlservermedia.ps1
#

$storageAccountKey = "463znlo22viNBm3ACyTCeHaZJDqHkCY6SH9oLMIv3yVr/7RzXphZKS2KCZxJ4eLwQkWThK2wBwXo42pHHkNDdw=="
$storageAccountName = "stginstallerswspri"
$containerName = "sqlserver"
$blobName = "en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso"
$destination = "d:\sqlserver.iso"
Write-Log("c:\get-sqlservermedia.log", "Starting retrieval of sql server media")
try
{
	$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
	Get-AzureStorageBlobContent -Blob $blobName  -Container $containerName -Destination $destination -Context $storageContext
	Mount-DiskImage -ImagePath d:\sqlserver.iso 
	Write-Log("c:\get-sqlservermedia.log", "Mounted sql server media")

	$ISODrive = (Get-DiskImage -ImagePath "d:\sqlserver.iso" | Get-Volume).DriveLetter
}
catch
{
	Write-Log("c:\get-sqlservermedia.log", "Exception retrieving and mounting sql server media")
	Write-Log("c:\get-sqlservermedia.log", $_)
}