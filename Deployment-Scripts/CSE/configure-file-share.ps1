param(
	[string]$fileShareKey
)

$symDirPath = "c:\server\workspace\client"
$stgAcctName = "stgfileswspdpr"
$fileShareName = "workspace-file-storage"
$symDirFolderName = "files"
$filesMountDrive = "Z"

Function Write-Log
{
	Param ([string]$logstring)

	$Logfile = "c:\config.log"
	Add-content $Logfile -value $logstring
	Write-Host $logstring
}

Write-Log "Starting map of AZF"
Write-Log "Fileshare key: " $fileShareKey
Try
{
	$acctKey = ConvertTo-SecureString -String $fileShareKey -AsPlainText -Force
	$credential = New-Object System.Management.Automation.PSCredential -ArgumentList "Azure\$($stgAcctName)", $acctKey

	Write-Log "Mapping drive"
	Write-Log $filesMountDrive
	Write-Log "\\$($stgAcctName).file.core.windows.net\$($fileShareName)"
    Write-Log $filesMountDrive
	New-PSDrive -Name $filesMountDrive -PSProvider FileSystem -Root "\\$($stgAcctName).file.core.windows.net\$($fileShareName)" -Credential $credential -Persist -Scope Global
    Write-Log "mapped drive"

    Write-Log "Creating sym link"
	New-Item $symDirPath -type directory -Force
    Write-Log "Part 2"
	New-Item -ItemType SymbolicLink -Path "$($symDirPath)\$($symDirFolderName)" -Value "$($filesMountDrive):"
	Write-Log "Created sym link"

    Write-Log "storing credentials"
	cmdkey /add:$stgAcctName.file.core.windows.net /user:AZURE\$stgAcctName /pass:$key
    Write-Log "stored credentials"
}
Catch
{
	Write-Log $_.Exception.Message
}
Write-Log "Finished AZF config"