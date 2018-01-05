  param(
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
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

	$dataDisk = ((Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter) + ":\"
	Write-Log("The data disk drive letter is " + $dataDisk)


    # copy adventureworks
    $downloadParams = @{ 
        "DownloadId"= 478214
        "FileTime"=129906742867770000
        "Build"=21066
    }

    wget http://download-codeplex.sec.s-msft.com/Download/Release?ProjectName=msftdbprodsamples -Body $downloadParams -UseBasicParsing -OutFile $($dataDisk + "av.zip")

    Unzip $($dataDisk + "av.zip") $dataDisk
    Remove-Item -Path $($dataDisk + "av.zip")

    $files = Get-ChildItem $dataDisk
    foreach ($file in $files){
        $filename = $dataDisk + $file
        Write-Log("Setting permission on: " + $filename)

        $acl = Get-Acl $filename
        Write-Host $acl
        $ar = New-Object  system.security.accesscontrol.filesystemaccessrule("everyone","FullControl","Allow")
        $acl.SetAccessRule($ar)
        Set-Acl $filename $acl
    }

	Write-Log("All done!")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 
 
