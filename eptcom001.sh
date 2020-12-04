#!/bin/bash

# ユーザプロファイル
#EPTAGRREPROFILE="535652911541-aws-tehai"
EPTAGRREPROFILE="user1"
EPTCLIENTPROFILE="user2"

# DynamoDB名称
EPTCONFDB="dynamo_big3219-dev-ClientSideInfo"
EPTMIGDB="dynamo_big3219-dev-MigrationInfo"

# ロググループ、ストリーム名
EPTLOGGROUP="/endpoint/script"
EPTLOGSTREAM=""
EPTNEXTSEQ=""

# 標準エンドポイントのリスト
EPTSTDENDPOINT="com.amazonaws.ap-northeast-1.ec2 \
                com.amazonaws.ap-northeast-1.ec2messages \
                com.amazonaws.ap-northeast-1.logs \
                com.amazonaws.ap-northeast-1.monitoring \
                com.amazonaws.ap-northeast-1.ssm \
                com.amazonaws.ap-northeast-1.ssmmessages \
                com.amazonaws.vpce.ap-northeast-1.vpce-svc-0613e0e16963cb0f4"
#EPTPROXYEPT="com.amazonaws.vpce.ap-northeast-1.vpce-svc-0613e0e16963cb0f4"
EPTPROXYEPT="com.amazonaws.ap-northeast-1.ssmmessages"
EPTPROXYNAME="os-proxy.bgl-private"

function loginit() {

    echo "########## loginit() called : prm : ${1} ###########"
#    return 0

    aws logs create-log-group --log-group-name ${EPTLOGGROUP} --profile ${EPTAGRREPROFILE}
    ret=$?
    if [ 0 -ne ${ret} ]
    then
        return 9
    fi

    if [ -n ${1} ]
    then
        EPTLOGSTREAM=${1}
    else
        return 9
    fi

    EPTsuffix=`date +"%Y%m%d%H%M%S"`
    EPTLOGSTREAM="${EPTLOGSTREAM}_${EPTsuffix}"
    
    aws logs create-log-stream --log-group-name ${EPTLOGGROUP} --log-stream-name ${EPTLOGSTREAM} --profile ${EPTAGRREPROFILE}
    ret=$?
    if [ 0 -ne ${ret} ]
    then
        return 9
    fi

    return 0

}

function logoutput() {

    echo "########## logoutput() called : prm : ${1} ###########"
    return 0

    timestamp=`date +%s%3N`

    if [ -z ${EPTNEXTSEQ} ]
    then
        putlogOutput=`aws logs put-log-events  --log-group-name ${EPTLOGGROUP} \
            --log-stream-name ${EPTLOGSTREAM} --log-events timestamp=${timestamp},message="${1}" \
            --profile ${EPTAGRREPROFILE}`
        ret=$?
    else
        putlogOutput=`aws logs put-log-events  --log-group-name ${EPTLOGGROUP} \
            --log-stream-name ${EPTLOGSTREAM} --log-events timestamp=${timestamp},message="${1}" \
            --sequence-token ${EPTNEXTSEQ}`
        ret=$?
    fi
    
    if [ 0 -ne ${ret} ]
    then
        return 9
    fi
    
    EPTNEXTSEQ=`echo ${putlogOutput} | jq ".nextSequenceToken"`
    return 0

}
