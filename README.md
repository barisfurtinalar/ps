# ps/sql
Powershell & TSQL Scripts 

SQL Index Maintenance = checks fragmentation for indexes of a given table for >20% fragmentation and rebuilds the index. 

space-used-by-each-table.sql = To check the space used by each table

## Get-SQLClusterRegistryKeys.ps1
Search the registry for SQL Server cluster resource keys. 3 registry keys have to be present per SQL instance (SQL Server,SQL Server CEIP, SQL Server Agent)

