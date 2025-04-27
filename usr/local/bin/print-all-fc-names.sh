#!/bin/bash

cd /sys/class/fc_host || exit 0
grep . host*/node_name host*/port_name | egrep -o '[a-f0-9]{16}' | sort | uniq 
grep . host*/node_name host*/port_name | egrep -o '[a-f0-9]{16}' | sort | uniq | while read wwn; do echo $wwn | sed -e 's/\(..\)/\1-/g' -e 's/[-:]$//'; done
grep . host*/node_name host*/port_name | egrep -o '[a-f0-9]{16}' | sort | uniq | while read wwn; do echo $wwn | sed -e 's/\(..\)/\1:/g' -e 's/[-:]$//'; done

