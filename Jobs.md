##Jobs en SQL Server

######Larissa Rivas Carvajal
 
 
###Jobs
 
Los jobs son una serie de tareas que se realizan secuencialmente, esto desde el servicio de Agente de SQL Server. 
Un job puede realizar/ejecutar una serie precisa de acciones, entre ellas; scripts, lineas de comandos, consultas, entre otros.
 

El fin, es lograr que estas acciones se ejecuten dentro de la base de datos de manera calendarizada. Ya que por lo general, son creadas para que desempeñen ciertas tareas mas de una vez a lo largo de un tiempo establecido. 

En muchos casos, y por diversas razones ocurren errores dentro del mismo que imposibilitan su correcto funcionamiento. 

Es por ello, que es de gran importancia llevar un control preciso del funcionamiento de estos.


####Objetivo

El objetivo del siguiente código es verificar el funcionamiento de los jobs, de manera que si alguno de ellos lleva en ejecución mas tiempo del esperado, sea 
notificado por correo electrónico a los encargados del mismo. 


En Sql Server existen tablas predeterminadas para el control de los jobs, tres de ellas, las cuales utilizaremos en nuestro codigo son: sysjobs, SysJobHistory, SysjobActivity. Las cuales se encuentran en la base de datos msdb.

#####SysJob
En este se encuentra toda la información de cada job, tal como el nombre, el ID, la descripción, el paso en el que debe inciiar, el servidor del que proviene, la fecha de creación, entre otros. 

#####SysJobHistory
En esta tabla se encuentra la informacion de las ejecuciones de los jobs. ID del job, ID del paso, nombre del paso, estatus, tiempo, día y tiempo de execución, nombre del servidor, entre otros.

#####SysjobActivity
En esta tabla, se encuentra la actividad y el estado de cada uno de los jobs. Tambien se encuentra información como; ID del job, fecha de inicio de la ejecucón,
paso y fecha de la ultima ejecución realizada.


#####Script

 Se trabajaran con tablas temporales asi que es importante asegurarse que estas no queden en la base de datos 
 una vez que se finaliza con el script.

La primera tabla temporal, almacenará el nombre de los jobs provenientes de la tabla sysjobs y el nombre del "paso", el tiempo en el que inició dicho paso y la fecha en la que concluyo; estas provenientes de la tabla sysjobshistory.
Hay que tomar en cuenta que las fechas en estas tablas se manejan en formatos diferentes, por lo que es recomendable convertirlo a un formato igual para toda la ejecucion. 


> ```sql										
>INSERT INTO #RunningJobs                    
>	SELECT j.Name, j.job_id, jh.Step_name,
>	CONVERT(DATETIME, RTRIM(jh.run_date)) + 
>		((jh.run_time/10000 * 3600) + ((jh.run_time%10000)/100*60) +
>		 (jh.run_time%10000)%100) / (23.999999*3600)
>	AS Start_DateTime,
>	CONVERT(DATETIME, RTRIM(jh.run_date)) + 
>	((jh.run_time/10000 * 3600) + ((jh.run_time%10000)/100*60) +
>	 (jh.run_time%10000)%100) / (86399.9964)+((jh.run_duration/10000 * 3600) +
>	 ((jh.run_duration%10000)/100*60) + (jh.run_duration%10000)%100) / (86399.9964 ) 
>	AS End_DateTime
>	FROM msdb..sysjobhistory jh, msdb..sysjobs j
>	WHERE jh.job_id=j.job_id  
>	ORDER BY run_date DESC, run_time DESC 
> ```


En la siguiente variable tabla se almacenaran todos los jobs de la tabla sysjobactivity que aun estan en ejecucion , esto se determina solicitando todos aquellos jobs cuya variable de la fecha de inicio no sea null, pero la fecha en la que finalizo si lo sea. 
 
> ```sql										  		
>INSERT INTO  @JobsRunning
>	(JobsRunID, sessionId, job_id, run_request_date, start_execution_date, stop_execution_date)
>	(SELECT ROW_NUMBER() OVER (ORDER BY  session_id), session_id, job_id, run_requested_date, start_execution_date, stop_execution_date 
>		FROM msdb.dbo.sysjobactivity 
>		WHERE start_execution_date IS NOT NULL AND stop_execution_date IS NULL)
> ```
										
 
Uno de los "pasos del job" mas importante seleccionado previamente en la tabla #RunningJobs es el '(Job Outcome)' este es el paso final de cada uno de los jobs una vez que concluye su ejecucion.
Es decir, este "paso" contiene exactamente la fecha y hora en la que inicio y finalizo la ejecucion del job. 
Si este "paso" no se encuentra en la tabla para un job en especifico significa que el job no ha finalizado.

Asi que por medio de un cursor se recorrera cada uno de los pasos para un job en especifico, determinando si  cuenta con ese ultimo  '(Job Outcome)', en caso de que no, se insertara en la tabla #IdsDate

 
> ```sql										 
>DECLARE SesssionIdJob CURSOR FOR
>	SELECT JobsRunID FROM @JobsRunning
>	
>OPEN SesssionIdJob
>
>FETCH NEXT FROM SesssionIdJob
>INTO @SesssionidJob
> 
>WHILE @@FETCH_STATUS = 0
>BEGIN
>	set @date = (select start_execution_date From @JobsRunning where JobsRunID= @SesssionidJob)
>	set @JobRunningId = (select job_id From @JobsRunning where JobsRunID= @SesssionidJob)
>	set @today =  getdate() 
>	Insert into #IdsDate  -- UNIFY ALL THE INFORMATION (NAME, START HOUR, AND HOURS THAT HAVE BEEN RUNNING)
>	 Select  top 1 Name, @date, (DATEDIFF (HOUR, @date, @today))  from #RunningJobs
>		WHERE step_name != '(Job Outcome)'
>		and Start_DateTime = @date
>		and Job_Id = @JobRunningId  
>	FETCH NEXT FROM SesssionIdJob INTO @SesssionidJob
>END
>
>CLOSE SesssionIdJob
>DEALLOCATE SesssionIdJob 
> ```
 
 

A fin de un ejemplo, para la ultima etapa del correo electronico, se notificaran unicamente los jobs que han estado corriendo desde las ultimas 8 horas.

Se creara una tabla en HTML con la informacion que se desea, en nuestro caso: nombre del Job, Fecha y Hora en la que inicio y Cantidad de horas que lleva corriendo

> ```sql										
>SET @tableHTML =  
>  N'<H3>Jobs Running</H3>' + 
>  N'<table border="1">' +
>  N'<tr><th>JobName</th>
>  <th>Last_Start_Time</th>
>  <th>HoursRunning</th>  '  +
>  CAST ((SELECT td= Name , '',
>  td= start_dateTime,'',
>  td = TimeRunning , ''
>   FROM #IdsDate WHERE TimeRunning > 8 FOR XML PATH('tr') , TYPE 
>	) AS NVARCHAR(MAX) )+ N'</table>' 
> ``` 
   
Se completa la informacion necesaria para el correo electronico, y se envia la misma por medio del comando 
EXEC msdb.dbo.sp_send_dbmail con el asunto del corre, destinatario, asunto, cuerpo del corero y formato del cuerpo.
                
> ```sql
>SELECT @EMailBody = '*** This are the Jobs that are running since last 8 hours. Please analyze and take any required action.***'
>SELECT @EMailBody = @EMailBody + @tableHTML
>		         
>		EXEC msdb.dbo.sp_send_dbmail  
>			@profile_name = @DBProfile,
>			@recipients = @ADDR,
>			@subject = @EmailSubject,
>			@Body = @EMailBody,
>			@body_format = 'html' 
>	END 
>```



De la siguiente manera el cuerpo del correo se veria de la siguiente forma:



	*** This are the Jobs that are running since last 8 hours. Please analyze and take any required action.***
	
            	|    JobName    |   Last_Start_Time   | HoursRunning  |
            	| ------------- |:-----------------:  | -------------:|
            	|    Job #1     | 2015-11-12 08:00:00 |      22       |
	            |    Job #2     | 2015-11-17 10:20:00 |      12       |
	


	