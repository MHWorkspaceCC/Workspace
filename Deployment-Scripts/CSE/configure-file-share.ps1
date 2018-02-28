param(
    [Parameter(Mandatory=$true)]
	[string]$fileStgAcctName,
    [Parameter(Mandatory=$true)]
	[string]$fileShareKey,
	[string]$fileShareName = "workspace-file-storage",
	[string]$symDirPath = "c:\server\workspace\client",
	[string]$symDirFolderName = "files",
	[string]$filesMountDrive = "Z"
)

Function Write-Log
{
	Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
}

Write-Log("Starting map of AZF")
Write-Log("File share stg acct name: " + $fileStgAcctName)
Write-Log("File share key: " + $fileShareKey)
Write-Log("File share name: " + $fileShareName)

Try
{
	$acctKey = ConvertTo-SecureString -String $fileShareKey -AsPlainText -Force
	$credential = New-Object System.Management.Automation.PSCredential -ArgumentList "Azure\$($fileStgAcctName)", $acctKey

	Write-Log("Mapping drive")
	Write-Log($filesMountDrive)
	Write-Log("\\$($fileStgAcctName).file.core.windows.net\$($fileShareName)")
    Write-Log($filesMountDrive)
	New-PSDrive -Name $filesMountDrive -PSProvider FileSystem -Root "\\$($fileStgAcctName).file.core.windows.net\$($fileShareName)" -Credential $credential -Persist -Scope Global
    Write-Log("mapped drive")

    Write-Log("Creating sym link")
	New-Item $symDirPath -type directory -Force
    Write-Log("Creating link")
	New-Item -ItemType SymbolicLink -Path "$($symDirPath)\$($symDirFolderName)" -Value "$($filesMountDrive):"
	Write-Log("Created sym link")

    Write-Log("storing credentials")
	cmdkey /add:$fileStgAcctName.file.core.windows.net /user:AZURE\$fileStgAcctName /pass:$fileShareKey > "c:\cmdkey.log"
	cmdkey /list >> "c:\cmdkey.log"
    Write-Log("stored credentials")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
}

Write-Log("Finished AZF config")