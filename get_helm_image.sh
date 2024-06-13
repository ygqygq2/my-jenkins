#!/usr/bin/env bash
# 获取deploy镜像信息

#获取脚本所存放目录
cd `dirname $0`
SH_DIR=`pwd`
ME=$0
PARAMETERS=$*
config_file="${1:-/tmp/helm_config.txt}"
update_file="/tmp/update.md"
helm_result="/tmp/helm_result.txt"
helm_result_md="/tmp/helm_result.md"
deploy_result="/tmp/deploy_result.txt"
deploy_result_md="/tmp/deploy_result.md"
helm_repo_name="ygqygq2"
thread=1 # 此处定义线程数
faillog="./failure.log" # 此处定义失败列表,注意失败列表会先被删除再重新写入
#git pull

#定义输出颜色函数
function red_echo () {
#用法:  red_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;31m ${what} \e[0m"
}

function green_echo () {
#用法:  green_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;32m ${what} \e[0m"
}

function yellow_echo () {
#用法:  yellow_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;33m ${what} \e[0m"
}

function blue_echo () {
#用法:  blue_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;34m ${what} \e[0m"
}

function twinkle_echo () {
#用法:  twinkle_echo $(red_echo "内容")  ,此处例子为红色闪烁输出
    local twinkle='\e[05m'
    local what="${twinkle} $*"
    echo -e "$(date +%F-%T) ${what}"
}

function return_echo () {
    if [ $? -eq 0 ]; then
        echo -n "$*" && green_echo "成功"
        return 0
    else
        echo -n "$*" && red_echo "失败"
        return 1
    fi
}

function return_error_exit () {
    [ $? -eq 0 ] && local REVAL="0"
    local what=$*
    if [ "$REVAL" = "0" ];then
            [ ! -z "$what" ] && { echo -n "$*" && green_echo "成功" ; }
    else
            red_echo "$* 失败，脚本退出"
            exit 1
    fi
}

#定义确认函数
function user_verify_function () {
    while true;do
        echo ""
        read -p "是否确认?[Y/N]:" Y
        case $Y in
            [yY]|[yY][eE][sS])
                echo -e "answer:  \\033[20G [ \e[1;32m是\e[0m ] \033[0m"
                break
                ;;
            [nN]|[nN][oO])
                echo -e "answer:  \\033[20G [ \e[1;32m否\e[0m ] \033[0m"
                exit 1
                ;;
            *)
                continue
        esac
    done
}

#定义跳过函数
function user_pass_function () {
    while true;do
        echo ""
        read -p "是否确认?[Y/N]:" Y
        case $Y in
            [yY]|[yY][eE][sS])
                echo -e "answer:  \\033[20G [ \e[1;32m是\e[0m ] \033[0m"
                break
                ;;
            [nN]|[nN][oO])
                echo -e "answer:  \\033[20G [ \e[1;32m否\e[0m ] \033[0m"
                return 1
                ;;
            *)
                continue
        esac
    done
}

function deploy_get_image() {
    local helm_name=$1
    local namespace=$2
    echo
    yellow_echo "获取deploy [$line] 镜像"
    local image_url=$(helm get manifest $helm_name -n $namespace|grep 'image:'|head -n 1|awk -F':' '{print $2}')
    local image_tag=$(helm get manifest $helm_name -n $namespace|grep 'image:'|head -n 1|awk -F':' '{print $3}')
    local replica=$(helm get values $helm_name -n $namespace|grep '^replicaCount:'|awk -F':' '{print $2}')
    local charts_name=$(cat $config_file|egrep "^$helm_name[[:space:]]"|awk '{print $(NF-1)}'|awk -F'-' '{print $1}')
    local charts_version=$(cat $config_file|egrep "^$helm_name[[:space:]]"|awk '{print $(NF-1)}'|awk -F'-' '{print $2}')
    local line="$helm_name $namespace ${helm_repo_name}/$charts_name $charts_version $replica $image_url $image_tag"
    local md_line="|$helm_name |$namespace |${helm_repo_name}/$charts_name |$charts_version |$replica |$image_url |$image_tag|"
    if [ $? -eq 0 ]; then
        echo $line >> $deploy_result
        echo $md_line >> $deploy_result_md
    fi
}

function usage() {
    echo "sh $ME [config.txt]"
}

function newfile() {
    cat /dev/null > $deploy_result
cat >$deploy_result_md<<EOF    
---
## $(date +"%F %T")

|helm部署名 |k8s-namespace |helm-charts名 |charts版本 |pod个数 |docker镜像名 |docker tag|
|-|-|-|-|-|-|-|
EOF
}

function git_push() {
    \mv $update_file ${update_file}.tmp
    cat $deploy_result_md > $update_file
    cat ${update_file}.tmp >> $update_file
    rm -f ${update_file}.tmp
    git pull
    git add -A
    git commit -m "update: $(date +%F)"
    git push
}

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
            deploy_get_image $excute_line
            echo >&6 # 当进程结束以后，再向fd6中加上一个回车符，即补上了read -u6减去的那个
        } &
    done
     
    wait # 等待所有的后台子进程结束
    exec 6>&- # 关闭df6
     
    if [ -f $faillog ];then
        red_echo -e "Has failure job"
        exit 1
    else
        green_echo "All finish"
        echo "#############################"
    fi
}

if [ ! -f "$config_file" ]; then
    usage
    yellow_echo "输入namespace名，将获取其下全部应用列表"
    read -p "[Namespace:] " get_namespace
    helm list -n $get_namespace|egrep "[[:space:]]${helm_repo_name}-"|grep -v NAMESPACE > $config_file
fi

newfile
multi_process
echo >> $deploy_result
#git_push

[ ! -z "$get_namespace" ] && rm -f $config_file

exit 0
