@echo off

REM Copyright (C) 2010 Jim Klimov, JSC COS&HT
REM This script finds %veryold% files in the directory dedicated for automated
REM backups and removes them to free up space for new backups

set basedir=C:\Backups\regular

set veryold=30
REM veryold = days old for a regular dump file to be deleted

cd %basedir% || echo === NO DIR %basedir%, aborting! && exit 1

forfiles /P %basedir% /S /D -%veryold% /C "cmd /c if @isdir==FALSE echo DELETING @file && del /q /f @file"

