#!/bin/bash

. eptcom001.sh

array=()
CSVDATA=()
MIGERROR="90"
responseTmp="/tmp/eptdeltmp"
jsonTmp="/tmp/del.json"

function readCsvFile() {

	while read line ; do
        array+=($line)
	done < $1

    unset array[0]
    array=(${array[@]})
	CSVLINEMAX=${#array[@]}

	CSVLINEPOS=0
}

function getCsvLine() {

    if [ -n "${1}" ] ; then
	    line=${array[${1}]}
    else
        line=${array[${CSVLINEPOS}]}
        let CSVLINEPOS=+1
    fi

    CSVDATA=(`echo ${line}| tr ',' '\n'`)
    CSVDATACNT=${#CSVDATA[@]}

}


function delEndPoint() {

    echo "########## delEndpoint() : prm : $1 ##########"
#    return 0

    aws ec2 delete-vpc-endpoints \
        --profile ${EPTCLIENTPROFILE} \
        --vpc-endpoint-ids ${1} > $responseTmp

    ret=$?
    if [ 0 -ne ${ret} ]
    then
        return 9
    fi

    # ret=`cat $responseTmp | jq ".Unsuccessful"`
    # if [ "null" == "${ret}" ]
    # then
    #     return 0
    # else
    #     return 1
    # fi
}

function chkProxy() {

    echo "########## chkProxy() : prm : $1 ##########"
#    return 0
    if [ "${EPTPROXYEPT}" == "${1}" ]
    then
        return 0
    else
        return 1
    fi

}

function delDNSrec() {

    echo "########## delDNSrec() : prm : $1 ##########"
#    return 0

    dnslist=`aws route53 list-hosted-zones`
    ret=$?
    if [ 0 -ne ${ret} ]
    then
        return 9
    fi

    maxdnscnt=`echo $dnslist | jq ".HostedZones | length"`
    dnscnt=0
    while [ $dnscnt -lt $maxdnscnt ]
    do
        dnsname=`echo $dnslist | jq ".HostedZones[$dnscnt]" | jq ".Name" | tr -d '"'` 
        if [ $dnsname == $EPTPROXYNAME ]
        then
            echo "delDnsrec"
            hostzonetmp=`echo $dnslist | jq ".HostedZones.[$dnscnt].Id" | tr -d '"'`
            hostzone=`basename $hostzonetmp`
            listdel=`aws route53 list-resource-record-sets --hosted-zone-id $hostzone`
            maxcnt=`echo $listdel | jq".[] |length"`
            x=0
            while [ $x -le $maxcnt ]
            do
                type=`echo $listdel | jq ".[]" | jq ".[$x].Type" | tr -d '"'`
                if [ $type == "NS" ]
                then
                    let x=+1
                    continue
                fi
                if [ $type == "SOA" ]
                then
                    let x=+1
                    continue
                fi
                cp ./delfirst $jsonTmp
                echo $listdel | jq ".[]" | jq ".[$x]" >> $jsonTmp
                cat ./dellast >> $jsonTmp
                #aws route53 change-resource-record-sets --hosted-zone-id $hostzone --change-batch file://${jsonTmp}
                ret=$?
                if [ $ret -ne 0 ]
                then
                    return 9
                fi
                #aws route53 delete-hosted-zone --id $hostzone
                ret=$?
                if [ $ret -ne 0 ]
                then
                    return 9
                fi
                let x=+1
            done                
            break
        else
            continue
        fi
    done
    return 0

}

###########
# 設定用DBにアカウントがあるか確認する
##########

function ConfDBCheck() {

#    echo "ConfDBCheck()"
#    confVpcId="vpc-99999999"
#	return 0

	dbRes=`aws dynamodb get-item \
    			--table-name ${EPTCONFDB} \
    			--key "{\"account_id\": {\"S\": \"${1}\"}}" \
    			--return-consumed-capacity TOTAL`
    
    ret=$?
    if [ 0 -ne ${ret} ]
    then
    	return 9
    fi
    
    confVpcId=`echo ${dbRes} |  jq ".Item.client_VPCid.S" | tr -d '\"'`
    
    return 0

}

###########
# 移行用DBにエラーステータスを書き込む
##########

function wrErrorMig() {
    echo "wrErrorMig"
    return 0
	dbRes=`aws dynamodb put-item \
    			--table-name ${EPTCONFDB} \
    			--item "{\"account_id\": {\"S\": \"${1}\"}, \
                        \"VPC_id\": {\"S\": \"${2}\"}, \
                        \"status\": {\"S\": \"${3}\"}}"`
    
    ret=$?
    if [ 0 -ne ${ret} ]
    then
    	return 9
    fi
    
    confVpcId=`echo ${dbRes} |  jq ".Item.client_VPCid.S" | tr -d '\"'`
    
}

function  chkEndPoint() {
    echo "##### chkEndPoint() : prm : $1 ######"

    ENDPOINT=(${CSVDATA[@]})
    unset ENDPOINT[0]
    unset ENDPOINT[1]

    if [ "#" == "${ENDPOINT[2]}" ]
    then
        unset ENDPOINT[2]
    fi

    ENDPOINT=(${ENDPOINT[@]})
    ENDPOINT=(${EPTSTDENDPOINT} ${ENDPOINT[@]})
    ENDPOINTMAX=${#ENDPOINT[@]}
    return 0

}

function getEndPointid() {

    echo "########## getEndPointid() : prm : $1 ##########"
    endpoint=` aws ec2  describe-vpc-endpoints \
                --profile user1 --filters Name=vpc-id,Values=$1`
}

function cnvEndPointId() {
#    echo "########## cnvEndPointId() : prm : $1 ##########"
    maxEndpoint=`echo ${endpoint} | jq '.VpcEndpoints | length'`
    endpointcnt=0
    while [ $endpointcnt -lt $maxEndpoint ]
    do
        ServiceName=`echo ${endpoint} | jq ".VpcEndpoints[${endpointcnt}].ServiceName" | tr -d '"'`
        if [ "${ServiceName}" == "${1}" ]
        then
            endpointID=`echo ${endpoint} | jq ".VpcEndpoints[$endpointcnt].VpcEndpointId" | tr -d '"'`
            echo "$endpointID"
            return 0
        fi
        let endpointcnt+=1
    done

    return 9

}

##########
## main
##########

    loginit `basename -s .sh ${0}`

    readCsvFile id.csv

    # CSVファイルの全レコードを処理する
    i=0
    while [ ${i} -lt ${CSVLINEMAX} ]
    do
    	# 移行用CSVを1レコード読込む
        getCsvLine
        account=${CSVDATA[0]}
        vpc_id=${CSVDATA[1]}
        #EPTCLIENTPROFILE="${account}-aws-tehai"
        let i+=1

		# 設定用DBにアカウントが存在するか確認する
        ConfDBCheck $account
        ret=$?
        if [ 1 -eq ${ret} ]
        then
            wrErrorMig account vpc_id MIGERROR
            continue
        fi

		# VPC-IDが設定用DBに設定されている値と同じであるか確認する
        if [ ${vpc_id} != ${confVpcId} ]
        then
            wrErrorMig account vpc_id MIGERROR
            continue
        fi

        # エンドポイントのチェック及び展開を行う
        chkEndPoint
        ret=$?
        if [ 0 -ne ${ret} ]
        then
            wrErrorMig account vpc_id MIGERROR
            continue
        fi

        # エンドポイントのリストを取得
        getEndPointid ${vpc_id}
        # エンドポイント全てに対して処理を行う
        j=0

        while [ ${j} -lt ${ENDPOINTMAX} ]
        do
            endPoint=${ENDPOINT[${j}]}
            let j+=1

            endPointId=`cnvEndPointId ${endPoint}`
            echo "xxxxxxx   endpointID = $endPointId"
            if [ $? -eq 0 ]
            then
                delEndPoint ${endPointId}
                ret=$?
                if [ 0 -ne ${ret} ]
                then
                    wrErrorMig account vpc_id MIGERROR
                    continue
                fi
            fi

            # Proxyのエンドポイントか
            chkProxy ${endPoint}
            if [ 0 -eq ${ret} ]
            then
                # DNSのレコード削除
                delDNSrec
                ret=${?}
                if [ 0 -ne ${ret} ]
                then
                    wrErrorMig account vpc_id MIGERROR
                    continue
                fi
            fi
        done
    done


