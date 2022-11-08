import hudson.model.*;

pipeline {
  options {
    // 流水线超时设置
    timeout(time: 1, unit: 'HOURS')
    //保持构建的最大个数
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  agent {
    // k8s pod设置
    kubernetes {
      inheritFrom "jenkins-slave-${UUID.randomUUID().toString()}"
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins-role: k8s-slave
spec:
  containers:
  - name: helm
    image: ygqygq2/k8s-alpine:latest
    command:
    - cat
    tty: true
"""
    }
  }

  environment {
    // 全局环境变量
    KUBERNETES_VERSION = "v1.22.3-aliyun.1"  // k8s版本
    KUBECONFIG = credentials('kubeconfig')  // k8s config
    REGISTRY_SECRET_NAME = ""
    CHART_NAME = "mdb"  // chart模板名
    CHART_VALUES_DIR = "."  // charts values.yaml目录
    // CHART_VERSION = "3.0.0"  // chart模板版本，此处不定义，由Jenkins界面参数传入
    KUBE_NAMESPACE = "uat"  // 部署在k8s中的namespace名
    HELM_VERSION = "v3.9.0"  // 记录使用的helm版本信息
    HELM_REPO = "https://charts.linuxba.com/speed-up"  // harbor charts仓库
    HELM_REPO_NAME = "ygqygq2"  // charts仓库名
  }

  parameters {
    // string(defaultValue: 'harbor.k8snb.com', description: '镜像源仓库地址',
    //     name: 'SRC_HARBOR_URL', trim: true)
    // choice(name: 'SRC_HARBOR_REGISTRY', choices: 'uat', description: '选择镜像源仓库')
    string(defaultValue: 'registry.cn-shenzhen.aliyuncs.com', description: '镜像目标仓库地址',
        name: 'DEST_HARBOR_URL', trim: true)
    choice(name: 'DEST_HARBOR_REGISTRY', choices: 'ygqygq2', description: '选择镜像目标仓库')
    string(defaultValue: '1', description: 'pod副本数',
        name: 'REPLICAS', trim: true)
    string(defaultValue: '5.0.5', description: 'mdb chart 模板版本',
        name: 'CHART_VERSION', trim: true)
    string(defaultValue: 'latest', description: '镜像 tag',
        name: 'TAG', trim: true)
    choice(name: 'ACTION', choices: 'deploy\nrollback', description: '选择Helm动作')
  }

  stages {
    stage('Get App Name') {
      steps {
        script {
          env.APP_NAME = env.JOB_NAME.split('_')[-1];
        }
      }
    }
    stage('Deploy App') {
      steps {
        container('helm') {
          script {
            if (env.ACTION == "deploy") {
              echo "#######################容器部署开始#######################"
              // 不存在helm charts相应版本目录时
              file_name = "${env.WORKSPACE}/${env.CHART_NAME}-${env.CHART_VERSION}"
              if (fileExists(file_name) == false) {
                sh """#!/bin/sh -e\n
                  helm repo add ${HELM_REPO_NAME} ${HELM_REPO}
                  helm repo update
                  helm pull ${HELM_REPO_NAME}/${CHART_NAME} --version=$CHART_VERSION --untar
                  mv ${CHART_NAME} ${CHART_NAME}-${CHART_VERSION}
                """
              }

              sh '''#!/bin/sh -e\n
                helm_options=""
                if [[ ! -f "${CHART_VALUES_DIR}/${APP_NAME}-values.yaml" ]]; then
                  echo "#########不存在配置 [${CHART_VALUES_DIR}/${APP_NAME}-values.yaml]##########"
                  exit 1
                else
                  helm_options="$helm_options -f ${CHART_VALUES_DIR}/${APP_NAME}-values.yaml"
                fi

                if [[ ! -z "${REPLICAS}" ]]; then
                  helm_options="$helm_options --set replicaCount=${REPLICAS}"
                fi
 
                helm_status=$(helm list -n $KUBE_NAMESPACE|egrep "^${APP_NAME}[[:space:]]"|awk '{print $8}')
                if [[ "$helm_status" == "failed" ]]; then
                    helm uninstall "$APP_NAME" -n $KUBE_NAMESPACE
                fi
                if [[ -z "$(helm list -q -n $KUBE_NAMESPACE|egrep "^${APP_NAME}$")" ]]; then
                  eval helm upgrade "${APP_NAME}" --install \
                    --atomic \
                    --namespace "$KUBE_NAMESPACE" \
                    --set image.registry="${DEST_HARBOR_URL}" \
                    --set image.repository="${DEST_HARBOR_REGISTRY}/${APP_NAME}" \
                    --set image.tag="${TAG}" \
                    ${helm_options} \
                    --force \
                    ${CHART_NAME}-${CHART_VERSION}/
                else
                  # 先判断是否已运行相同tag的应用
                  image_repository=$(helm get values "${APP_NAME}" -n "$KUBE_NAMESPACE" -ojson\
                      |jq ".image.repository"|sed 's@"@@g')
                  image_tag=$(helm get values "${APP_NAME}" -n "$KUBE_NAMESPACE" -ojson\
                      |jq ".image.tag"|sed 's@"@@g')
                  if [[ "$image_repository" == "${DEST_HARBOR_REGISTRY}/${APP_NAME}" ]] && \
                      [[ "$image_tag" == "${TAG}" ]]; then
                    eval helm upgrade "${APP_NAME}" --reuse-values --install \
                      --namespace "$KUBE_NAMESPACE" \
                      --set image.registry="${DEST_HARBOR_URL}" \
                      --set image.repository="${DEST_HARBOR_REGISTRY}/${APP_NAME}" \
                      --set image.tag="${TAG}" \
                      --set podAnnotations.restart="$(date +%F-%H-%M)" \
                      ${helm_options} \
                      --force \
                      ${CHART_NAME}-${CHART_VERSION}/
                  else
                    eval helm upgrade "${APP_NAME}" --reuse-values --install \
                      --namespace "$KUBE_NAMESPACE" \
                      --set image.registry="${DEST_HARBOR_URL}" \
                      --set image.repository="${DEST_HARBOR_REGISTRY}/${APP_NAME}" \
                      --set image.tag="${TAG}" \
                      ${helm_options} \
                      --force \
                      ${CHART_NAME}-${CHART_VERSION}/
                  fi 
                fi
                
                kubectl rollout status -n "$KUBE_NAMESPACE" -w "deployment/${APP_NAME}-${CHART_NAME}" \
                  || kubectl rollout status -n "$KUBE_NAMESPACE" -w "statefulset/${APP_NAME}-${CHART_NAME}" \
                  || kubectl rollout status -n "$KUBE_NAMESPACE" -w "deployment/${APP_NAME}" \
                  || kubectl rollout status -n "$KUBE_NAMESPACE" -w "statefulset/${APP_NAME}"
              '''
              echo "#######################容器部署完成#######################"
            } else {
              echo "#######################未进行容器部署#######################"
            }
          }
        }
      }
    }

    stage('Rollback App') {
      steps {
        container('helm') {
          ansiColor('xterm') {
            script {
              if (env.ACTION == "rollback") {
                echo "#######################回滚开始#######################"
                sh '''#!/bin/sh -e\n
                  . function.sh
                  yellow_echo "Rollback [$APP_NAME]"
                  revision=$(helm list -n $namespace|egrep "^${APP_NAME} "|awk '{print $3}')
                  rollback_revision=$(($revision-1))
                  helm get --revision $rollback_revision "$APP_NAME" > /dev/null
                  if [ $? -eq 0 ]; then
                      helm rollback "$APP_NAME" $(($revision-1))
                  else
                      red_echo "Can not rollback [$APP_NAME], the revision [$rollback_revision] not exsit. "
                  fi
                '''
                echo "#######################回滚结束#######################"
              }
            }
          }
        }  
      }
    }
  }

  post {
    always {
      script{
        currentBuild.description = "${env.APP_NAME}:${env.TAG}"
      }
    }
  }
}

