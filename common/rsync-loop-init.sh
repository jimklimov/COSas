#!/bin/sh
# chkconfig: 2345 91 59
# description: script to loop rsync and replicate local files to remote storage

### $Id: rsync-loop-init.sh,v 1.3 2014/12/08 16:29:55 jim Exp $
### Trivial wrapper for rsync-loop as init script
### (C) 2011 Jim Klimov, COS&HT
BINFILE=/opt/COSas/bin/rsync-loop.sh
LOGFILE=/var/log/rsync-loop.log

RES=0
if [ -x "$BINFILE" -a $# -gt 0 ]; then
        "$BINFILE" "$@"
        RES=$?
        if [ $RES = 0 ]; then
                echo "$BINFILE $@:      [--OK--]"
        else
                echo "$BINFILE $@:      [-FAIL-] ($RES)"
        fi
else
        echo "FATAL: $BINFILE not accessible or no options passed!" >&2
        RES=1
fi

exit $RES

