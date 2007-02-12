#!/bin/sh

# runs the jevent agent indefinitely
CSTA=/var/csta

while :
do
   $CSTA/scripts/csta-event-publisher.pl -c $CSTA/config/csta-event-publisher.ini
   sleep 1
done
