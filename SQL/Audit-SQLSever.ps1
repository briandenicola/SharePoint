[CmdletBinding(SupportsShouldProcess=$true)]
param ( 
	[Parameter(Mandatory=$true)]	
    [string] $computer,
    [string] $cluster_name = [String]::Empty,
	[string[]] $cluster_nodes = [String]::Empty, 
	[int] $port = -1,
	[switch] $upload,
	[switch] $nosql,
	[switch] $sharepoint,
	[switch] $database
)

$current_dir = $PWD.Path

. (Join-PATH $ENV:SCRIPTS_HOME "Libraries\Standard_Functions.ps1")
. (Join-PATH $ENV:SCRIPTS_HOME "Libraries\SharePoint_Functions.ps1")
Import-Module sqlps -EA Stop -DisableNameChecking

cd $current_dir

if( $sharepoint ) {
	$global:url =  ""
	$global:list = "SQL Servers"
	$global:view = '}'
}
elseif( $database ) {
	$global:url =  ""
	$global:list = "Database Servers"
	$global:view = ''
}
else { 
	$global:url =  ""
	$global:list = "SQL Servers"
	$global:view = ''
}

function Get-SPFormattedServers ( [String[]] $computers )
{
	$sp_formatted_data = [String]::Empty
	
	$sp_server_list = Get-SPListViaWebService -url $global:url  -list $global:list -view $global:view
	foreach( $computer in $computers ) {
		$id = $sp_server_list | where { $_.SystemName -eq $computer } | Select -ExpandProperty ID
		$sp_formatted_data += "#{0};#{1};" -f $id, $computer
	}
	
	Write-Verbose $sp_formatted_data
	
	return $sp_formatted_data.TrimStart("#").TrimEnd(";").ToUpper()
}

function Audit-Server
{
	param ( 
		[string] $server,
		[object] $audit
	)
	
	Write-Verbose "[ $(Get-Date) ] - Auditing server - $server  . . . "
	
	$computer = Get-WmiObject Win32_ComputerSystem -ComputerName $server
	$os = Get-WmiObject Win32_OperatingSystem -ComputerName $server
	$bios = Get-WmiObject Win32_BIOS -ComputerName $server
	$nics = Get-WmiObject Win32_NetworkAdapterConfiguration -ComputerName $server
	$cpu = Get-WmiObject Win32_Processor -ComputerName $server | select -first 1 -expand MaxClockSpeed
	$disks = Get-WmiObject Win32_LogicalDisk -ComputerName $server
	
	$audit | add-member -type NoteProperty -name Domain -Value $computer.Domain		
	$audit | add-member -type NoteProperty -name Model -Value ($computer.Manufacturer + " " + $computer.Model.TrimEnd())
	$audit | add-member -type NoteProperty -name Processor -Value ($computer.NumberOfProcessors.toString() + " x " + ($cpu/1024).toString("#####.#") + " GHz")
	$audit | add-member -type NoteProperty -name Memory -Value ($computer.TotalPhysicalMemory/1gb).tostring("#####.#")
	$audit | add-member -type NoteProperty -name SerialNumber -Value ($bios.SerialNumber.TrimEnd())
	$audit | add-member -type NoteProperty -name OperatingSystem -Value ($os.Caption + " - " + $os.ServicePackMajorVersion.ToString() + "." + $os.ServicePackMinorVersion.ToString())

	Write-Verbose "[ $(Get-Date) ] - $($audit) "
	
	return $audit
}

function Get-SQLServerVersion
{
	param (
		[string] $ver
	)
	
	Write-Verbose "[ $(Get-Date) ] - Getting SQL Server version  . . . "
	
	if( $ver -match "11.0" ) { return "SQL Server 2012" }
	if( $ver -match "10.50" ) { return "SQL Server 2008/R2" }
	if( $ver -match "10.0" ) { return "SQL Server 2008" }
	if( $ver -match "9.00" ) { return "SQL Server 2005" }
	if( $ver -match "8.00" ) { return "SQL Server 2000" }
	
	return "Unknown Version"
}

function Get-SQLRunningInstances 
{
	param (
		[string] $computer
	)
	
	Write-Verbose "[ $(Get-Date) ] - Getting SQL Server instances  . . . "
	
	$instances = @(Get-Service -ComputerName $computer | Where { $_.Status -eq "Running" -and ($_.Name -match "MSSQLServer" -or $_.Name -match "MSSQL\$") } | Select -Unique -Expand Name)
	
	for( $i=0; $i -lt $instances.Count; $i++ ) { 
		if( $instances[$i] -ne "MSSQLSERVER" ) { $instances[$i] = $instances[$i].Split("$")[1] }
	}
	
	Write-Verbose "Found instances - $($instances) . . ."

	return $instances
}

function Get-SupportedOS 
{
	param (
		[string] $ver
	)
	
	if( [String]::IsNullOrEmpty($ver) ) { 
		return $false
	} 
	else {
		return ( [System.Convert]::ToDecimal( $ver.Split(" ")[0] ) -ge 6.1 )
	}
}

function Get-SQLClusterNodes 
{
	param ( 
		[string] $name
	)
	
	Write-Verbose "[ $(Get-Date) ] - Getting SQL Server Cluster Nodes for $($name) . . . "
	
	$sp_server_list = Get-SPListViaWebService -url $global:url  -list $global:list -view $global:view
		
    if( $name -ne [String]::Empty ) {
		Write-Verbose "[ $(Get-Date) ] - Getting SQL Server Cluster Nodes automatically . . . "
		$cluster = Get-Cluster -name $name -EA Stop  
		$nodes = $cluster | Get-ClusterNode | Select -Expand Name
	}
	else {
		Write-Verbose "[ $(Get-Date) ] - Getting SQL Server Cluster Nodes manually . . . "
		$nodes = @($cluster_nodes)
	}

	foreach( $node in $nodes ) 
	{
		if( ($sp_server_list | where { $_.SystemName -eq $node }) -eq $null ) {
			Write-Verbose "[ $(Get-Date) ] - $node was not found in SharePoint Server List. Going to Audit and Upload  . . . "
			
			$audit = Audit-Server -server $node -Audit ( New-Object PSObject -Property @{SystemName = $node;Role="Database Node";"IPAddresses"=(Get-IPAddress $node)} )
			
			if( $upload ) { 
				WriteTo-SPListViaWebService -url $global:url -list $global:list -Item $(Convert-ObjectToHash $audit) -TitleField SystemName 
			}
		}
	}
	
	return ( Get-SPFormattedServers $nodes )
}

function main
{
	$db = @()
	
	if( $cluster_name -ne [String]::Empty ) {
		Import-Module FailoverClusters -EA SilentlyContinue
		if( $? -eq $true ) { $cluster_module_loaded = $true } else { $cluster_module_loaded = $false }
	}
	
	$instances = Get-SQLRunningInstances -computer $computer	
	foreach( $instance in  $instances ) { 
		Write-Verbose "[ $(Get-Date) ] - Working on instance - $instance on $computer  . . . "
		if( $instance -eq $null ) { continue } 
	
		try {
			$properties = New-Object PSObject -Property @{
				SystemName = $computer
				Instance = $instance 
				IPAddresses = ( Get-IPAddress $computer )
			}
			
			if( $instance -eq "MSSQLSERVER" ) {
				$sql = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -Argument $computer
			} 
			else {
				if( $port -eq -1 ) { $con_str = $computer + "\" + $instance } else { $con_str = $computer + "," + $port + "\" + $instance }
				$sql = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -Argument $con_str
			}
			
			$properties | Add-Member -type NoteProperty -name Edition -Value $sql.Edition
			$properties | Add-Member -type NoteProperty -name OSVersion -Value $sql.OSVersion
			$properties | Add-Member -type NoteProperty -name IsClustered -Value $sql.IsClustered 
			$properties | Add-Member -type NoteProperty -name VersionString -Value $sql.VersionString
			$properties | Add-Member -type NoteProperty -name ServiceAccount -Value $sql.ServiceAccount 
			$properties | Add-Member -type NoteProperty -name SQLVersion -Value (Get-SQLServerVersion $sql.VersionString)
			$properties | Add-Member -type NoteProperty -name Databases -Value ( [String]::join(";", ($sql.Databases | Select -Expand Name)) )
		
			if( -not $nosql ) {
				$wmi = new-object "Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer" $computer
				$properties | Add-Member -type NoteProperty -name Port -Value ( $wmi.ServerInstances | Where { $_.Name -eq $instance } | Select -Expand ServerProtocols | Where { $_.DisplayName -eq "TCP/IP"} ).IpAddresses["IPAll"].IPAddressProperties["TcpPort"].Value
			}
		
			if( $properties.IsClustered -eq $false ) { 
				Write-Verbose "[ $(Get-Date) ] - SQL Server is a standalone instance so going to audit server  . . . "
				$properties | Add-Member -type NoteProperty -name Role -Value "Standalone Database Server" 
				$properties = Audit-Server -server $computer -audit $properties
			}
			else {
				Write-Verbose "[ $(Get-Date) ] - SQL Server is clustered so going to determine cluster nodes  . . . "
				$properties | Add-Member -type NoteProperty -name Role -Value "Database Cluster"
				Write-Verbose "[ $(Get-Date) ] - OS Version is $($sql.OSVersion) . . ."
				if ( ( $cluster_module_loaded = $true -and ( Get-SupportedOS -ver $sql.OSVersion ) ) -or ( $cluster_nodes -ne [String]::Empty) )  {
					$properties | Add-Member -type NoteProperty -name Nodes -Value ( Get-SQLClusterNodes -name $cluster_name )
				} 
			}
			
			if( $upload ) {
				Write-Verbose "[ $(Get-Date) ] - Upload was passed on command line. Will upload results to $global:url ($global:list)  . . . "
				WriteTo-SPListViaWebService -url $global:url -list $global:list -Item $(Convert-ObjectToHash $properties) -TitleField SystemName 
			}
			$db += $properties
		} 
		catch [System.Exception] {
			Write-Error ("The Audit failed on $computer ($instance) - " +  $_.Exception.ToString() )
		}
	}
	
	return $db
}
main
