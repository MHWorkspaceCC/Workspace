param(
    [string]$sourceResourceGroupName = "rg-vmimages-dd0p",
    [string]$imageName = "image-web",
    [string]$snapshotName = "mysnapshot2",
    [string]$sourceLocation = "westus",
    [string]$targetSubscriptionId,
    [string]$targetResourceGroupName,
    [string]$targetLocation,
    [string]$targetImageName
)

. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "d" -environment "p" -slot 0 -facility "p" 

$image = Get-AzureRmImage -ResourceGroupName $sourceResourceGroupName -ImageName $imageName
$osDisk = $image.StorageProfile.OsDisk

$snapshotConfig = New-AzureRmSnapshotConfig -SourceUri $osDisk.ManagedDisk.Id -CreateOption Copy -Location $sourceLocation
$snapshot = New-AzureRmSnapshot -ResourceGroupName $sourceResourceGroupName -Snapshot $snapshotConfig -SnapshotName $snapshotName

<# -- Create a snapshot of the OS (and optionally data disks) from the generalized VM -- #>
$vm = Get-AzureRmVM -ResourceGroupName $sourceResourceGroupName -Name $vmName
$disk = Get-AzureRmDisk -ResourceGroupName $sourceResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name
$snapshot = New-AzureRmSnapshotConfig -SourceUri $disk.Id -CreateOption Copy -Location $region
 
$snapshotName = $imageName + "-" + $region + "-snap"
 
New-AzureRmSnapshot -ResourceGroupName $resourceGroupName -Snapshot $snapshot -SnapshotName $snapsh

<#-- copy the snapshot to another subscription, same region --#>
$snap = Get-AzureRmSnapshot -ResourceGroupName $sourceResourceGroupName -SnapshotName $snapshotName
 
<#-- change to the target subscription #>
Select-AzureRmSubscription -SubscriptionId $targetSubscriptionId
$snapshotConfig = New-AzureRmSnapshotConfig -OsType Windows `
                                            -Location $region `
                                            -CreateOption Copy `
                                            -SourceResourceId $snap.Id
 
$snap = New-AzureRmSnapshot -ResourceGroupName $sourceResourceGroupName `
                            -SnapshotName $snapshotName `
                            -Snapshot $snapshotConfig
                            
<# -- In the second subscription, create a new Image from the copied snapshot --#>
Select-AzureRmSubscription -SubscriptionId $targetSubscriptionId
 
$snap = Get-AzureRmSnapshot -ResourceGroupName $sourceResourceGroupName -SnapshotName $snapshotName
 
$imageConfig = New-AzureRmImageConfig -Location $targetRegion
 
Set-AzureRmImageOsDisk -Image $imageConfig `
                        -OsType Windows `
                        -OsState Generalized `
                        -SnapshotId $snap.Id
 
New-AzureRmImage -ResourceGroupName $targetResourceGroupName `
                 -ImageName $targetImageName `
                 -Image $imageConfig

<# -- Delete the snapshot in the second subscription -- #>
Remove-AzureRmSnapshot -ResourceGroupName $targetResourceGroupName -SnapshotName $snapshotName -Force