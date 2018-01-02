param(
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Try
{
	Write-Log("Starting initialization of disk")

	 Get-Disk | `
		Where partitionstyle -eq 'raw' | `
		Initialize-Disk -PartitionStyle MBR -PassThru | `
		New-Partition -AssignDriveLetter -UseMaximumSize | `
		Format-Volume -FileSystem NTFS -NewFileSystemLabel "WorkspaceDB" -Confirm:$false | 
		Write-Log

	Write-Log("All done!")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
}