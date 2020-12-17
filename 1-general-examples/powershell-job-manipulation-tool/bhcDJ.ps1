function Select-Environment 
{
	$envString = ""
	[String]$envInfo = ctm env sh
	$index = $envInfo.IndexOf('{')
	$envStart = $envInfo.Substring(0, $index)
	$startWords = -split $envStart
	$dfltEnv = $startWords[2]
	$envData = $envInfo.Substring($index)
	$envJson = ConvertFrom-Json $envData

	if ($envJson.psobject.properties.Name.Count -eq 1) {
		$envName = $envJson.psobject.properties.Name
		$endPoint = $envJson.psobject.properties.Value.endPoint
		Write-Host "Using Default environment $envName"
	} else {
		Write-Host "Environments: "
		Write-Host "  Name `t`tUser `t`tendPoint"
		$envCtr = 0
		foreach ($env in $envJson.psobject.properties) {
			$envCtr++
			$eName = $env.Name
			$eUser = $env.Value.user
			$eEP = $env.Value.endPoint
			if ($eName -eq $dfltEnv) {
				$dfltEndpoint = $eEP
			}
			Write-Host "$envCtr $eName" -noNewLine
			if ($eName.Length -lt 6) {
				Write-Host "`t" -noNewLine
			}
			Write-Host "`t$eUser" -noNewLine
			if ($eUser.Length -lt 8) {
				Write-Host "`t" -noNewLine
			}
			Write-Host "`t$eEP "
		}	
		$envNum = Read-Host "Choose Environment number to use or d for default ($dfltEnv)"	
		Try {
			[Int]$envSelect = $envNum
			$envName = $envJson.psobject.properties.Name[$envNum - 1]
			$endPoint = $envJson.psobject.properties.Value[$envNum - 1].endPoint
		}
		Catch {
			if ($envNum -eq "d") {
				$envName = $dfltEnv
				$endPoint = $dfltEndpoint
			}
		}
		Write-Host "Using environment $envName"
	}
#--------------------------------------------------------------------------
#	Session Login is used to determine version of restserver and if
#	"deleted=false" filter is supported for the ctm run service
#	but it is not yet available in SaaS so checking for 'saas' in endpoint
#	as a temporary kludge.
#--------------------------------------------------------------------------
	if ($endPoint.IndexOf('saas') -gt 0) {
		Write-Host Assuming SaaS environment based on endpoint
		$subVersion = "20"
		$monthly = "40"
	}
	else {
		[String]$ctmInfo = ctm session login -e $envName
		$ctmJSON = ConvertFrom-JSON $ctmInfo
		$ctmVersion = $ctmJSON.version
		$version, $subVersion, $monthly = $ctmVersion -split '\.'
	}

	
	return($envName, $subVersion, $monthly)
}

function Do-Folders
{
	$folderFilter = Read-Host "Please enter a folder name or prefix to search. Enter to quit"
	While ($folderFilter -ne "q") {

		$folderCtr = 0
		[String]$folderJSON = ctm deploy jobs::get -e $envName -s """ctm=*&folder=$folderFilter"""
		if ($folderJSON.Length -eq 0) {
			Write-Host No folders found for selection criteria: folder = $folderFilter
		}
		else {
			$folderObj = ConvertFrom-Json -InputObject $folderJSON
			$jobInfo = @()

			foreach($folder in $folderObj.PsObject.Properties)
			{
				$folderCtr++
				Add-Member -InputObject $folder -MemberType NoteProperty -Name sq -Value $folderCtr
				Add-Member -InputObject $folder -MemberType NoteProperty -Name ft -Value "Smart"
			}
			
			$a = @{Expression={$_.sq}; Label="SQ"; Width=3}, 
				@{Expression={$_.Name}; Label="Folder Name"; Width=30},
				@{Expression={$_.Value.OrderMethod}; Label="Order Method"; Width=10},				
				@{Expression={$_.Value.ControlmServer}; Label="Control-M Server"; Width=20}, 
				@{Expression={$_.ft}; Label="Folder Type"; Width=7}
				
				$folderObj.PsObject.Properties | Format-Table -Property $a

			$folderSelect = 0			
			While (($folderSelect -lt 1) -Or ($folderSelect -gt $folderCtr)) {
				$reply = Read-Host "Enter folder sequence # to process or "q" to quit"
				Try {
					[Int]$folderSelect = $reply
				}
				Catch {
					if ($reply -eq "q") {Break}
				}
			}
			
			If ($reply -ne "q") {
				$function = Read-Host "Select action: o (Order) or q (quit)"
				Switch ($function)
					{
						o {ctm run order $folderObj.PsObject.Properties.Value[$folderSelect-1].ControlmServer $folderObj.PsObject.Properties.Name[$folderSelect-1] -e $envName}
						Default {
							Write-Host "Valid selections are o (Order) or q (quit)"
						}
					}
			}
		}
		
		$saveFilter = $folderFilter
		$folderFilter = Read-Host "Please enter a folder name or prefix to search, Enter to repeat same criteria, q to quit"
		if ($folderFilter -eq "") {
			$folderFilter = $saveFilter
		}
	} 
}

function Do-Jobs
{
	$folderFilter = Read-Host "Please enter a folder name or prefix to search. Enter to quit"
	While ($folderFilter -ne "q") {
		if (($subVersion -eq 20) -And ($monthly -gt 10)) { 

			[String]$jobInfo = ctm run jobs:status::get -e $envName -s """ctm=*&folder=$folderFilter&deleted=false"""
		} else {
			[String]$jobInfo = ctm run jobs:status::get -e $envName -s """ctm=*&folder=$folderFilter"""
		}
		$jobHash = ConvertFrom-JSON $jobinfo
		[Int]$returnedJobs = $jobHash.returned
		
		if ($returnedJobs -gt 0) {
			$jobCtr = 0
			foreach ($job in $jobHash.statuses)
			{
				$jobCtr++
				Add-Member -InputObject $job -MemberType NoteProperty -Name sq -Value $jobCtr
			}
			$jobHash.statuses | Format-Table -RepeatHeader -Property sq, name, folder, status, jobId, application, subApplication, startTime, endTime, host, cyclic
			
			$jobSelect = 0
			
			While (($jobSelect -lt 1) -Or ($jobSelect -gt $returnedJobs)) {
				$reply = Read-Host "Enter job sequence # to process or "q" to quit"
				Try {
					if ($reply.Length -eq 0) {
						$reply = "r"
						Break
					}
					else {[Int]$jobSelect = $reply}
				}
				Catch {
					if ($reply -eq "q") {Break}
				}
			}
		
			If (($reply -ne "q") -AND ($reply -ne "r")) {			
				$jobId = $jobHash.statuses.jobId[$jobSelect - 1]

				$function = Read-Host "Select action: b (Bypass), c (confirm), d (details), k (Kill), l (Log), n (Rerun now), o (Output), r (Rerun) or q (quit)"
				Switch ($function)
					{
						b {ctm run job::runNow $jobId -e $envName}
						c {ctm run job::confirm $jobId -e $envName}
						d {ctm run job:status::get $jobId -e $envName}
						k {ctm run job::kill $jobId -e $envName}
						l {ctm run job:log::get $jobId -e $envName}
						n { 
							ctm run job::rerun $jobId -e $envName
							ctm run job::runNow $jobId -e $envName
						}
						o {ctm run job:output::get $jobId -e $envName}
						r {ctm run job::rerun $jobId -e $envName}
						Default {
							Write-Host "Valid selections are b (Bypass), d (details), k (Kill), l (Log), n (Rerun now), o (Output), r (Rerun) or q (quit)"
						}
					}
			}

			
		} else {
			Write-Host "No jobs found to match folder=$folderFilter"
		}
		$saveFilter = $folderFilter
		if ($reply -ne "r") {
			$folderFilter = Read-Host "Please enter a folder name or prefix to search, Enter to repeat same criteria, q to quit"
		}
		if ($folderFilter -eq "") {
			$folderFilter = $saveFilter
		}
	} 
}

$envName, $subVersion, $monthly = Select-Environment

	While ($function -ne "q") {
		$function = Read-Host "Select action: e (Select Environment), j (Job Processing), f (Folder Processing or q (quit)"
		Switch ($function)
			{
				j {Do-Jobs}
				e {$envName, $subVersion, $monthly = Select-Environment}
				f {Do-Folders}
				q {}
				Default {
					Write-Host "Valid selections are e (Select Environment), j (Job Processing), f (Folder Processing or q (quit)"
				}
			}
	}
