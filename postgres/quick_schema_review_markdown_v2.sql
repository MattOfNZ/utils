-- PostgreSQL Schema to Markdown Converter Script (v2)
-- Returns complete markdown documentation for tables and views in a single result
-- Supports ILIKE filtering on schema and table/view names via the params CTE
WITH params AS (
    SELECT
        '%'::text AS schema_filter,   -- ILIKE pattern for schema name (e.g. 'public', 'my_%')
        '%'::text AS name_filter      -- ILIKE pattern for table/view name (e.g. 'user%', '%order%')
),
schema_info AS (
    SELECT 
        t.table_schema,
        t.table_name, 
        c.column_name, 
        CASE 
            WHEN c.data_type = 'character varying' AND c.character_maximum_length IS NOT NULL THEN
                'varchar(' || c.character_maximum_length || ')'
            WHEN c.data_type = 'character' AND c.character_maximum_length IS NOT NULL THEN
                'char(' || c.character_maximum_length || ')'
            WHEN c.data_type = 'numeric' AND c.numeric_precision IS NOT NULL THEN
                'numeric(' || c.numeric_precision || 
                CASE WHEN c.numeric_scale IS NOT NULL AND c.numeric_scale > 0 THEN ',' || c.numeric_scale ELSE '' END || ')'
            ELSE c.data_type
        END as formatted_type,
        c.is_nullable,
        c.ordinal_position,
        pg_description.description AS table_description
    FROM 
        information_schema.tables t
    CROSS JOIN
        params p
    JOIN 
        information_schema.columns c 
        ON t.table_name = c.table_name AND t.table_schema = c.table_schema
    LEFT JOIN 
        pg_catalog.pg_namespace ns 
        ON ns.nspname = t.table_schema
    LEFT JOIN 
        pg_catalog.pg_class cls 
        ON cls.relnamespace = ns.oid AND cls.relname = t.table_name
    LEFT JOIN 
        pg_catalog.pg_description 
        ON pg_description.objoid = cls.oid AND pg_description.objsubid = 0
    WHERE 
        t.table_schema NOT IN ('pg_catalog', 'information_schema')
        AND t.table_type = 'BASE TABLE'
        AND t.table_schema ILIKE p.schema_filter
        AND t.table_name ILIKE p.name_filter
),
foreign_keys AS (
    SELECT
        tc.table_schema,
        tc.table_name,
        kcu.column_name,
        ccu.table_schema AS foreign_table_schema,
        ccu.table_name AS foreign_table_name,
        ccu.column_name AS foreign_column_name
    FROM 
        information_schema.table_constraints AS tc 
        JOIN information_schema.key_column_usage AS kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
          ON ccu.constraint_name = tc.constraint_name
          AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
),
table_headers AS (
    SELECT DISTINCT
        table_schema,
        table_name,
        table_description,
        '## ' || table_schema || '.' || table_name || ' (Table)' ||
        CASE 
            WHEN table_description IS NOT NULL THEN E'\n*' || table_description || '*'
            ELSE ''
        END || E'\n\n| Column | Type | Nullable |\n|--------|------|----------|\n' as header
    FROM schema_info
),
table_rows AS (
    SELECT 
        si.table_schema,
        si.table_name,
        string_agg(
            '| ' || si.column_name || ' | ' || si.formatted_type || ' | ' ||
            CASE WHEN si.is_nullable = 'YES' THEN 'Yes' ELSE 'No' END || ' |',
            E'\n' ORDER BY si.ordinal_position
        ) as rows
    FROM schema_info si
    GROUP BY si.table_schema, si.table_name
),
fk_summary AS (
    SELECT 
        table_schema,
        table_name,
        CASE 
            WHEN COUNT(*) > 0 THEN
                E'\n\n**Foreign Keys:**\n' ||
                string_agg(
                    '- `' || column_name || '` → `' || 
                    foreign_table_schema || '.' || foreign_table_name || 
                    '.' || foreign_column_name || '`',
                    E'\n'
                )
            ELSE ''
        END as fk_text
    FROM foreign_keys
    GROUP BY table_schema, table_name
),
table_markdown AS (
    SELECT 
        th.table_schema,
        th.table_name,
        th.header || tr.rows || COALESCE(fks.fk_text, '') || E'\n' as markdown
    FROM table_headers th
    JOIN table_rows tr ON th.table_schema = tr.table_schema AND th.table_name = tr.table_name  
    LEFT JOIN fk_summary fks ON th.table_schema = fks.table_schema AND th.table_name = fks.table_name
),
view_info AS (
    SELECT
        v.table_schema,
        v.table_name,
        c.column_name,
        CASE 
            WHEN c.data_type = 'character varying' AND c.character_maximum_length IS NOT NULL THEN
                'varchar(' || c.character_maximum_length || ')'
            WHEN c.data_type = 'character' AND c.character_maximum_length IS NOT NULL THEN
                'char(' || c.character_maximum_length || ')'
            WHEN c.data_type = 'numeric' AND c.numeric_precision IS NOT NULL THEN
                'numeric(' || c.numeric_precision || 
                CASE WHEN c.numeric_scale IS NOT NULL AND c.numeric_scale > 0 THEN ',' || c.numeric_scale ELSE '' END || ')'
            ELSE c.data_type
        END as formatted_type,
        c.is_nullable,
        c.ordinal_position,
        pg_catalog.pg_get_viewdef(cls.oid, true) AS view_definition,
        pg_description.description AS view_description
    FROM
        information_schema.views v
    CROSS JOIN
        params p
    JOIN
        information_schema.columns c
        ON v.table_name = c.table_name AND v.table_schema = c.table_schema
    JOIN
        pg_catalog.pg_namespace ns
        ON ns.nspname = v.table_schema
    JOIN
        pg_catalog.pg_class cls
        ON cls.relnamespace = ns.oid AND cls.relname = v.table_name
    LEFT JOIN
        pg_catalog.pg_description
        ON pg_description.objoid = cls.oid AND pg_description.objsubid = 0
    WHERE
        v.table_schema NOT IN ('pg_catalog', 'information_schema')
        AND v.table_schema ILIKE p.schema_filter
        AND v.table_name ILIKE p.name_filter
),
view_headers AS (
    SELECT DISTINCT
        table_schema,
        table_name,
        view_description,
        view_definition,
        '## ' || table_schema || '.' || table_name || ' (View)' ||
        CASE 
            WHEN view_description IS NOT NULL THEN E'\n*' || view_description || '*'
            ELSE ''
        END || E'\n\n| Column | Type | Nullable |\n|--------|------|----------|\n' as header
    FROM view_info
),
view_rows AS (
    SELECT
        vi.table_schema,
        vi.table_name,
        string_agg(
            '| ' || vi.column_name || ' | ' || vi.formatted_type || ' | ' ||
            CASE WHEN vi.is_nullable = 'YES' THEN 'Yes' ELSE 'No' END || ' |',
            E'\n' ORDER BY vi.ordinal_position
        ) as rows
    FROM view_info vi
    GROUP BY vi.table_schema, vi.table_name
),
view_markdown AS (
    SELECT
        vh.table_schema,
        vh.table_name,
        vh.header || vr.rows ||
        E'\n\n**View Definition:**\n```sql\n' || vh.view_definition || E'\n```\n' as markdown
    FROM view_headers vh
    JOIN view_rows vr ON vh.table_schema = vr.table_schema AND vh.table_name = vr.table_name
),
all_objects AS (
    SELECT table_schema, table_name, markdown FROM table_markdown
    UNION ALL
    SELECT table_schema, table_name, markdown FROM view_markdown
)
SELECT 
    '# Database Schema Documentation' || E'\n\n' ||
    string_agg(
        markdown,
        E'\n' 
        ORDER BY table_schema, table_name
    ) as complete_markdown
FROM all_objects;
