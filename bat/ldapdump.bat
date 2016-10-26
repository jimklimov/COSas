@echo off

REM (C) 2010 Jim Klimov, JSC COS&HT
REM This script automates backup of Sun/Oracle DSEE instance on Windows
REM Requires installed 7z archiver and DSEE components

set PATH=C:\DSEE\dsee6\bin;C:\DSEE\ds6\bin;C:\DSEE\dsrk6\bin;C:\Progra~1\7-Zip;C:\Progra~2\7-Zip;%PATH%
set mydate=%date:~-4,4%%date:~-7,2%%date:~-10,2%
set mytime=%time:~0,2%%time:~+3,2%%time:~+6,2%
if "%mytime:~0,1%"==" " set mytime=0%mytime:~1,6%
set projname=DEPLOYMENTNAME
set basedn="dc=company,dc=local"
set dumpdir=c:\backups\regular\ldap-%projname%
set instdir=d:\data-%projname%\ldap\dsins1
set passfile=d:\data-%projname%\ldap\ds6pass

REM Limit CPU usage? Use a space as an empty value!
REM Example hex-mask affinity below sets 2 cores (#3 and 4).
REM set STARTLIMIT= 
set STARTLIMIT=start /LOW /B /WAIT /MIN /AFFINITY 0xc

mkdir %dumpdir% 2>nul
cd %dumpdir% || echo === NO DIR %dumpdir%, aborting! && exit 1

echo === TIMESTAMP: %mydate%_%mytime%

echo === DUMPING: %basedn%
set dumpbase=%dumpdir%\ldap_export_%projname%_%mydate%_%mytime%
%STARTLIMIT% dsconf export -e -w %passfile% %basedn% %dumpbase%.ldif 2>%dumpbase%.log

echo === DUMPING: ldap instance database
set dumpbase=%dumpdir%\ldap_backup_db_%projname%_%mydate%_%mytime%
%STARTLIMIT% dsconf.exe backup -e -w %passfile% %dumpbase% 2>%dumpbase%.log

echo === Compressing results...
mkdir %dumpdir%\compressed 2>nul
cd %dumpdir%\compressed || echo === NO DIR %dumpdir%\compressed, aborting! && exit 1
%STARTLIMIT% 7z a -y ldap_%projname%_%mydate%_%mytime%.7z %instdir%\alias %instdir%\config ..\ldap_backup_db_%mydate%_%mytime% ..\ldap_*_%mydate%_%mytime%.* && echo === Deleting ARCH/LDIF/LOG files... && del /f ..\ldap_*_%mydate%_%mytime%.* && rmdir /q /s ..\ldap_backup_db_%mydate%_%mytime%

echo === DONE

