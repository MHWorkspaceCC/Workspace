param(
    [string]$installersStgAcctName="stginstallersss0p",
    [string]$installersStgAcctKey="RTroekJPVf2/9tMyTfJ+LTrup0IwZIDyuus13KoQX0QuH3MCTBLt0wawD0Air2bMYF03JDV0sRSYuqYypSBxbg==",
    [string]$installContainerName="sqlserver",
    [string]$installBlobName="en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso",
    [string]$tempLocation="D:\",
    [string]$destinationIsoName="sqlserver.iso",
    [string]$loginUserName="wsapp",
    [string]$loginPassword="Workspace!DB!2018",
    [string]$saPassword="Workspace!DB!2018",
    [string]$sysUserName="wsadmin",
    [string]$sysPassword="Workspace!DB!2018"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Write-Log("Trusting PSGallery")
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Log("Installing xSqlServer")
Install-Module -Name xSqlServer -Repository PSGallery

Write-Log("Importing SqlServer")
Install-Module -Name SqlServer -Repository PSGallery
Import-Module SqlServer

$localIsoPath = $tempLocation + $destinationSqlIso

Write-Log("Starting copy of installer files")
$storageContext = New-AzureStorageContext -StorageAccountName $installersStgAcctName -StorageAccountKey $installersStgAcctKey
Write-Log("Starting copy of SQL Server ISO")
Get-AzureStorageBlobContent -Blob $installBlobName -Container $installContainerName -Destination $localIsoPath -Context $storageContext

Write-Log("Mounting SQL Server ISO")
Mount-DiskImage -ImagePath $localIsoPath
$sqlInstallDrive = (Get-DiskImage -ImagePath $localIsoPath | Get-Volume).DriveLetter
Write-Log("Mounted sql server media on " + $sqlInstallDrive)

Write-Log("Creating credentials for app login")
$loginPwdSecure = ConvertTo-SecureString $loginPassword -AsPlainText -Force
$loginCred = New-Object System.Management.Automation.PSCredential ($loginUserName, $loginPwdSecure)

Write-Log("Creating credentials for sys account")
$sysPasswordSecure = $sysPassword | ConvertTo-SecureString -AsPlainText -Force
$sysCreds = New-Object -TypeName pscredential -ArgumentList $sysUserName, $sysPasswordSecure

Write-Log("Creating credentials for sa")
$saPasswordSecure = $saPassword | ConvertTo-SecureString -AsPlainText -Force
$saCred = New-Object -TypeName pscredential -ArgumentList "sa", $saPasswordSecure

Write-Log("Sourcing SqlStandaloneDSC")
. ./SqlStandaloneDSC

Write-Log("Configuring SQLServer DSC")
SqlStandaloneDSC -ConfigurationData SQLConfigurationData.psd1 -LoginCredential $loginCred -SysAdminAccount $sysCreds -saCredential $saAcctCreds -installDisk $sqlInstallDrive

Write-Log("Starting SQL Server Install")
Start-DscConfiguration .\SqlStandaloneDSC -Verbose -wait -Force

Write-Log("Creating sa account")
$ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
$ss.ConnectionContext.LoginSecure = $false
$ss.ConnectionContext.Login = "sa"
$ss.ConnectionContext.Password = $saPassword
Write-Log($ss.Information.Version)

Write-Log("Umounting SQL server iso")
Dismount-DiskImage -ImagePath $localIsoPath

Write-Log("Cleaning up installer files")
Remove-Item -Path $localIsoPath

Write-Log("Finished installing SQL Server")