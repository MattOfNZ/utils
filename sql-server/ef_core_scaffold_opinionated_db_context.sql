SET NOCOUNT ON;

-- EF Core DbContext Entities Generator - Lightweight
-- Generates simple DbSet properties with exact name mirroring
-- Compatible with SQL Server 2012+

DECLARE @SchemaName NVARCHAR(128) = 'dbo';        -- Target schema name
DECLARE @TableName NVARCHAR(128) = NULL;          -- NULL = entire schema, or specify table name
DECLARE @TargetNamespace NVARCHAR(256) = 'MyApp.Data.Models'; -- Full target namespace for models
DECLARE @DbContextNamespace NVARCHAR(256) = 'MyApp.Data';     -- DbContext namespace
DECLARE @ClassPrefix NVARCHAR(128) = '';          -- Prefix for C# class names
DECLARE @DbContextName NVARCHAR(128) = 'ApplicationDbContext'; -- DbContext class name

-- Validate schema exists
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = @SchemaName)
BEGIN
    PRINT 'Schema [' + @SchemaName + '] not found!';
    RETURN;
END

-- Get tables to process
DECLARE @TablesToProcess TABLE (
    TableName NVARCHAR(128),
    TableSchema NVARCHAR(128)
);

IF @TableName IS NOT NULL
BEGIN
    INSERT INTO @TablesToProcess VALUES (@TableName, @SchemaName);
END
ELSE
BEGIN
    INSERT INTO @TablesToProcess (TableName, TableSchema)
    SELECT TABLE_NAME, TABLE_SCHEMA
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = @SchemaName 
      AND TABLE_TYPE = 'BASE TABLE'
    ORDER BY TABLE_NAME;
END

DECLARE @TableCount INT = (SELECT COUNT(*) FROM @TablesToProcess);

PRINT '=== EF CORE DBCONTEXT ENTITIES GENERATOR ===';
PRINT 'Schema: ' + @SchemaName;
PRINT 'Tables: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT 'Mode: Lightweight - Exact name mirroring';
PRINT '';

-- Generate using statements and class header
PRINT 'using Microsoft.EntityFrameworkCore;';
PRINT 'using ' + @TargetNamespace + ';';
PRINT '';
PRINT 'namespace ' + @DbContextNamespace + ';';
PRINT '';
PRINT 'public class ' + @DbContextName + ' : DbContext';
PRINT '{';
PRINT '    public ' + @DbContextName + '(DbContextOptions<' + @DbContextName + '> options) : base(options) { }';
PRINT '';

-- Generate DbSet properties with exact name mirroring
DECLARE @CurrentTable NVARCHAR(128);
DECLARE @CurrentSchema NVARCHAR(128);

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, TableSchema FROM @TablesToProcess ORDER BY TableName;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @CurrentTable, @CurrentSchema;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @ClassName NVARCHAR(256) = @ClassPrefix + @CurrentTable;
    DECLARE @PropertyName NVARCHAR(256) = @CurrentTable; -- Exact mirroring, no pluralization
    
    PRINT '    public DbSet<' + @ClassName + '> ' + @PropertyName + ' { get; set; }';
    
    FETCH NEXT FROM table_cursor INTO @CurrentTable, @CurrentSchema;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

PRINT '}';
PRINT '';
PRINT '// === LIGHTWEIGHT DBCONTEXT GENERATION COMPLETE ===';
PRINT '// Total DbSets: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT '// Note: Add OnModelCreating configurations as needed for your specific requirements';