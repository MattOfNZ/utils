SELECT 
  table_schema || '.' || table_name AS table_key,
  
  'SELECT' || E'\n    ' || 
  string_agg(table_name || '.' || column_name, ',' || E'\n    ' ORDER BY ordinal_position) || 
  E'\nFROM ' || table_schema || '.' || table_name || ';' AS select_statement,
  
  'INSERT INTO ' || table_schema || '.' || table_name || ' (' || E'\n    ' ||
  string_agg(column_name, ',' || E'\n    ' ORDER BY ordinal_position) ||
  E'\n) VALUES (' || E'\n    ' ||
  string_agg('$' || ordinal_position, ',' || E'\n    ' ORDER BY ordinal_position) ||
  E'\n);' AS insert_statement,
  
  'UPDATE ' || table_schema || '.' || table_name || ' SET' || E'\n    ' ||
  string_agg(column_name || ' = $' || ordinal_position, ',' || E'\n    ' ORDER BY ordinal_position) ||
  E'\nWHERE id = $' || (max(ordinal_position) + 1) || ';' AS update_statement
  
FROM information_schema.columns 
WHERE table_schema = 'yourschema' 
  AND table_name = 'yourtable'
GROUP BY table_schema, table_name;