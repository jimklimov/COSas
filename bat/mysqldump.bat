@echo off

REM (C) 2010 Jim Klimov, JSC COS&HT
REM This script automates backup of a MySQL instance on Windows
REM Requires installed 7z archiver and MySQL components

rem set PATH="C:\Program Files\MySQL\MySQL Server 5.1\bin";%PATH%
set PATH=C:\Progra~1\MySQL\MySQLS~1.1\bin;C:\Progra~1\7-Zip;C:\Progra~2\7-Zip;%PATH%
set mydate=%date:~-4,4%%date:~-7,2%%date:~-10,2%
set mytime=%time:~0,2%%time:~+3,2%%time:~+6,2%
if "%mytime:~0,1%"==" " set mytime=0%mytime:~1,6%
set dumpdir=c:\backups\regular\mysql
set mysqluser=root
set mysqlpass=pa$$w0rd
set projname=DEPLOYMENTNAME

REM Limit CPU usage? Use a space as an empty value!
REM Example hex-mask affinity below sets 2 cores (#1 and 2).
rem set STARTLIMIT= 
set STARTLIMIT=start /LOW /B /WAIT /MIN /AFFINITY 0x3

mkdir %dumpdir% 2>nul
cd %dumpdir% || echo === NO DIR %dumpdir%, aborting! && exit 1

echo === TIMESTAMP: %mydate%_%mytime%

echo === DUMPING: alldb
set dumpbase=%dumpdir%\mydump_%projname%_alldb_%mydate%_%mytime%
%STARTLIMIT% mysqldump.exe --all-databases -u %mysqluser% -p%mysqlpass% >%dumpbase%.sql 2>%dumpbase%.log

set DB=mysql
echo === DUMPING: %DB%
set dumpbase=%dumpdir%\mydump_%projname%_%DB%_%mydate%_%mytime%
%STARTLIMIT% mysqldump.exe %DB% -u %mysqluser% -p%mysqlpass% >%dumpbase%.sql 2>%dumpbase%.log

set DB=mfc
echo === DUMPING: %DB%
set dumpbase=%dumpdir%\mydump_%projname%_%DB%_%mydate%_%mytime%
%STARTLIMIT% mysqldump.exe %DB% -u %mysqluser% -p%mysqlpass% >%dumpbase%.sql 2>%dumpbase%.log

set DB=magnolia_author
echo === DUMPING: %DB%
set dumpbase=%dumpdir%\mydump_%projname%_%DB%_%mydate%_%mytime%
%STARTLIMIT% mysqldump.exe %DB% -u %mysqluser% -p%mysqlpass% >%dumpbase%.sql 2>%dumpbase%.log

set DB=livecycle
echo === DUMPING: %DB%
set dumpbase=%dumpdir%\mydump_%projname%_%DB%_%mydate%_%mytime%
%STARTLIMIT% mysqldump.exe %DB% -u %mysqluser% -p%mysqlpass% >%dumpbase%.sql 2>%dumpbase%.log

set DB=alfresco
echo === DUMPING: %DB%
set dumpbase=%dumpdir%\mydump_%projname%_%DB%_%mydate%_%mytime%
%STARTLIMIT% mysqldump.exe %DB% -u %mysqluser% -p%mysqlpass% >%dumpbase%.sql 2>%dumpbase%.log

echo === Compressing results...
mkdir %dumpdir%\compressed 2>nul
cd %dumpdir%\compressed || echo === NO DIR %dumpdir%\compressed, aborting! && exit 1
%STARTLIMIT% 7z a -y mydump_%projname%_%mydate%_%mytime%.7z ..\mydump_%projname%_*_%mydate%_%mytime%.* && echo === Deleting SQL/LOG files... && del /f ..\mydump_%projname%_*_%mydate%_%mytime%.*

echo === DONE

