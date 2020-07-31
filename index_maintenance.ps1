Import-Module SQLPS –DisableNameChecking

$instance = "<instance_name>"
$databaseName = "<db_name>"
$tableName = "<table_name>"
$schemaName = "<schema_name>"
$server = New-Object Microsoft.SqlServer.Management.Smo.Server -Argument $instance
$table = $server.databases.Tables | Where {$_.Schema –eq $schemaName –and $_.Name –eq $tableName }
$fragmentedIX = $table.Indexes | ForEach { $_.EnumFragmentation() | Where { $_.AverageFragmentation –gt 20 }} |
Select -ExpandProperty Index_Name | foreach{Write-Host $_ ;
Invoke-Sqlcmd -ServerInstance $instance -Database $databaseName -Query "Alter Index $_ on $schemaName.$tableName rebuild"; Write-Host "Rebuild. for index $_ initiated!!!"}

 
