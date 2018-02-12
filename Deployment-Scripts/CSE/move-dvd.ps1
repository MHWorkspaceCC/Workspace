#
# move-dvd.ps1
#

param(

)

Function Write-Log
{
   Param ([string]$logstring)

   Add-Content -Path "c:\configure.log" -Value $logstring
} 

Try
{
    $cd = Get-CimInstance -Class Win32_LogicalDisk | Where-Object {$_.DriveType -eq 5 } 

    $drv = Get-WmiObject win32_volume -filter $('DriveLetter = "' + $cd.Name + '"')
    $drv.DriveLetter = "Z:"
    $drv.Put()

	Write-Log "Done moving DVD"
}
Catch
{
	Write-Log "Exception"
	Write-Log $_.Exception.Message
}

