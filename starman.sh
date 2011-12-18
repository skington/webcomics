#!/bin/sh
# Find out where we're unpacked (thanks to
# http://stackoverflow.com/questions/59895 for this)

DANCERDIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
killall plackup;
plackup \
    --server Starman --app $DANCERDIR/bin/app.pl \
    --port 80 --enviroment development \
    --reload --Reload $DANCERDIR,$DANCERDIR/lib \
    --access_log $DANCERDIR/logs/access_log

