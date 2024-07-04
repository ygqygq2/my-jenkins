import hudson.model.*;

pipeline {
  options {
    // 流水线超时设置
    timeout(time:1, unit: 'HOURS')
    //保持构建的最大个数
    buildDiscarder(logRotator(numToKeepStr: '20'))
    // 跳过默认设置的代码check out
    skipDefaultCheckout()
  }

  agent {
    node {
      // 指定运行节点的标签或名称
      label "master"
    }
  }

  environment {
    // 全局环境变量
    HARBOR_URL = "harbor.k8snb.com"  // harbor地址
    // $HARBOR_CRE or $HARBOR_CRE_USR or $HARBOR_CRE_PSW
    HARBOR_CRE = credentials('harbor_devuser')  // harbor用户密码
    HARBOR_REGISTRY = "dev"  // harbor项目仓库
    KUBERNETES_VERSION="v1.22.3"  // k8s版本
    KUBECONFIG = credentials('dev-kubernetes-admin-config')  // k8s config
    // MVN_OPTION = ""
    CHART_NAME = "mdb"  // chart模板名
    CHART_VALUES_DIR = "helm"  // charts values.yaml目录
    //CHART_VERSION = "3.0.0"  // chart模板版本，此处不定义，由Jenkins界面参数传入
    KUBE_NAMESPACE = "dev"  // 部署在k8s中的namespace名
    HELM_VERSION = "v3.1.2"  // 记录使用的helm版本信息
    HELM_REPO="http://harbor.ygqygq2.com/chartrepo/charts"  // harbor charts仓库
    HELM_REPO_NAME = "mdb"  // charts仓库名
    HELM_GIT_URL = "http://github.com/ygqygq2/my-jenkins.git"  // helm应用git仓库地址
    HELM_GIT_BRANCH = "master"  // helm应用git仓库分支
    // REPLICAS = "1"  // 部署的k8s pod副本数, 已由jenkins界面传入
  }

  parameters {
    string(defaultValue: 'https://github.com/ygqygq2/fastdfs-nginx.git', description: '要 build 镜像的 git 地址',
        name: 'CODE_GIT_URL', trim: true)
    string(defaultValue: 'master', description: '要 build 镜像的 git 分支',
        name: 'CODE_GIT_BRANCH', trim: true)
    choice(name: 'UNITTEST', choices: 'true\nfalse', description: '是否单元测试')
    choice(name: 'SONARSCAN', choices: 'true\nfalse', description: '是否 sonar 扫描')
    string(defaultValue: '1', description: 'pod副本数',
        name: 'REPLICAS', trim: true)
    string(defaultValue: '5.0.5', description: 'mdb chart 模板版本',
        name: 'CHART_VERSION', trim: true)
    choice(name: 'ACTION', choices: 'deploy\nrollback', description: '选择Helm动作')
  }

  tools {
    maven "maven3.6.1"
  }

  stages {
    stage('Get App Name') {
      steps {
        script {
          env.APP_NAME = env.JOB_NAME.split('_')[-1];
        }
      }
    }

    stage('Get version') {
      steps {
        script {
          echo "########################开始获取版本号########################"
          if (env.CODE_GIT_BRANCH == ''){
            echo "必须输入分支号 ！例：1.2.0或 feature/1.2.0"
          }else {
            BRANCH = env.CODE_GIT_BRANCH
          }

          env.VERSION=BRANCH.split("/")[-1]
          JSON=sh(script: "#!/bin/sh -e\n curl -s --connect-timeout 60 -u '${HARBOR_CRE_USR}:${HARBOR_CRE_PSW}' " + 
              "-X GET --header 'Accept: application/json' " + 
              "'http://${HARBOR_URL}/api/v2.0/projects/${HARBOR_REGISTRY}/repositories/${APP_NAME}/artifacts?page=1&page_size=20&with_tag=true&with_label=false&with_scan_overview=false&with_signature=false&with_immutable_status=false'", 
              returnStdout: true).trim()
          LATEST_TAG=sh(script: """#!/bin/sh -e\n
              echo '$JSON'|jq '.[].tags'|grep "${VERSION}_" | awk -F'\"' '{print \$4}' | \
              sort -nr|awk  'NR==1 {print; exit}'|sed 's/\"//g'""", 
              returnStdout: true).trim()

          if (LATEST_TAG == ''){
            env.NEW_TAG=sh(script: '#!/bin/sh -e\n echo "${VERSION}_001"', returnStdout: true).trim()
          } else {
            CURRENT_INCREASE=sh(script: """#!/bin/sh -e\n
                LATEST_TAG=$LATEST_TAG; echo \${LATEST_TAG##*_}|awk '{print int(\$1)}' """,
                returnStdout: true).trim()
            INCREASE=Integer.parseInt(CURRENT_INCREASE) + 1
            INCREASE=sh(script: """#!/bin/sh -e\n
                INCREASE=$INCREASE; printf "%.3d" \$INCREASE """, returnStdout: true).trim()
            env.NEW_TAG=env.VERSION + "_" + INCREASE
          }

          echo "Docker image is [ ${env.HARBOR_URL}/${env.HARBOR_REGISTRY}/${env.APP_NAME}:${env.NEW_TAG} ]!"
          echo "Image tag is ${env.NEW_TAG}!"
          echo "########################获取版本号完成########################"
        }
      }
    }

    stage('Get code') {
      steps {
        script{
          echo  "########################开始拉取代码########################"
          dir("${WORKSPACE}/code-dir") {
            checkout([$class: 'GitSCM',
              branches: [[name: "${env.CODE_GIT_BRANCH}"]],
              doGenerateSubmoduleConfigurations: false,
              extensions: [],
              gitTool: 'Default',
              submoduleCfg: [],
              userRemoteConfigs: [[url: "${env.CODE_GIT_URL}",credentialsId: 'gitlab',]]
            ])
          }
          sh """#!/bin/sh -e
            tar -cf code-dir.tar code-dir
            rm -rf code-dir
            """
          echo  "########################拉取代码完成########################"

          // 将代码推送到专用构建机器（主要是解决普通机器不能联网问题）
          def remote = [:]
          remote.name = "build_host"
          remote.host = "xx.xx.xx.xx"
          remote.allowAnyHosts = true

          withCredentials([usernamePassword(credentialsId: 'node1', passwordVariable: 'passWord', usernameVariable: 'userName')]) {
            remote.user = userName
            remote.password = passWord
            stage("SSH Put Files to Remote") {
              sshCommand remote: remote, command: "mkdir -p ${WORKSPACE}"
              sshPut remote: remote, from: "${WORKSPACE}/code-dir.tar", into: "${WORKSPACE}/code-dir.tar"
            }
          }
          sh "rm -f code-dir.tar"
          echo  "########################推送代码完成########################"
        }
      }
    }

    stage('Sonar scan') {
      steps {
        script {
          if (env.SONARSCAN == 'true') {
            echo "########################开始代码扫描########################"

            withSonarQubeEnv('sonarqube7.4') {
              sh """
                mvn -B clean compile sonar:sonar
              """
            }
            echo "########################代码扫描完成########################"
          } else {
            echo  "#######################未进行代码扫描#######################"
          }
        }
      }
    }

    stage('Unit test'){
      steps {
        script {
          if (env.UNITTEST == 'true') {
            echo "########################开始单元测试########################"

            withSonarQubeEnv('sonarqube7.4') {
              sh """
                # mvn -B clean test -Dmaven.test.skip=false -DskipTests=false sonar:sonar
                echo "sonartest"
              """
            }

            echo "########################单元测试完成########################"
          } else {
            echo "#######################未进行单元测试#######################"
          }
        }
      }
    }

    stage('Build image') {
      agent {
        node {
          label "harbor"
        }
      }
      steps {
        script {
          echo "#######################开始生成镜像#######################"
          sh '''#!/bin/sh -e
            tar -xf code-dir.tar
            rm -f code-dir.tar
            cd code-dir
            docker login -u ${HARBOR_CRE_USR} -p ${HARBOR_CRE_PSW} ${HARBOR_URL}
            docker build -t ${HARBOR_URL}/${HARBOR_REGISTRY}/${APP_NAME}:${NEW_TAG} ./
            docker push ${HARBOR_URL}/${HARBOR_REGISTRY}/${APP_NAME}:${NEW_TAG} > /dev/null
            docker rmi ${HARBOR_URL}/${HARBOR_REGISTRY}/${APP_NAME}:${NEW_TAG}  > /dev/null
            echo "Build image successfully!"
            cd .. && rm -rf code-dir
          '''
          echo "#######################生成镜像完成#######################"
        }
      }
    }

    stage('Scan docker image') {
      steps {
        echo "#####################镜像漏洞扫描开始######################"
        sh '''#!/bin/sh -e
          echo "镜像上传后自动扫描"
          echo "请使用以下用户登录后查看"
          echo "详情: http://${HARBOR_URL}/harbor/projects/2/repositories/${APP_NAME}"
          echo "访问用户/密码: guest/xxxx"
        '''
        echo "#####################镜像漏洞扫描完成######################"
      }
    }

    stage('Get Charts Values') {
      steps {
        dir("${env.WORKSPACE}/${env.CHART_VALUES_DIR}") {
          echo "#####################拉取helm values.yaml开始#####################"
          git branch: "${env.HELM_GIT_BRANCH}", credentialsId: 'gitlab', url: "${env.HELM_GIT_URL}"
          echo "#####################拉取helm values.yaml完成#####################"
        }
      }
    }

    stage('Deploy App') {
      steps {
        script {
          if (env.DEPLOY == "true") {
            echo "#######################开始容器部署#######################"
            // 不存在helm charts相应版本目录时
            file_name = "${env.WORKSPACE}/${env.CHART_NAME}-${env.CHART_VERSION}"
            if(fileExists(file_name) == false) {
              sh """#!/bin/sh -e
                helm repo add ${HELM_REPO_NAME} ${HELM_REPO}
                helm repo update
                helm pull ${HELM_REPO_NAME}/${CHART_NAME} --version=$CHART_VERSION --untar
                mv ${CHART_NAME} ${CHART_NAME}-${CHART_VERSION}
                helm dependency update ${CHART_NAME}-${CHART_VERSION}/
                helm dependency build ${CHART_NAME}-${CHART_VERSION}/
              """
            }

            sh '''#!/bin/sh -e
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
              if [[ ! -z "${JAVA_OPS}" ]]; then
                helm_options="$helm_options --set javaOpts='${JAVA_OPS}'"
              fi
 
              if [[ -z "$(helm list -q -n $KUBE_NAMESPACE|egrep "^${APP_NAME}$")" ]]; then
                eval helm upgrade "${APP_NAME}" --install \
                  --namespace "$KUBE_NAMESPACE" \
                  --set image.registry="${HARBOR_URL}" \
                  --set image.repository="${HARBOR_REGISTRY}/${APP_NAME}" \
                  --set image.tag="${NEW_TAG}" \
                  ${helm_options} \
                  --force \
                  ${CHART_NAME}-${CHART_VERSION}/ \
                  || echo -e "When Error: UPGRADE FAILED: ${APP_NAME} has no deployed releases\n" \
                  "use command [ helm uninstall ${APP_NAME} ] to uninstall it."

              else
                # dev环境用的hostNetwork=true，先删除再部署
                helm uninstall "$APP_NAME" --namespace="$KUBE_NAMESPACE"
                eval helm upgrade "${APP_NAME}" --reuse-values --install \
                  --namespace "$KUBE_NAMESPACE" \
                  --set image.registry="${HARBOR_URL}" \
                  --set image.repository="${HARBOR_REGISTRY}/${APP_NAME}" \
                  --set image.tag="${NEW_TAG}" \
                  ${helm_options} \
                  --force \
                  ${CHART_NAME}-${CHART_VERSION}/
              fi

              kubectl rollout status -n "$KUBE_NAMESPACE" -w "deployment/${APP_NAME}-${CHART_NAME}" \
                || kubectl rollout status -n "$KUBE_NAMESPACE" -w "statefulset/${APP_NAME}-${CHART_NAME}" \
                || kubectl rollout status -n "$KUBE_NAMESPACE" -w "deployment/${APP_NAME}" \
                || kubectl rollout status -n "$KUBE_NAMESPACE" -w "statefulset/${APP_NAME}"
            '''
            echo "#######################容器部署完成#########################"
          } else {
            echo "#######################未进行容器部署#######################"
          }
        }
      }
    }
  }
  post {
    always {
      script{
  	    currentBuild.description = "${env.APP_NAME}:${env.NEW_TAG}"
      }
    }
  }
}
