
	#########################################################################
	# Initialization Block													#
	#########################################################################	
	import-module webadministration
	# <$srcdir> + <srccontent>
	#   Use this variable to control where the script will copy additional contents from.
	#   Examples:
	#	   D: or \\1.2.3.4\d$
	#
	$srcdir	        = "\\x.x.x.x\share$"
	$srccontent	= "$srcdir\content"
	$dstcontent	= "<Drive>:\wwwroot"
	#
	$envtag			= 1;
	#
	$global:lastsite= "nullsite"
	$defaultsite 	= "Default Web Site"
	$hostname		= (hostname)
	$IISLogsWebsite	= "<IIS Logs Path>"
	#
	#########################################################################
	# Functions Block														#
	#########################################################################
	Function PrintMsg ($string){
		Write-Host "($hostname) $String `r"
	}	
	Function WarningMsg ($string){
		Write-Host -ForegroundColor yellow -BackgroundColor black "($hostname) $String `r"
	}
	Function LoadTable($type, $site){
		switch($type){
			"vdirs" {
				$SqlQuery = "SELECT vd_id, flag, site As Site, vdir As Nome, pool As Apppool, path As Path FROM vdirs WHERE flag=$envtag"
			}
			"sites" {			
				$SqlQuery = "SELECT s_id, site As Site, ip As IP, port As Port, header As HostHeader FROM sites WHERE site='$site'"
			}
		}
		$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
		$SqlConnection.ConnectionString = "Password=*****;Persist Security Info=True;User ID=myuser;Initial Catalog=MyCatalog;Data Source=myserver,port"
		# 
		$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
		$SqlCmd.CommandText = $SqlQuery
		$SqlCmd.Connection  = $SqlConnection
		#
		$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$SqlAdapter.SelectCommand = $SqlCmd
		#
		$DataSet = New-Object System.Data.DataSet
		#
		# Prefixing with [void] to avoid the first row which 
		# is the row count from the select.
		# ref: http://stackoverflow.com/questions/16244515/powershell-dataset-contains-the-number-of-records
		[void]$SqlAdapter.Fill($DataSet)
		#
		$SqlConnection.Close()
		return $DataSet.Tables[0]
	}
	Function SetHostHeaders($site){
		$hhlist = LoadTable "sites" $site
		if($hhlist){
			$hhlist | foreach-object {
				$port = $_.Port
				$ip	  = $_.IP
				$hh	  = $_.HostHeader
				if (!(get-webbinding | where-object { $_.bindinginformation -eq "${ip}:${port}:${hh}" }) ){
					PrintMsg "New bind '$hh' on port '$port' created."
					New-Webbinding -Name $site -Port $port -IPAddress $ip -HostHeader $hh
				} else {
					WarningMsg "Bind ${ip}:${port}:${hh} Exists. Skipping.."
				}
			}
		}
	}
	Function CheckSourceVdir($VdirName){
		$IISPath = "IIS:\Sites\$defaultsite\$VdirName"
		#
		if (Test-Path $IISPath) {
			#PrintMsg("Source VDIR $defaultsite->$VdirName FOUND!")
			return $true
		} else {
			write-host $IISPath
			WarningMsg("Source VDIR $defaultsite->$VdirName NOT FOUND! Skipping...")
			return $false
		}
	}
	Function GetVdirPath($VdirName){
		$object = Get-WebApplication -Site $defaultsite -Name $VdirName | Select PhysicalPath
		return $object.PhysicalPath
	}
	Function CheckDestSite($site){
		# Create/Update destination site physical path from content.
		if (Test-Path "$srccontent\$site"){
			if( $global:lastsite -ne $site ){
				PrintMsg ("Updating '$site' site content...")
				Copy-Item "$srccontent\$site" -Destination $dstcontent -recurse -force
			}
		} else {
			if(Test-Path "$dstcontent\$site"){
				WarningMsg("Content source at '$dstcontent\$siteName' FOUND! Ignoring content copy/update...")
			} else {
				WarningMsg("Source content at '$srccontent\$siteName' NOT FOUND! Skipping...")
				return $false
			}
		}
		#
		# Check if Website exists on IIS.
		$iisWebSite = Get-WebSite *$site* | Select Name
		if(!$iisWebSite) {
			WarningMsg("Destination website `"$site`" NOT FOUND! Creating.")
			#
			# Site does not exists. Let's create it.
			New-Item iis:\Sites\$site -bindings @{protocol="http";bindingInformation=":80:$site"} -physicalPath "$dstcontent\$site"
			New-Item -Path "$IISLogsWebsite\$site" -type directory -Force -ErrorAction SilentlyContinue
			Set-ItemProperty "IIS:\Sites\$site" -name logFile.directory -value $IISLogsWebsite
			#
			$iisWebSite = Get-WebSite $site* | Select Name
			if(!$iisWebSite) {
				WarningMsg("FAILED to create website '$site'. Skipping...")
				return $false
			} else {
				PrintMsg  ("Website '$site' created successfully!")
			}
		}
		if ($iisWebSite.Count -gt 1) {
			WarningMsg("More than one site with the name `"$site`" exists! Skipping...")
			return $false
		}
		# Update Host Headers
		if( $global:lastsite -ne $site ){
			SetHostHeaders($site)
		}
		$global:lastsite = $site
		#
		return $true
	}
	Function CreateVirtDir($object){
		$pool = $object.Apppool
		$vdir = $object.Nome
		$site = $object.Site
		$path = $object.Path
		# Check if SOURCE VDIR exists AND Check/Create DESTINATION Site.
		if ( (CheckSourceVdir($vdir)) -and (CheckDestSite($site)) ){
			# Check if Application Pool exists. 
			# If not create it or fail.
			if (!(Test-Path "IIS:\AppPools\$pool")){
				WarningMsg("Application pool $pool NOT FOUND! Creating pool...")
				#			
				if ( New-WebAppPool -Name $pool -ErrorAction SilentlyContinue ){
					PrintMsg  ("Application pool $pool created successfully!")
				} else {
					WarningMsg("FAILED to create application pool $pool. Skipping...")
					return $false
				}
			}
			# Check if VDIR source physical path exists.
			if (!$path){
				# Create VDIR from Default Website
				$PP = GetVdirPath($vdir)
			} else {
				# Create VDIR from supplied path
				if(Test-Path $path){
					$PP = $path
				} else {
					WarningMsg("VDIR '$vdir' SOURCE directory '$path' does NOT EXISTS. Skipping...")
					return $false
				}
			}			
			if($PP){
				# Check if VDIR already exists on DESTINATION site.
				$SS = Get-WebApplication -Name $vdir -Site $site
				if($SS){
				    # If exists, make sure VDIR uses newly created Application Pool.
					$oldpool = $SS.ApplicationPool
					If($pool -eq $oldpool){
						WarningMsg("VDIR '$site->$vdir' already EXISTS! Skipping...")
					} else {
						WarningMsg("VDIR '$site->$vdir' on different application pool ($oldpool) detected! Setting to '$pool'.")
						Set-ItemProperty IIS:\Sites\$site\$vdir ApplicationPool $pool
					}
				} else { 
					# If does NOT exists. Try to create VDIR on DESTINATION site using newly created Application Pool.
					if( new-WebApplication -Site $site -Name $vdir -PhysicalPath $PP -ApplicationPool $pool -ErrorAction SilentlyContinue ){
						PrintMsg  ("VDIR '$site->$vdir' created successfully!")
					} else {
						WarningMsg("FAILED to create application pool $pool. Skipping...")
						return $false
					}
				}
			} else {
				# Source Physical Path does NOT exist. Fail.
				return $false
			}			
		}
		return $true
	}
	#########################################################################
	# Main Execution Block													#
	#########################################################################
	#
	########################################
	# FLAGS:                               #
	#     0 - IGNORE                       #
	#     1 - PUBLISH VDIR                 #
	########################################
	Clear
	PrintMsg("Initializing...")
	#
	$vdirs = LoadTable "vdirs"
	#
	$vdirs | foreach-object {
		if ($_.Flag -eq $envtag){
			CreateVirtDir($_) | out-null
		}
	}
