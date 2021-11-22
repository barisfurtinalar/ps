 ##Move tempdb to EC2 instance store for selected SQL instances.
 ##Work in progress##
 
## Logging the process

 ##Logging process
$LogPath = 'C:\Logs'
$LogFile = "$LogPath\DriveCheck.log" 
try {
    if(-not(Test-Path -Path $LogPath -ErrorAction Stop)){
        ##if is not true create a log file to save INFO & ERROR records
        New-Item -ItemType Directory -Path $LogPath -ErrorAction Stop | Out-Null ## bypass output
        New-Item -ItemType File -Path $LogFile -ErrorAction Stop | Out-Null
    }
}
catch{
    throw 
}
Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)-Running... PS Edition: $PSEdition - $PSHOME"

if(-not(Get-Module -Name sqlps -ListAvailable)){
    Add-Content -Path -Value "[ERROR]-$(Get-Date -Format o)-SQL PS Module is not installed"
    throw ## quit the script
}
else{
    Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)-SQL PS Module is installed"
}
 ##Some re-usable logic - get SQL services and add them in a hashtable
 Function Get-SQLInstances {
  Param(
      $Server = $env:ComputerName
      )
    $SQLservicesHash=@{}
    try 
    {
        Get-WmiObject win32_service -computerName $Server | ?{$_.Caption -match "SQL Server*" -and $_.PathName -match "sqlservr.exe"} | Foreach-Object{$SQLservicesHash.Add($_.Name,$_.Status)}
        Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)-SQL Server - Instances found: $SQLservicesHash.Keys"
    }
    catch
    {   
        Add-Content -Path $LogFile -Value "[ERROR]-$(Get-Date -Format o)- No SQL Servicefound: $SQLservicesHash.Keys"
        throw 
    }
    return $SQLservicesHash 
} 

Function Restart-SQLInstances {
   
    try{
        $SQLinstances = (Get-SQLInstances).Keys
        $SQLinstances | Stop-Service -Force
        Write-Output 'Sleeping 10 secs ...'
        Start-Sleep 10
        $SQLinstances | Start-Service 
        Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)-SQL Instances restarted: $SQLintances"
    }
    catch{
        Add-Content -Path $LogFile -Value "[ERROR]-$(Get-Date -Format o)-$SQLinstances failed to meddle with"
        throw
    }
}

function Get-NextAvailableDriveLetter {
    ##English alphabet :)
    $letters=@('E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
    #Array to hold letters in use as drive letters
    $used=@()
    #Array to hold letters not in use
    $available=@()
    foreach($drive in $letters){
        if (Get-Volume -DriveLetter $drive -ErrorAction Ignore)
        {
           ## Add the drive letter to used array
           $used +=$drive
        }
        else
        {
          ##for further functionality   
        }
    }
    $available+=Compare-Object -ReferenceObject $letters -DifferenceObject $used | select -expandproperty inputobject
    ##First available letter to assign.
    return $available[0]
}
##PREPARE DISKS FOR TEMPDB
#$availableDiskletter='Z'
$availableDiskletter=Get-NextAvailableDriveLetter

$NVMe = Get-PhysicalDisk | ? { $_.CanPool -eq $True -and $_.FriendlyName -eq "NVMe Amazon EC2 NVMe"}
New-StoragePool –FriendlyName TempDBPool –StorageSubsystemFriendlyName "Windows Storage*" –PhysicalDisks $NVMe
if($NVMe.Count -eq 1)
{
    New-VirtualDisk -StoragePoolFriendlyName TempDBPool -FriendlyName TempDBDisk -ResiliencySettingName simple -ProvisioningType Fixed -UseMaximumSize
    Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)- Single disk for TempDB is a risky move. Please make up your mind!"
}
elseif($NVMe.Count -eq 2)
{
    New-VirtualDisk -StoragePoolFriendlyName TempDBPool -FriendlyName TempDBDisk -ResiliencySettingName mirror -ProvisioningType Fixed -UseMaximumSize
    Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)- Mirrored virtual disk ready"
}
else{
    # Mirror with NumberOfDataCopies option set to 3 please test
    New-VirtualDisk -StoragePoolFriendlyName TempDBPool -FriendlyName TempDBDisk -ResiliencySettingName mirror  -NumberOfDataCopies 3 -ProvisioningType Fixed -UseMaximumSize
    Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)- Mirrored virtual disk ready (with multiple copies)"
}
##Take into a try/catch block
Get-VirtualDisk –FriendlyName TempDBDisk | Get-Disk | Initialize-Disk –Passthru | New-Partition –DriveLetter $availableDiskletter –UseMaximumSize | Format-Volume -FileSystem NTFS -AllocationUnitSize 65536 -NewFileSystemLabel TempDBfiles -Confirm:$false 
Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)- $availableDiskletter volume created successfully"

$drivepath="$($availableDiskletter):\MSSQL\DATA\"
    if(-not(Test-Path -Path $drivepath -ErrorAction Stop)){
        ##if is not true create a log file to save INFO & ERROR records
        New-Item -ItemType Directory -Path $drivepath -ErrorAction Stop | Out-Null 
        Add-Content -Path $LogFile -Value "[INFORMATION]-$(Get-Date -Format o)- TempDB path at $drivepath configured successfully"
    }

##Assign permissions to SQL server service

 
 ##CREATE AND EXECUTE ALTER STATEMENTS
$SQLinstances = Get-SQLInstances 
$SQLinstancesName = $SQLinstances.Split("$") 
foreach($sqli in $SQLinstancesName){
    if($sqli -match 'MSSQLSERVER')
    {

         $drivepath="$($availableDiskletter):\MSSQL\DATA\$($sqli)\"
        if(-not(Test-Path -Path $drivepath -ErrorAction Stop)){
            ##if is not true create a log file to save INFO & ERROR records
            New-Item -ItemType Directory -Path $drivepath -ErrorAction Stop | Out-Null ## bypass output
        }

        $ALTER=@"
        SELECT 'ALTER DATABASE tempdb MODIFY FILE (NAME = [' + f.name + '],'
        + ' FILENAME = ''$($availableDiskletter):\MSSQL\DATA\$($sqli)\' + f.name
        + CASE WHEN f.type = 1 THEN '.ldf' ELSE '.mdf' END
        + ''');'
        FROM sys.master_files f
        WHERE f.database_id = DB_ID(N'tempdb');
        "@
       $commands=Invoke-Sqlcmd -ServerInstance "$env:COMPUTERNAME" -Query $ALTER | select -ExpandProperty Column1
       foreach($cmd1 in $commands){
            
            Invoke-Sqlcmd -ServerInstance "$env:COMPUTERNAME" -Query $cmd1
       }
       
    }
    elseif($sqli -match "MSSQL"){
       ## 
    }
    ## For named instances
    else{

        $drivepath="$($availableDiskletter):\MSSQL\DATA\$($sqli)\"
        if(-not(Test-Path -Path $drivepath -ErrorAction Stop)){
            ##if is not true create a log file to save INFO & ERROR records
            New-Item -ItemType Directory -Path $drivepath -ErrorAction Stop | Out-Null ## bypass output
        }

            $ALTER=@"
            SELECT 'ALTER DATABASE tempdb MODIFY FILE (NAME = [' + f.name + '],'
            + ' FILENAME = ''$($availableDiskletter):\MSSQL\DATA\$($sqli)\' + f.name
            + CASE WHEN f.type = 1 THEN '.ldf' ELSE '.mdf' END
            + ''');'
            FROM sys.master_files f
            WHERE f.database_id = DB_ID(N'tempdb');
            "@
        $commands=Invoke-Sqlcmd -ServerInstance "$env:COMPUTERNAME\$sqli" -Query $ALTER | select -ExpandProperty Column1
        foreach($cmd2 in $commands){

            Invoke-Sqlcmd -ServerInstance "$env:COMPUTERNAME\$sqli" -Query $cmd2
       }
    }

} 
##RESTART SQL SERVER SERVICES

Restart-SQLInstances
