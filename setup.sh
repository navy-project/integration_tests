#!/bin/bash

cd example_containers/test_daemon
docker build -t test_daemon .

cd ../test_task
docker build -t test_task .
