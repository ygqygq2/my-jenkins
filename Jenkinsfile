pipeline {
  options {
    // 流水线超时设置
    timeout(time:1, unit: 'HOURS')
    //保持构建的最大个数
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  agent {
    // label "master"
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
    KUBECONFIG = credentials('kubeconfig')
    REGISTRY_SECRET_NAME = ""
  }

  parameters {
    string(defaultValue: 'harbor.k8snb.com', description: '镜像源仓库地址',
        name: 'SRC_HARBOR_URL', trim: true)
    choice(name: 'SRC_HARBOR_REGISTRY', choices: 'uat', description: '选择镜像源仓库')
    string(defaultValue: 'registry.cn-shenzhen.aliyuncs.com', description: '镜像目标仓库地址',
        name: 'DEST_HARBOR_URL', trim: true)
    choice(name: 'DEST_HARBOR_REGISTRY', choices: 'ygqygq2', description: '选择镜像目标仓库')
    choice(name: 'ACTION', choices: 'deploy\nrollback', description: '选择Helm动作')
  }

  stages {
    stage('批量更新helm') {
      steps {
        container('helm') {
          ansiColor('xterm') {
            sh """
              /bin/bash jenkins_deploy.sh config.txt "${ACTION}"
            """
          }
        }
      }
    }
  }
}
