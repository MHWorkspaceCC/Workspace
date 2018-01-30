EXEC sp_configure 'show advanced options', 1
GO
RECONFIGURE
GO

EXEC sp_configure 'clr enabled', 1
GO
EXEC sp_configure 'cost threshold for parallelism', 40
GO
EXEC sp_configure 'max degree of parallelism', 6
GO
DECLARE @maxRam INT = 
(
   SELECT
       (total_physical_memory_kb / 1024) - 8192
   FROM sys.dm_os_sys_memory
)

EXEC sp_configure 'max server memory (MB)', @maxRam
GO
RECONFIGURE
GO