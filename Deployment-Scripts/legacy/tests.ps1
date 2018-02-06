$var = "HI"

$scriptBlocksToRun1 = New-Object System.Collections.ArrayList

foreach ($i in @("HI", "there", "mike")){
	$sb = {
		Write-Host "HI" $local
	}
	
	$scriptBlocksToRun1.Add($sb) | Out-Null
}

$parameterScriptBlock = {
	param([string]$local)
}

$jobs = New-Object System.Collections.ArrayList 
$i = 0
foreach ($scriptBlock in $scriptBlocksToRun1){
	$modifiedScriptBlock = [scriptblock]::Create($parameterScriptBlock.ToString() + " " + $scriptBlock.ToString())

	$job = Start-Job -ScriptBlock $modifiedScriptBlock -Arg $i
	$jobs.Add($job) | Out-Null
	$i++
}

while ($true){
	$alldone = $true
	foreach ($job in $jobs){
		Write-Host $job.State
		if ($job.State -ne [System.Management.Automation.JobState]::Completed){
			$alldone = $false
			break
		}
	}

	if ($alldone) { break }

	foreach ($job in $jobs){
		if ($job.HasMoreData){
			$data = Receive-Job $job
			Write-Host $data
		}
	}

	Wait-Job -Job $jobs -Timeout 2 
}

foreach ($job in $jobs){
	if ($job.HasMoreData){
		$data = Receive-Job -Job $job
		foreach ($i in $data) { 
			Write-Host $i 
		}
		Write-Host $data
	}
}
<#
while (
	
	$job.State -ne [System.Management.Automation.JobState]::Completed){
	if ($job.HasMoreData){
		$data = Receive-Job $job
		Write-Host $data
	}
	Wait-Job $job -Timeout 2
}
if ($job.HasMoreData){
	$data = Receive-Job $job
	Write-Host $data
}
#>