set nocount on 

-- EF Core Class Generator SQL Script - Simple and Exact
-- Compatible with SQL Server 2012+ - Exact column names, no transformations
-- Usage: Replace @SchemaName and @TableName with your target schema and table

DECLARE @SchemaName NVARCHAR(128) = 'dbo';  -- Replace with your schema name
DECLARE @TableName NVARCHAR(128) = 'TableName'; -- Replace with your table name

-- Verify table exists
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = @SchemaName AND TABLE_NAME = @TableName)
BEGIN
    PRINT 'Table [' + @SchemaName + '].[' + @TableName + '] not found!'
    RETURN
END

-- Get total column count
DECLARE @TotalColumns INT
SELECT @TotalColumns = COUNT(*) 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_SCHEMA = @SchemaName AND TABLE_NAME = @TableName

PRINT 'Total columns found: ' + CAST(@TotalColumns AS NVARCHAR(10))
PRINT ''

PRINT '=== CLASS HEADER ==='
PRINT '// Add these using statements to your file:'
PRINT '// using System.ComponentModel.DataAnnotations;'
PRINT '// using System.ComponentModel.DataAnnotations.Schema;'
PRINT '// using Microsoft.EntityFrameworkCore;'
PRINT ''
PRINT '[Table("' + @TableName + '", Schema = "' + @SchemaName + '")]'
PRINT 'public class ' + @TableName
PRINT '{'

-- Get primary key columns
DECLARE @PKColumns TABLE (COLUMN_NAME NVARCHAR(128))
INSERT INTO @PKColumns
SELECT ku.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku 
    ON tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
    AND tc.TABLE_SCHEMA = ku.TABLE_SCHEMA
WHERE tc.TABLE_SCHEMA = @SchemaName 
  AND tc.TABLE_NAME = @TableName
  AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'

-- Generate properties using cursor for reliable output
DECLARE @ColumnName NVARCHAR(128)
DECLARE @DataType NVARCHAR(128)
DECLARE @IsNullable NVARCHAR(3)
DECLARE @MaxLength INT
DECLARE @IsPrimaryKey BIT
DECLARE @CSharpType NVARCHAR(50)
DECLARE @PropertyOutput NVARCHAR(MAX)

DECLARE column_cursor CURSOR FOR
SELECT 
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.IS_NULLABLE,
    c.CHARACTER_MAXIMUM_LENGTH,
    CASE WHEN pk.COLUMN_NAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
FROM INFORMATION_SCHEMA.COLUMNS c
LEFT JOIN @PKColumns pk ON c.COLUMN_NAME = pk.COLUMN_NAME
WHERE c.TABLE_SCHEMA = @SchemaName 
  AND c.TABLE_NAME = @TableName
ORDER BY c.ORDINAL_POSITION

OPEN column_cursor
FETCH NEXT FROM column_cursor INTO @ColumnName, @DataType, @IsNullable, @MaxLength, @IsPrimaryKey

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @PropertyOutput = ''
    
    -- Map SQL types to C# types
    SET @CSharpType = CASE @DataType
        WHEN 'bigint' THEN 'long'
        WHEN 'int' THEN 'int'
        WHEN 'smallint' THEN 'short'
        WHEN 'tinyint' THEN 'byte'
        WHEN 'bit' THEN 'bool'
        WHEN 'decimal' THEN 'decimal'
        WHEN 'numeric' THEN 'decimal'
        WHEN 'money' THEN 'decimal'
        WHEN 'smallmoney' THEN 'decimal'
        WHEN 'float' THEN 'double'
        WHEN 'real' THEN 'float'
        WHEN 'datetime' THEN 'DateTime'
        WHEN 'datetime2' THEN 'DateTime'
        WHEN 'smalldatetime' THEN 'DateTime'
        WHEN 'date' THEN 'DateTime'
        WHEN 'time' THEN 'TimeSpan'
        WHEN 'datetimeoffset' THEN 'DateTimeOffset'
        WHEN 'timestamp' THEN 'byte[]'
        WHEN 'binary' THEN 'byte[]'
        WHEN 'varbinary' THEN 'byte[]'
        WHEN 'image' THEN 'byte[]'
        WHEN 'uniqueidentifier' THEN 'Guid'
        WHEN 'varchar' THEN 'string'
        WHEN 'char' THEN 'string'
        WHEN 'nvarchar' THEN 'string'
        WHEN 'nchar' THEN 'string'
        WHEN 'text' THEN 'string'
        WHEN 'ntext' THEN 'string'
        ELSE 'object'
    END

    -- Add nullable modifier if needed
    IF @IsNullable = 'YES' AND @CSharpType NOT IN ('string', 'byte[]', 'object')
        SET @CSharpType = @CSharpType + '?'

    -- Build property output
    SET @PropertyOutput = '    '
    
    -- Key attribute
    IF @IsPrimaryKey = 1
        SET @PropertyOutput = @PropertyOutput + '[Key]' + CHAR(13) + CHAR(10) + '    '
    
    -- Required attribute
    IF @IsNullable = 'NO' AND @IsPrimaryKey = 0
        SET @PropertyOutput = @PropertyOutput + '[Required]' + CHAR(13) + CHAR(10) + '    '
    
    -- MaxLength attribute
    IF @MaxLength IS NOT NULL AND @CSharpType = 'string' AND @MaxLength > 0 AND @MaxLength < 8000
        SET @PropertyOutput = @PropertyOutput + '[MaxLength(' + CAST(@MaxLength AS NVARCHAR(10)) + ')]' + CHAR(13) + CHAR(10) + '    '
    
    -- Column attribute - EXACT column name
    SET @PropertyOutput = @PropertyOutput + '[Column("' + @ColumnName + '")]' + CHAR(13) + CHAR(10)
    
    -- Property declaration - EXACT column name as property name
    SET @PropertyOutput = @PropertyOutput + '    public ' + @CSharpType + ' ' + @ColumnName + ' { get; set; }'

    PRINT @PropertyOutput

    FETCH NEXT FROM column_cursor INTO @ColumnName, @DataType, @IsNullable, @MaxLength, @IsPrimaryKey
END

CLOSE column_cursor
DEALLOCATE column_cursor

PRINT '}'
PRINT ''
PRINT '// === GENERATION COMPLETE ==='
PRINT '// Total Properties: ' + CAST(@TotalColumns AS NVARCHAR(10))