param(
    [string]$driveLabel="WorkspaceDB",
    [string]$driveLetter="E"
) 

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
} 

$volume = Get-Volume -FileSystemLabel $driveLabel -ErrorVariable err -ErrorAction SilentlyContinue
if ($volume -ne $null){
    return ${
        "DriveLetter" = $volume.DriveLetter
        "Created" = $false
    }
}

$raw = $dataDisk = Get-Disk | `
    Where partitionstyle -eq 'raw' | `
    Select-Object -first 1

if ($raw -eq $null){
    throw "Could not find a raw disk"
}

Write-Host "Got raw disk - formatting"

$dataDisk | 
    Initialize-Disk -PartitionStyle MBR -PassThru | `
    New-Partition -DriveLetter $driveLetter -UseMaximumSize | `
    Format-Volume -FileSystem NTFS -NewFileSystemLabel $driveLabel -Confirm:$false | 
    Write-Log

Write-Log "All done!"

@{
    "DriveLetter" = $volume.DriveLetter
    "Created" = $true
}
