wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/move-dvd.ps1 -OutFile move-dvd.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-net45.ps1 -OutFile install-net45.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-iis.ps1 -OutFile install-iis.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-octopusdsc.ps1 -OutFile install-octopusdsc.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/configure-web-server-image.ps1 -OutFile configure-web-server-image.ps1

$dbBackupsStorageAccountName = "stgdbbackupsss0p"
$dbBackupsStorageAccountKey = "dMFiKWGj8AtVR1Tf4xTgWEEqdUS0wIX/iJU/VAGrDCX/G8YfkH1mZeQUDI6h0xKQWvlVwH16nDGmzNneiMP11w=="
$webArchiveBlobName = "ws-client-web-6.0.0.502.zip"

$backupStorageContext = New-AzureStorageContext -StorageAccountName $dbBackupsStorageAccountName -StorageAccountKey $dbBackupsStorageAccountKey
Get-AzureStorageBlobContent -Blob $webArchiveBlobName -Container "current" -Destination "c:\web.zip" -Context $backupStorageContext

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Unzip "c:\web.zip" "c:\"
. .\configure-web-server-image.ps1
Remove-Item -Path c:\config.log