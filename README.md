# github-actions-terraform
# 概要
GitHub ActionsによるTerraformのCIサンプルです。
特徴は以下の通りです。
- OpenID Connect(OIDC)でのAWS認証によるActions実行により、アクセスキー&シークレットキー管理が不要
- Terraformのデファクトとなっているディレクトリ構成で作成
- その上でActionsでは、更新があったディレクトリを特定し、そのディレクトリのみTerraformを実行。


`terrafrom/envs/xxx`のように環境面など、実行ディレクトリが特定されている場合は、ワークフローを分けてしまった方が簡単ですが、アカウントやプロジェクトなどTerraform実行ディレクトリが単純増加するユースケースで、このサンプルの枠フローが効果を発揮します。

## 前提とするTerraformのディレクトリ構成
terraformのモジュールの標準的なディレクトリ構成を前提としています。
`/terraform/accounts/`配下にそれぞれのアカウント単位でterrafomを管理するイメージです。
アカウントを追加する場合は、`_template`フォルダを任意の名称でコピーして適切に設定を変更してterraformでapplyします。
```
.
└── terraform
    ├── accounts
    │   ├── _template
    │   ├── user-a
    │   │   ├── backend.tf
    │   │   ├── main.tf
    │   │   ├── provider.tf
    │   │   └── terraform.tf
    │   ├── user-b
    │   └── user-c
    └── modules
        └── xxxxx
```
## GitHub Actionsの前提
- mainブランチへのマージで、AWS環境へのデプロイが実行されます
- mainブランチへはPull Requestでマージする前提です。mainブランチへの直接pushの場合、Actionsが正常に動作しません
- はPull Request作成/更新時に、`terraform plan`を実行します
- terraform実行アカウントは以下のルールで決定します
    - `terraform/accounts/`配下で更新があったアカウントのディレクトリが対象となります
    - ただし`modules`配下で更新が発生した場合は、`terraform/accounts/`配下のすべてのアカウントのディレクトリが対象となります

# セットアップ手順
## 事前準備
実行環境として`AdministratorAccess`権限でマネージメントコンソール操作が可能なユーザを用意します。

## GitHub CI環境のセットアップ
### GitHubのリポジトリ作成
- GitHubでリポジトリを作成します
- 作成したリポジトリのリポジトリ名を控えます(`NoppyOrg/github-actions-terraform`など)

## AWS環境でのTerraform実行に必要なリソースの作成
GitHub Actionsによる実行および、Terraformの実行に必要なリソースをAWS環境に設定します。
具体的には以下のリソースを作成します。
- OIDC Provider
- IAMロール(GitHub ActionsからWebFederationによりAssumeRoleされる先のIAMロールであり、Terraformの実行ロール)
- Terraformのバックエンド用S3バケット
- Terraformのロック用DynamoDBテーブル

### OIDCプロバイダー/IAMロール/S3バケット/DynamoDB作成
Terrafom実行に必要な、OIDCプロバイダー、IAMロール、バックエンド用のS3バケット、ロックテーブル用のDynamoDBテーブルをCloudFormationを利用し作成します。
スタックは、以下の内容で作成します。
- 対象リージョン: `東京リージョン( ap-northeast-1 )`
- スタック名: `terraform`
- テンプレート: `setup_github/setup_resources_for_github.yaml`
- パラメータ:
    - GitRepositoryName: `Actionsを実行するGitHubのリポジトリ名(Organizations名/リポジトリ名)`を指定

スタックの出力に後続のGitHubやTerraformの設定で必要な内容が出力されるので確認します。
- GitHubへの設定に必要
    - `RoleArn` : GitHubからAssumeRoleする先のロール名
- Terraformコードへの設定に必要
    - `BackendBacketName` : Terraformのバックエンド用のS3バケット名
    - `LockStateTableName` : Terraformのロック用DynamoDBテーブルのテーブル名

## GitHubリポジトリ設定
GitHubリポジトリの`Actions Secrets`に`ASSUME_ROLE_ARN`というSecrets名でCloudFormationで作成したRoleのARNを指定します。
1. リポジトリの`Settings`に移動します。
1. 左のメニューから`Secrets`の`Actions`を選択します。
1. 右上の`New repository secret`を選び、下記設定をします。
    - `Name` :  `ASSUME_ROLE_ARN`と指定します。Actionsの中では`${{ secrets.ASSUME_ROLE_ARN }}`という形で呼び出されます。
    - `Value` : CloudFormationのスタックの出力に`RoleArn`で出力されているIAMロールのARNを設定します。
1. 設定されると`Repository secrets`に表示されます。

設定画面
![GitHub Secrets設定イメージ](./Documents/github_secrets_setting.png)

## Terraform変更
### 既存の developmentディレクトリの置き換え
`terraform/accounts/template`フォルダの内容を更新します。

### バックエンド設定の変更
`terraform/accounts/_template/backend.tf`で以下の二点を修正します。
- `bucket` : CloudFormationのスタックの出力の`BackendBacketName`を指定します。
-  `dynamodb_table` : CloudFormationのスタックの出力の`LockStateTableName`を指定します。

- `terraform/accounts/_template/backend.tf`
```
terraform {
  backend "s3" {
    bucket         = "<CFnで作成したバケットの名前>"
    key            = "development/terraform.tfstate"
    dynamodb_table = "<CFnで作成したDynamoDBのテーブル名>"
    region         = "ap-northeast-1"
  }
}
```
## GitHubへのリリース
- このActionsは、mainブランチへ直接pushでは正常に動作しません。mainブランチには必ずPull Requestでマージしてください。
- 具体的手順は以下の通りです。
    - GitHubにはフューチャーブランチ(`feature`または`feature-*`の名称)で、Pushします(terraform planが実行されます)
    - フューチャーブランチから、mainブランチへのPull Requestを作成します。(terraform planが実行されます)
    - mainブランチにマージされるとterraform applyが実行され環境に適用されます。

# Actions説明
## ジョブ構成
ワークフローは、以下の２つのジョブで構成しています。
1. 更新されたterraformディレクトリ特定JOB
1. 特定したterraformディレクトリに対してのterraform実行(matrixによる並列実行)

## 更新ディレクトリの特定方法
更新ディレクトリは、`git diff`で`origin/main`ブランチからの更新リストを取得し、シェルで更新があったディレクトリを特定しています。
具体的には以下の処理をしています。
1. ターゲットブランチ(`origin/main`)特定 : pull requestとmainブランチへのプッシュでターゲットブランチの特定方法がことなります。
    1. Pull Request: `${{ github.base_ref }}`
    1. MainブランチへのPush: `${GITHUB_REF#refs/heads/}`
1. 差分取得 : `git diff`コマンドで`/terraform/accounts`配下の差分を特定します。
    1. Pull Request: `git diff origin/${TARGET_BRANCH} HEAD --name-only -- /terraform/accounts`
    1. MainブランチへのPush: `git diff HEAD^ HEAD --name-only -- /terraform/accounts`
1. 差分からsedコマンドから`/terraform/accounts`直下のファイル/ディレクトリを抽出します。
    1. コマンド : `sed -E 's:(^${{ env.TERRAFORM_TARGET_DIR }}/[^/]*/)(.*$):\1:'`
    1. 処理イメージ
        1. 処理前
            ```
            terraform/accounts/_template/terraform.tf
            terraform/accounts/user-b/terraform.tf
            terraform/accounts/user-b/backend.tf
            terraform/accounts/user-a/main.tf
            terraform/accounts/user-a/provider.tf
            ```
        1. 処理後
            ```
            terraform/accounts/_template/
            terraform/accounts/user-b/
            terraform/accounts/user-b/
            terraform/accounts/user-a/
            terraform/accounts/user-a/
            ```
1. 重複データを排除します
    1. コマンド : `sort | uniq`
    1. 処理イメージ
        1. 処理前
            ```
            terraform/accounts/_template/
            terraform/accounts/user-b/
            terraform/accounts/user-b/
            terraform/accounts/user-a/
            terraform/accounts/user-a/
            ```
        1. 処理後
            ```
            terraform/accounts/_template/
            terraform/accounts/user-b/
            terraform/accounts/user-a/
            ```
1. 存在するディレクトリのみ残します(ディレクトリ削除更新対策)。また`_template`ディレクトリを除外します。
    1. コマンド : `awk '{ if( system("[ -d "$1" ]") == 0 && $1 !~ /${{env.TERRAFORM_ENVS_EXCLUDED_DIR}}/ ){print $1} }'`
    1. 処理イメージ
        1. 処理前
            ```
            terraform/accounts/_template/
            terraform/accounts/user-b/
            terraform/accounts/user-a/
            ```
        1. 処理後
            ```
            terraform/accounts/user-b/
            terraform/accounts/user-a/
            ```
1. JSONのLIST形式に変換します。
    1. コマンド : `jq -scR 'split("\n") | .[:-1]'`
    1. 処理イメージ
        1. 処理前
            ```
            terraform/accounts/user-b/
            terraform/accounts/user-a/
            ```
        1. 処理後
            ```
            [ "terraform/accounts/user-b/", "terraform/accounts/user-a/" ]
            ```