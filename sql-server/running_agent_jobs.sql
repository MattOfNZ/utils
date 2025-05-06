SELECT 
    j.name AS job_name,
    ja.start_execution_date,
    DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS minutes_running
FROM 
    msdb.dbo.sysjobs j
JOIN 
    msdb.dbo.sysjobactivity ja ON ja.job_id = j.job_id
JOIN 
    (SELECT 
        job_id, 
        MAX(session_id) AS session_id
     FROM 
        msdb.dbo.sysjobactivity
     GROUP BY 
        job_id) AS last_session 
    ON ja.job_id = last_session.job_id AND ja.session_id = last_session.session_id
WHERE 
    ja.start_execution_date IS NOT NULL
    AND ja.stop_execution_date IS NULL
ORDER BY 
    ja.start_execution_date;


EXEC msdb.dbo.sp_help_job @execution_status = 1;