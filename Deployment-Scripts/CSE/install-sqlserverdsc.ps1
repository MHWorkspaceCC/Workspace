#
# install-sqlserverdsc.ps1
#

try
{
	Write-Log("c:\install-sqlserverdsc.log", "Installing zSqlServer")
	$module = Find-Module -Name xSqlServer -Repository PSGallery 
	Install-Module $module
	Write-Log("c:\install-sqlserverdsc.log", "Installed xSqlServer")
}
catch 
{
	Write-Log("c:\install-sqlserverdsc.log", 'Exception installing sqlserverdsc')
	Write-Log("c:\install-sqlserverdsc.log", $_)
}
