#Login-AzureRmAccount
#$azureSub = Get-AzureRmsubscription -SubscriptionId 8cc982bb-0877-4c51-aa28-6325a012e486 | Select-AzureRmsubscription
$snapshot = Get-AzureRmSnapshot -ResourceGroupName "rg-devvmimages-dd0p" -SnapshotName "datadisk-devvm-dd0p-image"
$snapshot

$url = "https://md-gwvqdphktrj1.blob.core.windows.net/14zhh5cchkwn/abcd?sv=2017-04-17&sr=b&si=69c8f366-ea65-4ade-83d5-785d031f5319&sig=%2BqPqlAjWW8A80lRJbhwO1kVmBGxWAMDk2NGGQGbiuFk%3D"

$storageAccountName = "stgdevdatadisksdd0p"
$storageAccountKey = “6aoPPN9cpAbq+GusDzwmFbYWyn0baA8nPrLvE89cR6FkcfPcx8WTqrXAX9KrPHAtlvSstW6DfJKvecnynTQ8mg==”
$absoluteUri = $url
$destContainer = “datadisks”
$blobName = “devdatadisk.vhd”

$destContext = New-AzureStorageContext –StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
Start-AzureStorageBlobCopy -AbsoluteUri $absoluteUri -DestContainer $destContainer -DestContext $destContext -DestBlob $blobName

$disk = Get-AzureRmDisk -ResourceGroupName "rg-dev-dd0p" -DiskName "datadisk-b4ms-vm-dev-dd0p"

$diskConfig = New-AzureRmDiskConfig -SourceResourceId $disk.Id -CreateOption Copy -Location westus
New-AzureRmDisk -ResourceGroupName "rg-devvmimages-dd0p" -Disk $diskConfig -DiskName "datadisk-dev-dd0p"
