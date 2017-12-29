#
# configure_jump_server.ps1
#

Function Write-Log
{
   Param ([string]$logstring)

   Add-Content -Path "c:\configure.log" -Value $logstring
} 

Try
{
	Write-Log "All done!"
}
Catch
{
	Write-Log "Exception"
	Write-Log $_.Exception.Message
}