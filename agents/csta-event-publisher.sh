#!/bin/sh

# runs the jevent agent indefinitely
HAFFA=/var/haffa
USER=nobody

while :
do
   chown $USER $HAFFA/config/csta-event-publisher.ini
   /bin/su - $USER -c "$HAFFA/scripts/csta-event-publisher.pl -c $HAFFA/config/csta-event-publisher.ini"
   sleep 1
done
