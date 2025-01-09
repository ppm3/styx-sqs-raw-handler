#!/bin/bash

# Read environment parameter or set default to "dev"
ENV=${1:-dev}
# Read AWS profile parameter or set default to "loquesea"
AWS_PROFILE=${2:-loquesea}
# Read AWS region parameter or set default to "us-west-2"
AWS_REGION=${3:-us-west-2}

while [[ $# -gt 0 ]]
do
	key="$1"
	case $key in
		--env)
		if [ -n "$2" ]; then
			ENV="$2"
			shift 2
		fi
		;;
        --profile)
        if [ -n "$2" ]; then
            AWS_PROFILE="$2"
            shift 2
        fi
        ;;
        --region)
        if [ -n "$2" ]; then
            AWS_REGION="$2"
            shift 2
        fi
        ;;
		*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

echo ""
echo -e  "\e[32m[!!] Preparations for the deployment process \e[0m"
echo ""

echo "[-] Deploying stack to: $ENV"
echo "[-] Using AWS profile: $AWS_PROFILE"
echo "[-] Using AWS region: $AWS_REGION"

if [ -z "$ENV" ]; then
    echo "[!] Environment is not set"
    exit 1
fi

if [ -z "$AWS_PROFILE" ]; then
    echo "[!] AWS profile is not set"
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "[!] AWS region is not set"
    exit 1
fi

if [ "$AWS_PROFILE" == "$ENV" ]; then
    echo "[!] AWS profile should not be the same as the environment"
    exit 1
fi

if [ "$AWS_REGION" == "$ENV" ]; then
    echo "[!] AWS region should not be the same as the environment"
    exit 1
fi

# Get the current folder name
MAIN_DIR=$(basename "$PWD")
SCRIPT_DIR=$(dirname "$0")
echo "[-] Current folder name is: $MAIN_DIR"

__DIR=$(dirname "$(realpath "$0")")
export PROJECT_ROOT="$__DIR"
echo "[-] Exported PROJECT_ROOT: $PROJECT_ROOT"

STACK_NAME="$MAIN_DIR-$ENV"
echo "[-] Stack name is: $STACK_NAME"

LAYER_HASH_FILE="$SCRIPT_DIR/.layer_hash"
if [ ! -f "$LAYER_HASH_FILE" ]; then
    touch "$LAYER_HASH_FILE"
    echo "[*] Created empty .layer_hash file"
fi


SAM_FILE="$SCRIPT_DIR/.sam"
SAM_COPY="$SCRIPT_DIR/samconfig.toml"

# Check if the samconfig.toml file exists
if [ -f "$SAM_COPY" ]; then
    rm "$SAM_COPY"
    echo "[!] Removed existing samconfig.toml"
fi

# Check if the .sam file exists
if [ -f "$SAM_FILE" ]; then
    cp "$SAM_FILE" "$SAM_COPY"
    echo "[-] Copied samconfig.toml"
else
    echo "[X] No SAM template found in $dir"
    exit 1
fi

# update samconfig.toml values
# stack_name = "$STACK_NAME"
# s3_prefix = "$STACK_NAME"
sed -i "s/^stack_name = \".*\"/stack_name = \"$STACK_NAME\"/" "$SAM_COPY"
sed -i "s/^s3_prefix = \".*\"/s3_prefix = \"$STACK_NAME\"/" "$SAM_COPY"
sed -i "s/^region = \".*\"/region = \"$AWS_REGION\"/" "$SAM_COPY"
sed -i "s/^profile = \".*\"/profile = \"$AWS_PROFILE\"/" "$SAM_COPY"

echo "[=] The samconfig.toml file is updated"

# Check if the .params folder exists
PARAM_FILE=".params/$ENV.ini"
if [ ! -f "$PARAM_FILE" ]; then
    echo "[!] No parameter file found for environment: $ENV"
    exit 1
fi
echo "[-] Parameter file is: $PARAM_FILE"

echo ""
echo -e "\e[32m[!!] Start proces for: $STACK_NAME stack in region: $AWS_REGION and env: $ENV \e[0m"
echo ""

echo "[*] Running sam validate: $STACK_NAME"
# Validate the SAM template
sam validate --lint --region $AWS_REGION

if [ $? -ne 0 ]; then
    echo -e "\e[31m[ERROR] Validation failed, stopping script execution. D:\e[0m"
    exit 1
fi

# clean up .aws-sam directory
echo "[!] clean up .aws-sam directory"
rm -rf .aws-sam

echo "[*] Building stack: $STACK_NAME"

# Build the SAM template
sam build 

if [ $? -ne 0 ]; then
    echo -e "\e[31m[ERROR] Build failed, stopping script execution. D: \e[0m"
    exit 1
fi

echo -e  "\e[32m[!!] Build completed successfully \e[0m"

# deploy the stack
echo "[*] Deploying stack: $STACK_NAME ...."
DEPLOY_OUTPUT=$(sam deploy --profile $AWS_PROFILE --stack-name $STACK_NAME --parameter-overrides $(cat $PARAM_FILE) --no-confirm-changeset 2>&1)

if [ $? -ne 0 ]; then
    echo -e "\e[31m[ERROR] Deployment failed, stopping script execution. D: \e[0m"
    echo -e "\e[31m $DEPLOY_OUTPUT \e[0m"
    exit 1
fi

# print output
echo "[*] Stack output:"
echo "$DEPLOY_OUTPUT"


if [ -f "$SAM_COPY" ]; then
    rm "$SAM_COPY"
    echo "[!] Removed existing samconfig.toml"
fi

# Remove .aws-sam directory if it exists
if [ -d ".aws-sam" ]; then
    rm -rf .aws-sam
    echo "[!] Removed .aws-sam directory"
fi

echo ""
echo -e "\e[32m[!!] Deployment completed successfully for environment: $ENV \e[0m"
echo ""
exit 0