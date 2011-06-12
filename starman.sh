#!/bin/sh

killall plackup;
/usr/local/bin/plackup \
    --server Starman --app /home/sam/dancer/bin/app.pl \
    --port 80 --enviroment development \
    --reload --Reload /home/sam/dancer,/home/sam/dancer/lib \
    --access_log /home/sam/dancer/logs/access_log

