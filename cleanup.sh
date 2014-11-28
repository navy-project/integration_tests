#!/bin/bash
docker ps | grep 'example' | awk '{print $1}' | xargs docker stop -t 0
docker ps -aq | xargs docker rm
