-- Results to Text!

-- SQL Server Schema to Markdown Converter Script
-- Returns complete markdown documentation in a single result
WITH schema_info AS (
    SELECT 
        t.TABLE_SCHEMA,
        t.TABLE_NAME, 
        c.COLUMN_NAME, 
        CASE 
            WHEN c.DATA_TYPE = 'varchar' AND c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN
                'varchar(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            WHEN c.DATA_TYPE = 'nvarchar' AND c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN
                'nvarchar(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            WHEN c.DATA_TYPE = 'char' AND c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN
                'char(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            WHEN c.DATA_TYPE = 'nchar' AND c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN
                'nchar(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            WHEN c.DATA_TYPE = 'decimal' AND c.NUMERIC_PRECISION IS NOT NULL THEN
                'decimal(' + CAST(c.NUMERIC_PRECISION AS VARCHAR(10)) + 
                CASE WHEN c.NUMERIC_SCALE IS NOT NULL AND c.NUMERIC_SCALE > 0 
                     THEN ',' + CAST(c.NUMERIC_SCALE AS VARCHAR(10)) 
                     ELSE '' END + ')'
            WHEN c.DATA_TYPE = 'numeric' AND c.NUMERIC_PRECISION IS NOT NULL THEN
                'numeric(' + CAST(c.NUMERIC_PRECISION AS VARCHAR(10)) + 
                CASE WHEN c.NUMERIC_SCALE IS NOT NULL AND c.NUMERIC_SCALE > 0 
                     THEN ',' + CAST(c.NUMERIC_SCALE AS VARCHAR(10)) 
                     ELSE '' END + ')'
            WHEN c.DATA_TYPE = 'float' AND c.NUMERIC_PRECISION IS NOT NULL THEN
                'float(' + CAST(c.NUMERIC_PRECISION AS VARCHAR(10)) + ')'
            ELSE c.DATA_TYPE
        END as formatted_type,
        c.IS_NULLABLE,
        c.ORDINAL_POSITION,
        CAST(ep.value AS NVARCHAR(MAX)) AS table_description
    FROM 
        INFORMATION_SCHEMA.TABLES t
    JOIN 
        INFORMATION_SCHEMA.COLUMNS c 
        ON t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_SCHEMA = c.TABLE_SCHEMA
    LEFT JOIN 
        sys.tables st ON st.name = t.TABLE_NAME
    LEFT JOIN 
        sys.schemas ss ON ss.schema_id = st.schema_id AND ss.name = t.TABLE_SCHEMA
    LEFT JOIN 
        sys.extended_properties ep 
        ON ep.major_id = st.object_id 
        AND ep.minor_id = 0 
        AND ep.name = 'MS_Description'
    WHERE 
        t.TABLE_TYPE = 'BASE TABLE'
        AND t.TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
),
foreign_keys AS (
    SELECT
        OBJECT_SCHEMA_NAME(fk.parent_object_id) AS table_schema,
        OBJECT_NAME(fk.parent_object_id) AS table_name,
        COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS column_name,
        OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS foreign_table_schema,
        OBJECT_NAME(fk.referenced_object_id) AS foreign_table_name,
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS foreign_column_name
    FROM 
        sys.foreign_keys fk
    INNER JOIN 
        sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
),
table_headers AS (
    SELECT DISTINCT
        table_schema,
        table_name,
        table_description,
        '## ' + table_schema + '.' + table_name + 
        CASE 
            WHEN table_description IS NOT NULL THEN CHAR(10) + '*' + table_description + '*'
            ELSE ''
        END + CHAR(10) + CHAR(10) + '| Column | Type | Nullable |' + CHAR(10) + '|--------|------|----------|' + CHAR(10) as header
    FROM schema_info
),
table_rows AS (
    SELECT 
        si.table_schema,
        si.table_name,
        STRING_AGG(
            '| ' + si.column_name + ' | ' + si.formatted_type + ' | ' +
            CASE WHEN si.is_nullable = 'YES' THEN 'Yes' ELSE 'No' END + ' |',
            CHAR(10)
        ) WITHIN GROUP (ORDER BY si.ordinal_position) as rows
    FROM schema_info si
    GROUP BY si.table_schema, si.table_name
),
fk_summary AS (
    SELECT 
        table_schema,
        table_name,
        CASE 
            WHEN COUNT(*) > 0 THEN
                CHAR(10) + CHAR(10) + '**Foreign Keys:**' + CHAR(10) +
                STRING_AGG(
                    '- `' + column_name + '` → `' + 
                    foreign_table_schema + '.' + foreign_table_name + 
                    '.' + foreign_column_name + '`',
                    CHAR(10)
                )
            ELSE ''
        END as fk_text
    FROM foreign_keys
    GROUP BY table_schema, table_name
)
SELECT 
    '# Database Schema Documentation' + CHAR(10) + CHAR(10) +
    STRING_AGG(
        th.header + tr.rows + ISNULL(fks.fk_text, '') + CHAR(10),
        CHAR(10)
    ) WITHIN GROUP (ORDER BY th.table_schema, th.table_name) as complete_markdown
FROM table_headers th
JOIN table_rows tr ON th.table_schema = tr.table_schema AND th.table_name = tr.table_name  
LEFT JOIN fk_summary fks ON th.table_schema = fks.table_schema AND th.table_name = fks.table_name;