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
    KUBECONFIG = credentials('kubeconfig')  // k8s config
    REGISTRY_SECRET_NAME = ""
    CHART_NAME = "mdb"  // chart模板名
    CHART_VALUES_DIR = "."  // charts values.yaml目录
    // CHART_VERSION = "3.0.0"  // chart模板版本，此处不定义，由Jenkins界面参数传入
    KUBE_NAMESPACE = "uat"  // 部署在k8s中的namespace名
    HELM_REPO = "https://charts.linuxba.com/speed-up"  // harbor charts仓库
    HELM_REPO_NAME = "ygqygq2"  // charts仓库名
    SRC_HARBOR_CRE = credentials('harbor_devuser')  // 源harbor用户密码
    DEST_HARBOR_CRE = credentials('harbor_devuser')  // 目标harbor用户密码
    // SKOPEO_ARGS = "--src-tls-verify=false --dest-tls-verify=false"
  }

  parameters {
    string(defaultValue: 'harbor.ygqygq2.com', description: '镜像源仓库地址',
        name: 'SRC_HARBOR_URL', trim: true)
    choice(name: 'SRC_HARBOR_REGISTRY', choices: 'uat', description: '选择镜像源仓库')
    string(defaultValue: 'harbor.ygqygq2.com', description: '镜像目标仓库地址',
        name: 'DEST_HARBOR_URL', trim: true)
    choice(name: 'DEST_HARBOR_REGISTRY', choices: 'pre', description: '选择镜像目标仓库')
    string(defaultValue: '1', description: 'pod副本数',
        name: 'REPLICAS', trim: true)
    string(defaultValue: '5.0.7', description: 'mdb chart 模板版本',
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
          sh """
            echo "$APP_NAME $DEST_HARBOR_REGISTRY $CHART_NAME $CHART_VERSION $REPLICAS $SRC_HARBOR_URL/$SRC_HARBOR_REGISTRY/$APP_NAME $TAG" > _config.txt
          """
        }
      }
    }
    stage('Deploy App') {
      steps {
        container('helm') {
          ansiColor('xterm') {
            sh """
              /bin/bash jenkins_deploy.sh _config.txt "${ACTION}"
            """
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
