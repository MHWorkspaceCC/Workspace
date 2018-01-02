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
	Write-Log("In configure db disk init server")

	$dataDisk = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
	Write-Log("The data disk drive letter is " + $dataDisk)

	Write-Log("All done!")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
}