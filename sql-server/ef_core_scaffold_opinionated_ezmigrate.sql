SET NOCOUNT ON;

-- Lightweight Migration Controller Generator
-- Generates simple controller methods for data migration using Dapper
-- Compatible with SQL Server 2012+

DECLARE @SourceSchemaName NVARCHAR(128) = 'dbo';   -- Source schema name
DECLARE @TableName NVARCHAR(128) = NULL;           -- NULL = entire schema, or specify table name
DECLARE @ClassPrefix NVARCHAR(128) = '';  -- Prefix for C# class names
DECLARE @ControllerName NVARCHAR(128) = 'YourController'; -- Controller class name
DECLARE @DbContextProperty NVARCHAR(128) = '_dbContext'; -- DbContext field name

-- Validate schema exists
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = @SourceSchemaName)
BEGIN
    PRINT 'Schema [' + @SourceSchemaName + '] not found!';
    RETURN;
END

-- Get tables to process
DECLARE @TablesToProcess TABLE (
    TableName NVARCHAR(128),
    TableSchema NVARCHAR(128)
);

IF @TableName IS NOT NULL
BEGIN
    INSERT INTO @TablesToProcess VALUES (@TableName, @SourceSchemaName);
END
ELSE
BEGIN
    INSERT INTO @TablesToProcess (TableName, TableSchema)
    SELECT TABLE_NAME, TABLE_SCHEMA
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = @SourceSchemaName 
      AND TABLE_TYPE = 'BASE TABLE'
    ORDER BY TABLE_NAME;
END

DECLARE @TableCount INT = (SELECT COUNT(*) FROM @TablesToProcess);

PRINT '=== LIGHTWEIGHT MIGRATION CONTROLLER GENERATOR ===';
PRINT 'Source Schema: ' + @SourceSchemaName;
PRINT 'Tables: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT 'Controller: ' + @ControllerName;
PRINT '';

-- Generate controller header (for reference)
PRINT '// Controller class structure (add to your existing controller):';
PRINT '// private readonly DbContext ' + @DbContextProperty + ';';
PRINT '// private readonly string _connectionString;';
PRINT '// public ' + @ControllerName + '(DbContext dbContext)';
PRINT '// {';
PRINT '//     ' + @DbContextProperty + ' = dbContext;';
PRINT '//     _connectionString = "TODOTODO";';
PRINT '// }';
PRINT '';

-- Generate migration methods
DECLARE @CurrentTable NVARCHAR(128);
DECLARE @CurrentSchema NVARCHAR(128);

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, TableSchema FROM @TablesToProcess ORDER BY TableName;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @CurrentTable, @CurrentSchema;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @ClassName NVARCHAR(256) = @ClassPrefix + @CurrentTable;
    DECLARE @MethodName NVARCHAR(256) = @CurrentTable;
    DECLARE @RouteParam NVARCHAR(256);
    
    -- Convert PascalCase to kebab-case for route
    -- Simple conversion: insert hyphens before capitals (except first)
    DECLARE @i INT = 2;
    DECLARE @RouteBuilder NVARCHAR(256) = LOWER(LEFT(@MethodName, 1));
    
    WHILE @i <= LEN(@MethodName)
    BEGIN
        DECLARE @CurrentChar CHAR(1) = SUBSTRING(@MethodName, @i, 1);
        IF ASCII(@CurrentChar) BETWEEN 65 AND 90 -- If uppercase
            SET @RouteBuilder = @RouteBuilder + '-' + LOWER(@CurrentChar);
        ELSE
            SET @RouteBuilder = @RouteBuilder + @CurrentChar;
        SET @i = @i + 1;
    END
    
    SET @RouteParam = @RouteBuilder;
    
    -- Generate the method
    PRINT '[HttpPost("' + @RouteParam + '")]';
    PRINT 'public async Task<IActionResult> ' + @MethodName + '()';
    PRINT '{';
    PRINT '    using var connection = new SqlConnection(_connectionString);';
    PRINT '    connection.Open();';
    PRINT '    var ' + LOWER(@MethodName) + 's = connection.Query<' + @ClassName + '>("SELECT * FROM [' + @CurrentSchema + '].[' + @CurrentTable + ']");';
    PRINT '    ' + @DbContextProperty + '.' + @CurrentTable + '.AddRange(' + LOWER(@MethodName) + 's);';
    PRINT '    await ' + @DbContextProperty + '.SaveChangesAsync();';
    PRINT '    return Ok();';
    PRINT '}';
    PRINT '';
    
    FETCH NEXT FROM table_cursor INTO @CurrentTable, @CurrentSchema;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

PRINT '// === LIGHTWEIGHT CONTROLLER GENERATION COMPLETE ===';
PRINT '// Total methods: ' + CAST(@TableCount AS NVARCHAR(10));
