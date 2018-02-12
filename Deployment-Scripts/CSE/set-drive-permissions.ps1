param(
    [string]$driveLabel,
    [string]$group="everyone",
    [string]$right="Fullcontrol",
    [string]$controlType="Allow"
)
Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

$volume = Get-Volume -FileSystemLabel $driveLabel -ErrorVariable err -ErrorAction SilentlyContinue
if ($volume -eq $null){
    throw "Did not find a drive with label: " + $driveLabel
}

$filename = $volume.DriveLetter + ":\"
$acl = Get-Acl $filename
Write-Host $acl
$ar = New-Object  system.security.accesscontrol.filesystemaccessrule("everyone","FullControl","Allow")
$acl.SetAccessRule($ar)
Set-Acl $filename $acl	

Write-Log "All done!"