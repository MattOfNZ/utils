SET NOCOUNT ON;

-- Modern EF Core Class Generator - Entire Schema Support
-- Compatible with SQL Server 2012+ (uses FOR XML PATH instead of STRING_AGG)
-- Generates classes for all tables in a schema or specific table
-- Usage: Set @SchemaName and optionally @TableName (leave NULL for entire schema)

DECLARE @SchemaName NVARCHAR(128) = 'dbo';        -- Target schema name
DECLARE @TableName NVARCHAR(128) = NULL;          -- NULL = entire schema, or specify table name
DECLARE @TargetNamespace NVARCHAR(256) = 'MyApp.Data.Models'; -- Full target namespace
DECLARE @ClassPrefix NVARCHAR(128) = '';          -- Prefix for C# class names (e.g., 'Entity' -> 'EntityUser')
DECLARE @IncludeJsonAttributes BIT = 0;           -- Include System.Text.Json attributes
DECLARE @UseRecords BIT = 0;                      -- Generate as records instead of classes
DECLARE @MakeEverythingNullable BIT = 1;          -- Make all properties nullable (useful for data migration)

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
    -- Single table mode
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
                   WHERE TABLE_SCHEMA = @SchemaName AND TABLE_NAME = @TableName)
    BEGIN
        PRINT 'Table [' + @SchemaName + '].[' + @TableName + '] not found!';
        RETURN;
    END
    
    INSERT INTO @TablesToProcess VALUES (@TableName, @SchemaName);
END
ELSE
BEGIN
    -- Entire schema mode
    INSERT INTO @TablesToProcess (TableName, TableSchema)
    SELECT TABLE_NAME, TABLE_SCHEMA
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = @SchemaName 
      AND TABLE_TYPE = 'BASE TABLE'
    ORDER BY TABLE_NAME;
END

-- Print header information
DECLARE @TableCount INT = (SELECT COUNT(*) FROM @TablesToProcess);
PRINT '=== MODERN EF CORE CLASS GENERATOR ===';
PRINT 'Schema: ' + @SchemaName;
PRINT 'Tables to process: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT 'Generation mode: ' + CASE WHEN @UseRecords = 1 THEN 'Records' ELSE 'Classes' END;
PRINT 'Nullable mode: ' + CASE WHEN @MakeEverythingNullable = 1 THEN 'All Nullable' ELSE 'Schema Defined' END;
PRINT '';

-- Generate using statements
PRINT '// Required using statements:';
PRINT 'using System.ComponentModel.DataAnnotations;';
PRINT 'using System.ComponentModel.DataAnnotations.Schema;';
PRINT 'using Microsoft.EntityFrameworkCore;';
IF @IncludeJsonAttributes = 1
    PRINT 'using System.Text.Json.Serialization;';
PRINT '';
PRINT 'namespace ' + @TargetNamespace + ';';
PRINT '';

-- Main table processing cursor (optimized)
DECLARE @CurrentTable NVARCHAR(128);
DECLARE @CurrentSchema NVARCHAR(128);

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, TableSchema FROM @TablesToProcess ORDER BY TableName;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @CurrentTable, @CurrentSchema;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Print table header
    DECLARE @ClassName NVARCHAR(256) = @ClassPrefix + @CurrentTable;
    PRINT '[Table("' + @CurrentTable + '", Schema = "' + @CurrentSchema + '")]';
    PRINT 'public ' + CASE WHEN @UseRecords = 1 THEN 'record' ELSE 'class' END + ' ' + @ClassName;
    PRINT '{';

    -- Get column information for current table
    DECLARE @ColumnOutput NVARCHAR(MAX);
    
    SELECT @ColumnOutput = STUFF((
        SELECT CHAR(13) + CHAR(10) + 
               -- Attributes
               CASE WHEN pk.COLUMN_NAME IS NOT NULL THEN '    [Key]' + CHAR(13) + CHAR(10) ELSE '' END +
               CASE WHEN id.COLUMN_NAME IS NOT NULL THEN '    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]' + CHAR(13) + CHAR(10) ELSE '' END +
               CASE WHEN @MakeEverythingNullable = 0 AND c.IS_NULLABLE = 'NO' AND pk.COLUMN_NAME IS NULL AND 
                         CASE 
                             WHEN c.DATA_TYPE IN ('varchar', 'char', 'nvarchar', 'nchar', 'text', 'ntext', 'xml') THEN 'string'
                             ELSE 'other'
                         END = 'string'
                    THEN '    [Required]' + CHAR(13) + CHAR(10) ELSE '' END +
               CASE WHEN c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL AND 
                         c.DATA_TYPE IN ('varchar', 'char', 'nvarchar', 'nchar') 
                         AND c.CHARACTER_MAXIMUM_LENGTH > 0 AND c.CHARACTER_MAXIMUM_LENGTH < 8000
                    THEN '    [MaxLength(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS NVARCHAR(10)) + ')]' + CHAR(13) + CHAR(10) 
                    ELSE '' END +
               CASE WHEN @IncludeJsonAttributes = 1 
                    THEN '    [JsonPropertyName("' + LOWER(c.COLUMN_NAME) + '")]' + CHAR(13) + CHAR(10) 
                    ELSE '' END +
               '    [Column("' + c.COLUMN_NAME + '")]' + CHAR(13) + CHAR(10) +
               -- Property declaration with modern C# type mapping
               '    public ' + 
               CASE 
                   WHEN (@MakeEverythingNullable = 1 OR c.IS_NULLABLE = 'YES') AND 
                        CASE 
                            WHEN c.DATA_TYPE IN ('bigint') THEN 'long'
                            WHEN c.DATA_TYPE IN ('int') THEN 'int'
                            WHEN c.DATA_TYPE IN ('smallint') THEN 'short'
                            WHEN c.DATA_TYPE IN ('tinyint') THEN 'byte'
                            WHEN c.DATA_TYPE IN ('bit') THEN 'bool'
                            WHEN c.DATA_TYPE IN ('decimal', 'numeric', 'money', 'smallmoney') THEN 'decimal'
                            WHEN c.DATA_TYPE IN ('float') THEN 'double'
                            WHEN c.DATA_TYPE IN ('real') THEN 'float'
                            WHEN c.DATA_TYPE IN ('datetime', 'datetime2', 'smalldatetime', 'date') THEN 'DateTime'
                            WHEN c.DATA_TYPE IN ('time') THEN 'TimeSpan'
                            WHEN c.DATA_TYPE IN ('datetimeoffset') THEN 'DateTimeOffset'
                            WHEN c.DATA_TYPE IN ('uniqueidentifier') THEN 'Guid'
                            ELSE 'other'
                        END NOT IN ('string', 'byte[]', 'object', 'other')
                   THEN 
                       CASE 
                           WHEN c.DATA_TYPE IN ('bigint') THEN 'long?'
                           WHEN c.DATA_TYPE IN ('int') THEN 'int?'
                           WHEN c.DATA_TYPE IN ('smallint') THEN 'short?'
                           WHEN c.DATA_TYPE IN ('tinyint') THEN 'byte?'
                           WHEN c.DATA_TYPE IN ('bit') THEN 'bool?'
                           WHEN c.DATA_TYPE IN ('decimal', 'numeric', 'money', 'smallmoney') THEN 'decimal?'
                           WHEN c.DATA_TYPE IN ('float') THEN 'double?'
                           WHEN c.DATA_TYPE IN ('real') THEN 'float?'
                           WHEN c.DATA_TYPE IN ('datetime', 'datetime2', 'smalldatetime', 'date') THEN 'DateTime?'
                           WHEN c.DATA_TYPE IN ('time') THEN 'TimeSpan?'
                           WHEN c.DATA_TYPE IN ('datetimeoffset') THEN 'DateTimeOffset?'
                           WHEN c.DATA_TYPE IN ('uniqueidentifier') THEN 'Guid?'
                           ELSE 'object'
                       END
                   ELSE
                       CASE 
                           WHEN c.DATA_TYPE IN ('bigint') THEN 'long'
                           WHEN c.DATA_TYPE IN ('int') THEN 'int'
                           WHEN c.DATA_TYPE IN ('smallint') THEN 'short'
                           WHEN c.DATA_TYPE IN ('tinyint') THEN 'byte'
                           WHEN c.DATA_TYPE IN ('bit') THEN 'bool'
                           WHEN c.DATA_TYPE IN ('decimal', 'numeric', 'money', 'smallmoney') THEN 'decimal'
                           WHEN c.DATA_TYPE IN ('float') THEN 'double'
                           WHEN c.DATA_TYPE IN ('real') THEN 'float'
                           WHEN c.DATA_TYPE IN ('datetime', 'datetime2', 'smalldatetime', 'date') THEN 'DateTime'
                           WHEN c.DATA_TYPE IN ('time') THEN 'TimeSpan'
                           WHEN c.DATA_TYPE IN ('datetimeoffset') THEN 'DateTimeOffset'
                           WHEN c.DATA_TYPE IN ('timestamp', 'binary', 'varbinary', 'image') THEN 'byte[]'
                           WHEN c.DATA_TYPE IN ('uniqueidentifier') THEN 'Guid'
                           WHEN c.DATA_TYPE IN ('varchar', 'char', 'nvarchar', 'nchar', 'text', 'ntext', 'xml') THEN 
                               CASE WHEN @MakeEverythingNullable = 1 THEN 'string?' ELSE 'string' END
                           WHEN c.DATA_TYPE IN ('geography', 'geometry', 'hierarchyid') THEN 'string'
                           WHEN c.DATA_TYPE IN ('sql_variant') THEN 'object'
                           ELSE 'object'
                       END
               END + ' ' + c.COLUMN_NAME + ' { get; set; }'
        FROM INFORMATION_SCHEMA.COLUMNS c
        LEFT JOIN (
            -- Primary Keys
            SELECT ku.TABLE_SCHEMA, ku.TABLE_NAME, ku.COLUMN_NAME
            FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
            INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku 
                ON tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
                AND tc.TABLE_SCHEMA = ku.TABLE_SCHEMA
            WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
        ) pk ON c.TABLE_SCHEMA = pk.TABLE_SCHEMA 
            AND c.TABLE_NAME = pk.TABLE_NAME 
            AND c.COLUMN_NAME = pk.COLUMN_NAME
        LEFT JOIN (
            -- Identity columns (SQL Server 2012+ compatible)
            SELECT 
                SCHEMA_NAME(o.schema_id) AS TABLE_SCHEMA,
                OBJECT_NAME(c.object_id) AS TABLE_NAME,
                c.name AS COLUMN_NAME
            FROM sys.columns c
            INNER JOIN sys.objects o ON c.object_id = o.object_id
            WHERE c.is_identity = 1
        ) id ON c.TABLE_SCHEMA = id.TABLE_SCHEMA 
            AND c.TABLE_NAME = id.TABLE_NAME 
            AND c.COLUMN_NAME = id.COLUMN_NAME
        WHERE c.TABLE_SCHEMA = @CurrentSchema 
          AND c.TABLE_NAME = @CurrentTable
        ORDER BY c.ORDINAL_POSITION
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '');

    -- Print the properties
    PRINT @ColumnOutput;
    
    -- Close class
    PRINT '}';
    PRINT '';

    FETCH NEXT FROM table_cursor INTO @CurrentTable, @CurrentSchema;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

-- Print summary
PRINT '=== GENERATION SUMMARY ===';
DECLARE @SummaryOutput NVARCHAR(MAX) = '';

SELECT @SummaryOutput = @SummaryOutput + 
    '// Table: ' + t.TableName + ' - Properties: ' + CAST(COUNT(c.COLUMN_NAME) AS NVARCHAR(10)) + CHAR(13) + CHAR(10)
FROM @TablesToProcess t
INNER JOIN INFORMATION_SCHEMA.COLUMNS c 
    ON c.TABLE_SCHEMA = t.TableSchema AND c.TABLE_NAME = t.TableName
GROUP BY t.TableName, t.TableSchema
ORDER BY t.TableName;

PRINT @SummaryOutput;
PRINT '// Total tables processed: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT '// Generation complete!';
PRINT '';
PRINT '// === NULLABLE MODE NOTES ===';
PRINT '// When MakeEverythingNullable = 1:';
PRINT '// - All value types become nullable (int -> int?, DateTime -> DateTime?, etc.)';
PRINT '// - String types become nullable reference types (string -> string?)';
PRINT '// - [Required] attributes are suppressed for all properties except primary keys';
PRINT '// - Useful for data migration scenarios with inconsistent source data';