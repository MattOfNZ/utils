-- ============================================================================
-- uuid_ferret.sql
-- ----------------------------------------------------------------------------
-- Purpose:
--   Hunt down every plausible reference to one or more UUID values across a
--   Postgres database (PK columns, FK columns, and optionally other uuid /
--   uuid[] columns), scoped by schema/table name patterns.
--
-- How it works (two-step process):
--   STEP 1 (this file, "generator" query):
--     Pure SQL, driven entirely by two CTEs:
--       - `target`   : the UUID(s) you're hunting for
--       - `settings` : the search scope/behaviour
--     It walks pg_catalog to find every uuid / uuid[] column matching your
--     settings, builds one SELECT statement per matching column, and returns
--     them collapsed via string_agg into a single combined `full_search_sql`
--     value.
--
--     The generated SQL is deliberately lean:
--       - a `p` CTE holds the target UUID array once, referenced by every branch
--       - a single typed header row (''::text AS schema_name, ...) establishes
--         column names/types for the whole UNION ALL, so every other branch is
--         just three bare literals + a FROM/WHERE/LIMIT -- no repeated AS
--         aliases or casts per branch
--       - the header row is filtered out of the final result with
--         WHERE schema_name <> ''
--
--   STEP 2 (separate execution, "hunt" query):
--     Take the generated SQL text returned by Step 1 and execute it yourself.
--     Postgres has no portable way to UNION an unknown number of tables inside
--     one static statement, so generation and execution are two round-trips.
--
-- Generated SQL output columns: schema_name, table_name, column_name
--   (no pk/fk flag, no row data -- just the location of each match).
--
-- Requirements / notes:
--   - You need SELECT privilege on any table the generator finds, or those
--     rows will simply error out (or be skipped, depending how you execute).
--   - Columns matched this way are read via full/partial table scans unless
--     they're indexed (PKs and most FKs usually are). Large unindexed OTHER
--     columns can be slow -- keep search_other_uuid_columns = false unless
--     you need it.
--   - The UUID array is baked into the generated SQL's `p` CTE at generation
--     time. Re-run Step 1 if your target list changes.
-- ============================================================================


-- ============================================================================
-- STEP 1 -- Generator: produces one combined, ready-to-run SQL statement
-- ============================================================================
WITH target AS MATERIALIZED (
    -- >>> EDIT ME: the UUID(s) you're hunting for <<<
    SELECT ARRAY[
        '00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111111'
    ]::uuid[] AS target_uuids
),

settings AS MATERIALIZED (
    SELECT
        ARRAY['%']::text[]              AS schema_patterns,        -- ILIKE ANY(), supports >1 pattern
        ARRAY['%']::text[]              AS table_patterns,         -- ILIKE ANY(), supports >1 pattern
        ARRAY['pg_catalog','information_schema','pg_toast']::text[] AS exclude_schemas,
        ARRAY[]::text[]                 AS exclude_tables,         -- bare table names to skip
        true                             AS search_pk_columns,     -- hunt in primary key columns
        true                             AS search_fk_columns,     -- hunt in foreign key columns
        false                            AS search_other_uuid_columns, -- hunt in non-key uuid columns too
        true                             AS search_uuid_array_columns, -- also check uuid[] columns (&& overlap)
        500                              AS max_results_per_table  -- LIMIT per generated branch
),

uuid_columns AS (
    SELECT
        n.nspname   AS schema_name,
        c.relname   AS table_name,
        a.attname   AS column_name,
        a.attnum,
        c.oid       AS table_oid,
        (a.atttypid = 'uuid[]'::regtype) AS is_uuid_array
    FROM pg_attribute a
    JOIN pg_class     c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN settings s
    WHERE a.attnum > 0
      AND NOT a.attisdropped
      AND c.relkind IN ('r','p')                                   -- ordinary + partitioned tables
      AND (a.atttypid = 'uuid'::regtype OR a.atttypid = 'uuid[]'::regtype)
      AND (a.atttypid <> 'uuid[]'::regtype OR s.search_uuid_array_columns)
      AND n.nspname ILIKE ANY (s.schema_patterns)
      AND NOT (n.nspname = ANY (s.exclude_schemas))
      AND c.relname ILIKE ANY (s.table_patterns)
      AND NOT (c.relname = ANY (s.exclude_tables))
),

key_flags AS (
    SELECT
        con.conrelid AS table_oid,
        unnest(con.conkey) AS attnum,
        con.contype
    FROM pg_constraint con
    WHERE con.contype IN ('p','f')
),

classified_columns AS (
    SELECT
        uc.schema_name,
        uc.table_name,
        uc.column_name,
        uc.table_oid,
        uc.is_uuid_array,
        bool_or(kf.contype = 'p') AS is_pk,
        bool_or(kf.contype = 'f') AS is_fk
    FROM uuid_columns uc
    LEFT JOIN key_flags kf
      ON kf.table_oid = uc.table_oid AND kf.attnum = uc.attnum
    GROUP BY uc.schema_name, uc.table_name, uc.column_name, uc.table_oid, uc.is_uuid_array
),

filtered_columns AS (
    SELECT cc.*
    FROM classified_columns cc
    CROSS JOIN settings s
    WHERE (s.search_pk_columns AND cc.is_pk)
       OR (s.search_fk_columns AND cc.is_fk)
       OR (s.search_other_uuid_columns AND NOT cc.is_pk AND NOT cc.is_fk)
),

generated_branches AS (
    SELECT
        fc.schema_name,
        fc.table_name,
        fc.column_name,
        format(
            '(SELECT %L, %L, %L FROM %I.%I AS t, p WHERE t.%I %s (p.target_uuids) LIMIT %s)',
            fc.schema_name,
            fc.table_name,
            fc.column_name,
            fc.schema_name,
            fc.table_name,
            fc.column_name,
            CASE WHEN fc.is_uuid_array THEN '&&' ELSE '= ANY' END,
            s.max_results_per_table
        ) AS branch_sql
    FROM filtered_columns fc
    CROSS JOIN settings s
),

params_header AS (
    SELECT format(
        E'WITH p AS (\n    SELECT ARRAY[%s]::uuid[] AS target_uuids\n)',
        (SELECT string_agg(quote_literal(u::text), ',') FROM unnest(t.target_uuids) AS u)
    ) AS header_sql
    FROM target t
)

SELECT
    format(
        E'%s\nSELECT schema_name, table_name, column_name FROM (\n    %s\n    UNION ALL\n%s\n) ferret\nWHERE schema_name <> %L;',
        (SELECT header_sql FROM params_header),
        $q$SELECT ''::text AS schema_name, ''::text AS table_name, ''::text AS column_name$q$,
        string_agg(branch_sql, E'\nUNION ALL\n' ORDER BY schema_name, table_name, column_name),
        ''
    ) AS full_search_sql,
    count(*) AS tables_matched
FROM generated_branches;


-- ============================================================================
-- STEP 2 -- Running the generated SQL
-- ============================================================================
-- Take the `full_search_sql` text value returned above and execute it
-- yourself as a new statement.
-- ============================================================================