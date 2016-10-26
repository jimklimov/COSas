@echo off

REM (C) 2010 Jim Klimov, JSC COS&HT
REM This script makes an archve from specified source data (requires installed 7z)
REM %1 = dump path (temp dir, under it will be "conpressed\" with final files)
REM %2 = dump file base name, timestamp will be attached
REM %3... = source objects to dump into archive

set PATH=C:\Progra~1\7-Zip;C:\Progra~2\7-Zip;%PATH%
set mydate=%date:~-4,4%%date:~-7,2%%date:~-10,2%
set mytime=%time:~0,2%%time:~+3,2%%time:~+6,2%
if "%mytime:~0,1%"==" " set mytime=0%mytime:~1,6%
REM set dumpdir=c:\backups\magnolia
REM set srcdir=c:\magnolia-4.2.4

REM Limit CPU usage? Use a space as an empty value!
REM Example hex-mask affinity below sets 2 cores.
set STARTLIMIT= 
REM set STARTLIMIT=start /LOW /B /WAIT /MIN /AFFINITY 0x3

set dumpdir=%1
shift

set nametag=%1
shift

if "%1"=="" echo === BAD PARAMS! & echo FILEDUMP "dumpdir" "nametag" "list" "of" "source" "objects" & exit

mkdir %dumpdir% 2>nul
cd %dumpdir% || echo === NO DIR %dumpdir%, aborting! && exit 1

echo === TIMESTAMP: %mydate%_%mytime%

echo === DUMPING: %nametag%
echo === OBJECTS: %1 %2 %3 %4 %5 %6 %7 %8 %9
mkdir %dumpdir%\compressed 2>nul

cd %dumpdir%\compressed || echo === NO DIR %dumpdir%\compressed, aborting! && exit 1
%STARTLIMIT% 7z a -y %nametag%_%mydate%_%mytime%.7z %1 %2 %3 %4 %5 %6 %7 %8 %9

echo === DONE

