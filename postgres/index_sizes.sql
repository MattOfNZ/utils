SELECT
    n.nspname AS schema_name,
    t.relname AS table_name,
    i.relname AS index_name,
    pg_size_pretty(pg_relation_size(i.oid)) AS index_size,
    pg_relation_size(i.oid) AS index_size_bytes
FROM
    pg_index x
    JOIN pg_class i ON i.oid = x.indexrelid
    JOIN pg_class t ON t.oid = x.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE
    t.relkind = 'r'
ORDER BY
    pg_relation_size(i.oid) DESC