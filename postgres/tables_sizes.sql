SELECT 
    t.schemaname || '.' || t.tablename AS table_name,
    pg_size_pretty(pg_total_relation_size('"' || t.schemaname || '"."' || t.tablename || '"')) AS total_size,
    pg_total_relation_size('"' || t.schemaname || '"."' || t.tablename || '"') AS size_in_bytes,
    s.n_live_tup AS estimated_row_count,
    CASE 
        WHEN s.n_live_tup > 0 
        THEN pg_size_pretty((pg_total_relation_size('"' || t.schemaname || '"."' || t.tablename || '"') / s.n_live_tup)::bigint)
        ELSE 'N/A'
    END AS avg_size_per_row,
    CASE 
        WHEN s.n_live_tup > 0 
        THEN (pg_total_relation_size('"' || t.schemaname || '"."' || t.tablename || '"') / s.n_live_tup)::bigint
        ELSE 0
    END AS bytes_per_row
FROM 
    pg_tables t
JOIN 
    pg_stat_user_tables s ON t.schemaname = s.schemaname AND t.tablename = s.relname
ORDER BY 
    pg_total_relation_size('"' || t.schemaname || '"."' || t.tablename || '"') DESC;
    