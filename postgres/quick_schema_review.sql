SELECT 
    t.table_schema,
    t.table_name, 
    c.column_name, 
    c.data_type, 
    c.column_default,
    c.is_nullable,
    c.character_maximum_length,
    pg_description.description AS table_description
FROM 
    information_schema.tables t
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
ORDER BY 
    t.table_schema,
    t.table_name, 
    c.ordinal_position;
