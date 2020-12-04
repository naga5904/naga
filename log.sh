#!/bin/bash

timestamp=`date +%s%3N`

logoutput=`aws logs put-log-events  --log-group-name test_endpoint --log-stream-name endpoint_stream --log-events timestamp=$timestamp,message="test_endpoint event2" --sequence-token $1`

echo $?

echo $logoutput

