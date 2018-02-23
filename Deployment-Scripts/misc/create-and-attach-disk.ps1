. ..\WorkspaceAZRM.ps1

$ctx = Login-WorkspaceAzureAccount -subscription "t" -environment "p" -slot 0 -facility "p" 

$accountType = "PremiumLRS"
#$accountType = "PremiumLRS"
$dataDiskName = 'so-disk-p20-plrs'
#$diskName = 'so-disk-plrs'
$diskSize = 512

$vmName = "sql1-vm-db-tp0p"
$vmResourceGroupName = "rg-testdbimage-tp0p"

$resourceGroupName = "rg-disks-tp0p"

$dataDisk = Get-AzureRmDisk -ResourceGroupName $resourceGroupName -DiskName $dataDiskName -ErrorVariable err -ErrorAction SilentlyContinue
if ($err -ne $null){
    $diskconfig = New-AzureRmDiskConfig -Location westus -DiskSizeGB $diskSize -AccountType $accountType -OsType Windows -CreateOption Empty
    $dataDisk = New-AzureRmDisk -ResourceGroupName $resourceGroupName -DiskName $dataDiskName -Disk $diskconfig
}

$vm = Get-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName
$vm = Add-AzureRmVMDataDisk -VM $vm -Name $dataDiskName -CreateOption Attach -ManagedDiskId $dataDisk.Id -Lun 3

Update-AzureRmVM -VM $vm -ResourceGroupName $vmResourceGroupName


