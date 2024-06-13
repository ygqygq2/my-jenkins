#!/usr/bin/env bash
# jenkins helm部署脚本，需要接文件列表
#set -x

#获取脚本所存放目录
cd `dirname $0`
SH_DIR=`pwd`
ME=$0
PARAMETERS=$*
config_file="$1"
action="${2:-deploy}"
# 是否使用 docker-registry
docker_registry_secret="${REGISTRY_SECRET_NAME}"
docker_registry="${DEST_HARBOR_URL}"
docker_repository="${DEST_HARBOR_REGISTRY}"
dest_repo="${DEST_HARBOR_URL}/${DEST_HARBOR_REGISTRY}"  # 包含仓库项目的名字
#docker_repository="dev"  # 调试所用
thread=5 # 此处定义线程数
faillog="./failure.log" # 此处定义失败列表,注意失败列表会先被删除再重新写入
echo >> $config_file

HELM_REPO="https://ygqygq2.github.io/charts/speed-up"
HELM_REPO_NAME="ygqygq2"

. $SH_DIR/function.sh

function helm_check() {
    if [ ! -f "~.helm/repository/repositories.yaml" ]; then
        helm repo add ${HELM_REPO_NAME} ${HELM_REPO}
    fi
}

function check_image() {
    local image_name=$1
    local image_tag=$2
    curl -s -i -u "$DEST_HARBOR_CRE_USR:$DEST_HARBOR_CRE_PSW" -k -X GET \
        "http://$DEST_HARBOR_URL/api/repositories/$DEST_HARBOR_REGISTRY/$image_name/tags/$image_tag" -H "accept: application/json" \
        | grep '"name":' > /dev/null
    [ $? -eq 0 ] && return 0 || return 1
}

function sync_image() {
    local line=$*
    line=$(echo "$line"|sed 's@docker.io/@@g')
    if [[ ! -z $(echo "$line"|grep '/') ]]; then
        case $dest_registry in
            basic)
            local image_name=$(echo $line|awk -F':|/' '{print $(NF-2)"/"$(NF-1)}')
            ;;
            *)
            local image_name=$(echo $line|awk -F':|/' '{print $(NF-1)}')
            ;;
        esac
        if [[ ! -z $(echo "$image_name"|grep -w "$dest_registry") ]]; then 
            local image_name=$(basename $image_name) 
        fi
    else
        local image_name=$(echo ${line%:*})
    fi
    local image_tag=$(echo $line|awk -F: '{print $2}')
    check_image $image_name $image_tag
    return_echo "检测镜像 [$image_name] 存在 " 
    if [ $? -ne 0 ]; then
        echo
        yellow_echo "同步镜像[ $line ]"
        docker pull $SRC_HARBOR_URL/$SRC_HARBOR_REGISTRY/$image_name:$image_tag \
            && docker tag $SRC_HARBOR_URL/$SRC_HARBOR_REGISTRY/$image_name:$image_tag $dest_repo/$image_name:$image_tag \
            && docker push $dest_repo/$image_name:$image_tag \
            && docker rmi $SRC_HARBOR_URL/$SRC_HARBOR_REGISTRY/$image_name:$image_tag \
            && docker rmi $dest_repo/$image_name:$image_tag \
        || { red_echo "同步镜像[ $line ]"; echo "$line" | tee -a $faillog ; }
    else
        green_echo "已存在镜像，不需要推送[$dest_repo/$image_name:$image_tag]"
    fi
}

function deploy() {
    local line=$*
    local helm_name=$1
    local namespace=$2
    local helm_chart=$3
    local helm_chart_version=$4
    local replicas=$5    
    local image_url=$6
    local image_tag=$7

    ######################### 同步镜像 ########################
    # sync_image ${image_url}:${image_tag}
    ###########################################################

    ################# 检查 helm chart目录是否存在 ##############
    local chart_name=$(basename $helm_chart)
    local chart_dir=${chart_name}-${helm_chart_version}
    # 删除从右边开始到最后一个"/"及其右边所有字符
    local image_registry=${image_url%%/*}
    # 删除从左边开始到第一个"/"及其左边所有字符
    if [ ! -z "$docker_repository" ]; then
        # 重新拼接
        local image_repository="$docker_repository/$(basename $image_url)"
    else
        local image_repository=${image_url#*/} 
    fi

    if [ ! -d "$chart_dir" ]; then
        helm pull --untar $helm_chart --version=$helm_chart_version
        return_echo "helm pull --untar $helm_chart --version=$helm_chart_version"
        [ $? -ne 0 ] && return 1 || mv $chart_name $chart_dir
    fi
    ###########################################################
    
    echo "#############################"
    green_echo "Deploy [$helm_name] "
    # user_verify_function
    if [ -f $SH_DIR/${helm_name}-values.yaml ]; then
        values_option="-f $SH_DIR/${helm_name}-values.yaml"
    else
        red_echo "没有helm配置文件，跳过更新"
        return 1
    fi

    if [ ! -z "$docker_registry_secret" ]; then
        docker_registry_option="--set image.pullSecrets[0]=$docker_registry_secret"
    else
        docker_registry_option=""
    fi    

    if [ ! -z "$docker_registry" ]; then
        image_registry=$docker_registry
    fi

    helm_status=$(helm list -n $namespace|egrep "^${APP_NAME}[[:space:]]"|awk '{print $8}')
    if [[ "$helm_status" == "failed" ]]; then
        helm uninstall "$helm_name" -n $namespace
    fi
    if [[ -z "$(helm list -q -n $namespace|egrep "^${APP_NAME}$")" ]]; then
        helm upgrade --install \
            --atomic \
            --namespace="$namespace" \
            --set image.registry="${image_registry}" \
            --set image.repository="${image_repository}" \
            --set image.tag="${image_tag}" \
            --set replicaCount="$replicas" \
            --force \
            $values_option \
            $docker_registry_option \
            "$helm_name" \
            $chart_dir/
    else
        helm upgrade --reuse-values --install \
            --namespace="$namespace" \
            --set image.registry="${image_registry}" \
            --set image.repository="${image_repository}" \
            --set image.tag="${image_tag}" \
            --set replicaCount="$replicas" \
            --force \
            $values_option \
            $docker_registry_option \
            "$helm_name" \
            $chart_dir/
    fi

    kubectl rollout status -n "${namespace}" -w "deployment/${helm_name}-${chart_name}" \
        || kubectl rollout status -n "${namespace}" -w "statefulset/${helm_name}-${chart_name}" \
        || kubectl rollout status -n "${namespace}" -w "deployment/${helm_name}" \
        || kubectl rollout status -n "${namespace}" -w "statefulset/${helm_name}"
    [ $? -ne 0 ] && echo "$line" | tee -a $faillog
}

function rollback() {
    local line=$*
    local helm_name=$1
    local namespace=$2

    echo "#############################"
    yellow_echo "Rollback [$helm_name] "
    local revision=$(helm list -n $namespace|egrep "^${APP_NAME} "|awk '{print $3}')
    local rollback_revision=$(($revision-1))
    helm get --revision $rollback_revision "$helm_name" > /dev/null
    if [ $? -eq 0 ]; then
        helm rollback "$helm_name" $(($revision-1))
    else
        red_echo "Can not rollback [$helm_name], the revision [$rollback_revision] not exsit. "
    fi
}

function usage() {
    echo "sh $ME config.txt [deploy|rollback]"
}

if [ -z "$PARAMETERS" ]; then
    usage
    exit 55
fi
 
function trap_exit() {
    kill -9 0
}
 
function multi_process() {
    trap 'trap_exit;exit 2' 1 2 3 15
     
    if [ -f $faillog ];then
        rm -f $faillog
    fi

    tmp_fifofile="./$$.fifo"
    mkfifo $tmp_fifofile      # 新建一个fifo类型的文件
    exec 6<>$tmp_fifofile      # 将fd6指向fifo类型
    rm $tmp_fifofile
     
     
    for ((i=0;i<$thread;i++)); do
        echo
    done >&6 # 事实上就是在fd6中放置了$thread个回车符
     
    filename=$config_file
    exec 5<$filename
    while read line <&5
    do
        excute_line=$(echo $line|egrep -v "^#")
        if [ -z "$excute_line" ]; then
            continue
        fi
        read -u6
        # 一个read -u6命令执行一次，就从fd6中减去一个回车符，然后向下执行，
        # fd6中没有回车符的时候，就停在这了，从而实现了线程数量控制
        { # 此处子进程开始执行，被放到后台
            $action $excute_line 
            echo >&6 # 当进程结束以后，再向fd6中加上一个回车符，即补上了read -u6减去的那个
        } &
    done
     
    wait # 等待所有的后台子进程结束
    exec 6>&- # 关闭df6
     
    if [ -f $faillog ];then
        echo "#############################"
        red_echo "Has failure job list:"
        echo
        cat $faillog
        echo "#############################"
        exit 1
    else
        green_echo "All finish"
        echo "#############################"
    fi
}    


helm_check
multi_process

exit 0
