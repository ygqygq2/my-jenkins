#!/usr/bin/env bash
# jenkins helm部署脚本，需要接文件列表
# set -x

#获取脚本所存放目录
cd $(dirname $0)
SH_DIR=$(pwd)
ME=$0
PARAMETERS=$*
config_file="$1"
action="${2:-deploy}"
# 默认使用环境变量中的配置
# REGISTRY_SECRET_NAME=""
# DEST_HARBOR_URL=""
# DEST_HARBOR_REGISTRY="dev"  # 调试所用
dest_registry="${DEST_HARBOR_REGISTRY:-library}"
dest_repo="${DEST_HARBOR_URL}/${dest_registry}" # 包含仓库项目的名字
thread=5                # 此处定义线程数
faillog="./failure.log" # 此处定义失败列表,注意失败列表会先被删除再重新写入
echo >>$config_file

HELM_TYPE=${HELM_TYPE:-web}
HELM_REPO=${HELM_REPO:-https://ygqygq2.github.io/charts}
HELM_REPO_NAME=${HELM_REPO_NAME:-ygqygq2}

. $SH_DIR/function.sh

function helm_check() {
    if [ ! -z $(echo $HELM_REPO | grep 'oci://') ]; then
        return 0
    fi

    HELM_TYPE="web"
    if [ -z $(helm repo list | grep $HELM_REPO_NAME) ]; then
        helm repo add ${HELM_REPO_NAME} ${HELM_REPO}
    fi
}

function check_image() {
    local image_name=$1
    local image_tag=$2
    local encoded
    encoded=$(curl -s -o /dev/null -w %{url_effective} --get --data-urlencode "$image_name" "http://localhost")
    # 移除前缀部分，只保留编码后的结果
    encoded=$(echo $encoded | sed 's@http://localhost/?@@')
    curl -s -i --connect-timeout 10 -m 20 -u "$DEST_HARBOR_CRE_USR:$DEST_HARBOR_CRE_PSW" -k -X GET \
        -H "accept: application/json" \
        "https://$DEST_HARBOR_URL/api/v2.0/projects/$dest_registry/repositories/$encoded/artifacts/$image_tag/tags?page=1&page_size=10&with_signature=false&with_immutable_status=false" |
        grep '"name":' >/dev/null
    return $?
}

function check_skopeo() {
    command -v skopeo &>/dev/null
}

function check_docker() {
    command -v docker &>/dev/null
}

function skopeo_sync_image() {
    local line=$1
    local image_name=$2
    local image_tag=$3
    skopeo copy -a \
        --src-creds=${SRC_HARBOR_CRE_USR}:${SRC_HARBOR_CRE_PSW} \
        --dest-creds=${DEST_HARBOR_CRE_USR}:${DEST_HARBOR_CRE_PSW} \
        ${SKOPEO_ARGS} \
        docker://${line} \
        docker://$dest_repo/$image_name:$image_tag
    return $?
}

function docker_login() {
    echo "${SRC_HARBOR_CRE_PSW}" | docker login --username "${SRC_HARBOR_CRE_USR}" --password-stdin $SRC_HARBOR_URL
    echo "${DEST_HARBOR_CRE_PSW}" | docker login --username "${DEST_HARBOR_CRE_USR}" --password-stdin $DEST_HARBOR_URL
}

function docker_sync_image() {
    local line=$1
    local image_name=$2
    local image_tag=$3
    check_docker
    if [ $? -ne 0 ]; then
        yellow_echo "没有 docker 命令"
        return 1
    fi
    docker pull $line &&
        docker tag $line $dest_repo/$image_name:$image_tag &&
        docker push $dest_repo/$image_name:$image_tag &&
        docker rmi $line &&
        docker rmi $dest_repo/$image_name:$image_tag ||
        {
            red_echo "同步镜像[ $line ]"
            echo "$line" | tee -a $faillog
        }
}

function sync_image() {
    local line=$*
    local image_name
    local image_tag
    line=$(echo "$line" | sed 's@docker.io/@@')
    line=$(echo "$line" | sed "s@$DEST_HARBOR_URL/$DEST_HARBOR_REGISTRY@$SRC_HARBOR_URL/$SRC_HARBOR_REGISTRY@")
    if [[ ! -z $(echo "$line" | grep '/') ]]; then
        case $dest_registry in
        basic|library)
            image_name=$(echo $line | awk -F':|/' '{print $(NF-2)"/"$(NF-1)}')
            ;;
        *)
            image_name=$(echo $line | awk -F':|/' '{print $(NF-1)}')
            ;;
        esac
        if [[ ! -z $(echo "$image_name" | grep -w "$dest_registry") ]]; then
            image_name=$(basename $image_name)
        fi
    else
        image_name=$(echo ${line%:*})
    fi
    image_tag=$(echo $line | awk -F: '{print $2}')
    check_image $image_name $image_tag
    return_echo "检测镜像 [$image_name] 存在 "
    if [ $? -ne 0 ]; then
        echo
        yellow_echo "同步镜像[ $line ]"
        if [ "$have_skopeo" -eq 0 ]; then
            skopeo_sync_image "$line" "$image_name" "$image_tag" || docker_sync_image "$line" "$image_name" "$image_tag"
        else
            docker_sync_image "$line" "$image_name" "$image_tag"
        fi
    else
        green_echo "已存在镜像，不需要推送[$dest_repo/$image_name:$image_tag]"
        return 0
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
    sync_image ${image_url}:${image_tag}
    ###########################################################

    ################# 检查 helm chart目录是否存在 ##############
    local chart_name=$(basename $helm_chart)
    local chart_dir=${chart_name}-${helm_chart_version}
    # 删除从右边开始到最后一个"/"及其右边所有字符
    local image_registry=${image_url%%/*}
    # 删除从左边开始到第一个"/"及其左边所有字符
    if [ ! -z "$DEST_HARBOR_REGISTRY" ]; then
        # 重新拼接
        local image_repository="$DEST_HARBOR_REGISTRY/$(basename $image_url)"
    else
        local image_repository=${image_url#*/}
    fi

    if [[ "$HELM_TYPE" != "oci" ]]; then
        if [[ $helm_chart != *"$HELM_REPO_NAME/"* ]]; then
            helm_chart="$HELM_REPO_NAME/$helm_chart"
        fi
    else
        helm_chart="${HELM_REPO}/${helm_chart#"$HELM_REPO_NAME/"}"
    fi

    if [ ! -d "$chart_dir" ]; then
        [ -d "$chart_name" ] && mv $chart_name /tmp/$chart_name-$(date +%F-%T)
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

    if [ ! -z "$REGISTRY_SECRET_NAME" ]; then
        docker_registry_option="--set image.pullSecrets[0]=$REGISTRY_SECRET_NAME"
    else
        docker_registry_option=""
    fi

    if [ ! -z "$DEST_HARBOR_URL" ]; then
        image_registry=$DEST_HARBOR_URL
    fi

    # 检查 Helm Release 是否存在并获取状态
    helm_status=$(helm list -n "$namespace" -f "^${helm_name}$" | awk 'NR==2 {print $8}')
    
    # 如果 Helm Release 存在且状态为 failed，则卸载
    if [[ "$helm_status" == "failed" ]]; then
        helm uninstall "$helm_name" -n "$namespace"
        helm_status=""
    fi
    
    # 检查 Helm Release 是否存在
    if [[ -n "$helm_status" ]]; then
        values_option="$values_option --atomic"

        # 获取 Helm Release 的值
        helm_values=$(helm get values "$helm_name" -n "$namespace" -ojson 2>/dev/null)
        
        # 提取旧的 image.repository 和 image.tag
        old_image_repository=$(echo "$helm_values" | jq -r ".image.repository")
        old_image_tag=$(echo "$helm_values" | jq -r ".image.tag")
    
        # 判断是否已运行相同 tag 的应用
        if [[ "$image_repository" == "$old_image_repository" ]] && [[ "$image_tag" == "$old_image_tag" ]]; then
            values_option="$values_option --set podAnnotations.restart=$(date +%F-%H-%M)"
        fi
    fi
    
    # 执行 Helm install/upgrade
    helm upgrade --install \
        --namespace="$namespace" \
        --set image.registry="${image_registry}" \
        --set image.repository="${image_repository}" \
        --set image.tag="${image_tag}" \
        --set replicaCount="$replicas" \
        $values_option \
        $docker_registry_option \
        "$helm_name" \
        "$chart_dir/"

    kubectl rollout status -n "${namespace}" -w "deployment/${helm_name}-${chart_name}" ||
        kubectl rollout status -n "${namespace}" -w "statefulset/${helm_name}-${chart_name}" ||
        kubectl rollout status -n "${namespace}" -w "deployment/${helm_name}" ||
        kubectl rollout status -n "${namespace}" -w "statefulset/${helm_name}"
    [ $? -ne 0 ] && echo "$line" | tee -a $faillog
}

function rollback() {
    local line=$*
    local helm_name=$1
    local namespace=$2

    echo "#############################"
    yellow_echo "Rollback [$helm_name] "
    local revision=$(helm list -n $namespace | egrep "^${APP_NAME} " | awk '{print $3}')
    local rollback_revision=$(($revision - 1))
    helm get --revision $rollback_revision "$helm_name" >/dev/null
    if [ $? -eq 0 ]; then
        helm rollback "$helm_name" $(($revision - 1))
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

    if [ -f $faillog ]; then
        rm -f $faillog
    fi

    tmp_fifofile="./$$.fifo"
    mkfifo $tmp_fifofile  # 新建一个fifo类型的文件
    exec 6<>$tmp_fifofile # 将fd6指向fifo类型
    rm $tmp_fifofile

    for ((i = 0; i < $thread; i++)); do
        echo
    done >&6 # 事实上就是在fd6中放置了$thread个回车符

    filename=$config_file
    exec 5<$filename
    while read line <&5; do
        excute_line=$(echo "$line" | grep -E -v "^#")
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

    wait      # 等待所有的后台子进程结束
    exec 6>&- # 关闭df6

    if [ -f $faillog ]; then
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

check_skopeo
have_skopeo=$?
if [ "$have_skopeo" -ne 0 ]; then
    docker_login
fi
helm_check
multi_process

exit 0
