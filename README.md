# 1. 说明
* 此目录下包含应用的helm charts values.yaml文件 ; 
* 文件命名规则：`HELM-APP-NAME-values.yaml`;

## 1.1 `Jenkinsfile`
`Jenkinsfile`为批量部署的Jenkins所使用的Jenkinsfile。其内调用的是下文 2 中的批量更新脚本。

新建一个pipeline流水线`ops-update-uat-apps`，使用此git的`Jenkinsfile`，jenkins不需要配置参数。

## 1.2 `cd.Jenkinsfile`
* `cd.Jenkinsfile`为单程序部署使用的Jenkinsfile。
* Jenkins 任务命名规范：环境_产品线_HELM-APP-NAME;

## 1.3 `ci.Jenkinsfile`
流程是将 git 仓库的代码（内含 Dockerfile）拉下来，推送到专用 docker build 机器构建，然后将镜像上传至 harbor
* Jenkins 任务命名规范：环境_产品线_HELM-APP-NAME;

# 2. 批量更新脚本使用
`config.txt`列表内容示例(可过滤`bak-config.txt`内容编辑整理)：

```
# helm部署名 k8s-namespace helm-charts名 charts版本 pod个数 docker镜像名 tag
demo uat ygqygq2/mdb 5.0.5 1 nginx latest`
```

`Jenkinsfile`中执行批量更新：
`sh jenkins_deploy.sh config.txt`

>建议：
>应用部署成功后使用下文 3 的脚本，不接任何参数，获取当前运行的helm应用的结果`/tmp/deploy_result.txt`内容整理至`bak-config.txt`。

# 3. 根据列表获取当前应用版本信息                                                                                                                                                              
`sh get_helm_image.sh [config.txt]`

如果不接任何参数，将会提示获取哪个namespace下的应用版本信息。

