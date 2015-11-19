
IF OBJECT_ID('tempdb.dbo.#RunningJobs') IS NOT NULL
      DROP TABLE #RunningJobs
      
IF OBJECT_ID('tempdb.dbo.#IdsDate') IS NOT NULL
      DROP TABLE #IdsDate


CREATE TABLE #RunningJobs (   
	Name SYSNAME,
	Job_Id UNIQUEIDENTIFIER,
	Step_name SYSNAME,
	Start_DateTime DATETIME,
	End_DateTime DATETIME )     
      

										-- RETURN ALL THE JOB HISTORY TABLE WITH THE DATE AND TIME IN A DATETIME FORM
INSERT INTO #RunningJobs                    
	SELECT j.Name, j.job_id, jh.Step_name,
	CONVERT(DATETIME, RTRIM(jh.run_date)) + 
		((jh.run_time/10000 * 3600) + ((jh.run_time%10000)/100*60) +
		 (jh.run_time%10000)%100) / (23.999999*3600)
	AS Start_DateTime,
	CONVERT(DATETIME, RTRIM(jh.run_date)) + 
	((jh.run_time/10000 * 3600) + ((jh.run_time%10000)/100*60) +
	 (jh.run_time%10000)%100) / (86399.9964)+((jh.run_duration/10000 * 3600) +
	 ((jh.run_duration%10000)/100*60) + (jh.run_duration%10000)%100) / (86399.9964 ) 
	AS End_DateTime
	FROM msdb..sysjobhistory jh, msdb..sysjobs j
	WHERE jh.job_id=j.job_id  
	ORDER BY run_date DESC, run_time DESC 
	
select * from #RunningJobs

----------------------------------------------------------------------------------------------------
									--RETURN THE JOBS THAT ARE RUNNING FROM THE SYSJOBACTIVITY TABLE
DECLARE  @JobsRunning TABLE
	(JobsRunID int, 
	 sessionId int, 
	job_id UNIQUEIDENTIFIER, 
	run_request_date DATETIME, 
	start_execution_date DATETIME,
	stop_execution_date DATETIME)  

			
INSERT INTO  @JobsRunning
	(JobsRunID, sessionId, job_id, run_request_date, start_execution_date, stop_execution_date)
	(SELECT ROW_NUMBER() OVER (ORDER BY  session_id), session_id, job_id, run_requested_date, start_execution_date, stop_execution_date 
		FROM msdb.dbo.sysjobactivity 
		WHERE start_execution_date IS NOT NULL AND stop_execution_date IS NULL)

select * from  @JobsRunning

---------------------------------------------------------------------------------------------

CREATE TABLE  #IdsDate  ( Name SYSNAME, start_dateTime DATETIME, TimeRunning INT)

/***********/
 
DECLARE @date DATETIME
DECLARE @JobRunningId SYSNAME
DECLARE @today DATETIME

/***********/
DECLARE @SesssionidJob INT
DECLARE SesssionIdJob CURSOR FOR
	SELECT JobsRunID FROM @JobsRunning
	
OPEN SesssionIdJob

FETCH NEXT FROM SesssionIdJob
INTO @SesssionidJob
 
WHILE @@FETCH_STATUS = 0
BEGIN
	set @date = (select start_execution_date From @JobsRunning where JobsRunID= @SesssionidJob)
	set @JobRunningId = (select job_id From @JobsRunning where JobsRunID= @SesssionidJob)
	set @today =  getdate() 
	Insert into #IdsDate  -- UNIFY ALL THE INFORMATION (NAME, START HOUR, AND HOURS THAT HAVE BEEN RUNNING)
	 Select  top 1 Name, @date, (DATEDIFF (HOUR, @date, @today))  
	 from #RunningJobs
		WHERE step_name != '(Job Outcome)'
		and Start_DateTime = @date
		and Job_Id = @JobRunningId  
	FETCH NEXT FROM SesssionIdJob INTO @SesssionidJob
END

CLOSE SesssionIdJob
DEALLOCATE SesssionIdJob 

select * from #IdsDate

-----------------------------------------------------------------------------------------------------------------
											/* --------------- Email -----------------------------*/
DECLARE @EmailSubject VARCHAR(200)
DECLARE @EMailBody NVARCHAR(Max)
DECLARE @DBProfile VARCHAR(500)
DECLARE @ADDR VARCHAR(1000)

DECLARE @tableHTML  NVARCHAR(max) 
DECLARE @tableHTMLServer  NVARCHAR(max)

										--  MAKE A TABLE FOR THE EMAIL ONLY WITH THE JOBS THAT HAVE BEEN RUNNING FOR MORE THAN 8 HOURS (480 MINUTES)
SET @tableHTML =  
  N'<H3>Jobs Running</H3>' + 
  N'<table border="1">' +
  N'<tr><th>JobName</th>
  <th>Last_Start_Time</th>
  <th>HoursRunning</th>  '  +
  CAST ((SELECT td= Name , '',
  td= start_dateTime,'',
  td = TimeRunning , ''
   FROM #IdsDate WHERE TimeRunning > 8 FOR XML PATH('tr') , TYPE 
	) AS NVARCHAR(MAX) )+ N'</table>' 
  
   
SELECT @DBProfile = 'SQL Notification' 	 
SELECT @ADDR ='address@gmail.com'
                

SET @EmailSubject = @@SERVERNAME + ' : ' + ' : Jobs Running ' 

	IF @tableHTML <> '' -- IF THEY ARE JOBS RUNNING, ATTACHED BOTH TABLES TO THE MAIL
	BEGIN 
		SELECT @EMailBody = '*** This are the Jobs that are running since last 8 hours ' 
		SELECT @EMailBody = @EMailBody + '. Please analyze and take any required action.***'
        SELECT @EMailBody = @EMailBody + @tableHTML
			
		SELECT @DBProfile AS BDPROFILE
		SELECT @ADDR AS EMAILTO
		SELECT @EmailSubject AS EMAILSUBJECT
		SELECT @EMailBody AS BODY
		         
		EXEC msdb.dbo.sp_send_dbmail  
			@profile_name = @DBProfile,
			@recipients = @ADDR,
			@subject = @EmailSubject,
			@Body = @EMailBody,
			@body_format = 'html' 
	END 

IF OBJECT_ID('tempdb.dbo.#RunningJobs') IS NOT NULL
      DROP TABLE #RunningJobs
      
IF OBJECT_ID('tempdb.dbo.#IdsDate') IS NOT NULL
      DROP TABLE #IdsDate
