#
# move-dvd.ps1
#

param(
    [string]$drive = "Y:"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
} 

Try
{
    Write-Log("In Move-DVD: " + $drive)
    $cd = Get-CimInstance -Class Win32_LogicalDisk | Where-Object {$_.DriveType -eq 5 } 

    $drv = Get-WmiObject win32_volume -filter $('DriveLetter = "' + $cd.Name + '"')
    $drv.DriveLetter = $drive
    $drv.Put()

	Write-Log "Done move-dvd"
}
Catch
{
	Write-Log "Exception"
	Write-Log $_.Exception.Message
}

