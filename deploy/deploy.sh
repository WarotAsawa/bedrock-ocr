#!/bin/bash
set -e

# Configuration
AWS_REGION=${AWS_REGION:-"us-east-1"}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="bedrock-ocr-app"
IMAGE_TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
CLUSTER_NAME="bedrock-ocr-cluster"
SERVICE_NAME="bedrock-ocr-service"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
aws sts get-caller-identity > /dev/null || { echo "AWS credentials not configured correctly"; exit 1; }

# Create ECR repository if it doesn't exist
echo "Checking if ECR repository exists..."
aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_REGION} > /dev/null 2>&1 || \
    aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region ${AWS_REGION}

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push Docker image
echo "Building Docker image..."
docker build -t ${ECR_REPOSITORY}:${IMAGE_TAG} .

echo "Tagging Docker image..."
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}

echo "Pushing Docker image to ECR..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}

# Create SSM parameter for SECRET_KEY if it doesn't exist
echo "Checking if SSM parameter exists..."
aws ssm get-parameter --name "/bedrock-ocr/SECRET_KEY" --region ${AWS_REGION} > /dev/null 2>&1 || \
    aws ssm put-parameter --name "/bedrock-ocr/SECRET_KEY" --type "SecureString" --value "$(openssl rand -base64 32)" --region ${AWS_REGION}

# Create IAM roles if they don't exist
echo "Creating IAM roles if they don't exist..."

# Check if ecsTaskExecutionRole exists
aws iam get-role --role-name ecsTaskExecutionRole > /dev/null 2>&1 || {
    echo "Creating ecsTaskExecutionRole..."
    aws iam create-role \
        --role-name ecsTaskExecutionRole \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    
    aws iam attach-role-policy \
        --role-name ecsTaskExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    aws iam attach-role-policy \
        --role-name ecsTaskExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess
}

# Check if bedrockOcrAppRole exists
aws iam get-role --role-name bedrockOcrAppRole > /dev/null 2>&1 || {
    echo "Creating bedrockOcrAppRole..."
    aws iam create-role \
        --role-name bedrockOcrAppRole \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    
    # Create policy document for Bedrock access
    cat > bedrock-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name bedrockOcrAppRole \
        --policy-name BedrockAccess \
        --policy-document file://bedrock-policy.json
    
    rm bedrock-policy.json
}

# Create CloudWatch Logs group if it doesn't exist
echo "Creating CloudWatch Logs group if it doesn't exist..."
aws logs describe-log-groups --log-group-name-prefix "/ecs/bedrock-ocr-app" --region ${AWS_REGION} > /dev/null 2>&1 || \
    aws logs create-log-group --log-group-name "/ecs/bedrock-ocr-app" --region ${AWS_REGION}

# Create ECS cluster if it doesn't exist
echo "Creating ECS cluster if it doesn't exist..."
aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} | grep -q "ACTIVE" || \
    aws ecs create-cluster --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION}

# Create task definition
echo "Creating ECS task definition..."
sed -e "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
    -e "s/\${AWS_REGION}/${AWS_REGION}/g" \
    -e "s/\${IMAGE_TAG}/${IMAGE_TAG}/g" \
    deploy/ecs-task-definition.json > deploy/ecs-task-definition-updated.json

aws ecs register-task-definition \
    --cli-input-json file://deploy/ecs-task-definition-updated.json \
    --region ${AWS_REGION}

# Check if service exists
SERVICE_EXISTS=$(aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION} | jq -r '.services | length')

if [ "$SERVICE_EXISTS" -eq 0 ]; then
    echo "Creating new ECS service..."
    
    # Create security group for the service
    VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text --region ${AWS_REGION})
    
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "bedrock-ocr-sg" \
        --description "Security group for Bedrock OCR app" \
        --vpc-id ${VPC_ID} \
        --region ${AWS_REGION} \
        --output text --query 'GroupId')
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp \
        --port 8080 \
        --cidr 0.0.0.0/0 \
        --region ${AWS_REGION}
    
    # Get default subnets
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0:2].SubnetId' \
        --output text \
        --region ${AWS_REGION})
    
    # Replace spaces with commas
    SUBNET_IDS=$(echo ${SUBNET_IDS} | tr ' ' ',')
    
    # Create load balancer
    LB_ARN=$(aws elbv2 create-load-balancer \
        --name bedrock-ocr-lb \
        --subnets ${SUBNET_IDS} \
        --security-groups ${SECURITY_GROUP_ID} \
        --region ${AWS_REGION} \
        --output text --query 'LoadBalancers[0].LoadBalancerArn')
    
    # Create target group
    TG_ARN=$(aws elbv2 create-target-group \
        --name bedrock-ocr-tg \
        --protocol HTTP \
        --port 8080 \
        --vpc-id ${VPC_ID} \
        --target-type ip \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --region ${AWS_REGION} \
        --output text --query 'TargetGroups[0].TargetGroupArn')
    
    # Create listener
    aws elbv2 create-listener \
        --load-balancer-arn ${LB_ARN} \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
        --region ${AWS_REGION}
    
    # Create service
    aws ecs create-service \
        --cluster ${CLUSTER_NAME} \
        --service-name ${SERVICE_NAME} \
        --task-definition bedrock-ocr-app \
        --desired-count 1 \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_IDS}],securityGroups=[${SECURITY_GROUP_ID}],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=${TG_ARN},containerName=bedrock-ocr-app,containerPort=8080" \
        --region ${AWS_REGION}
    
    # Get load balancer DNS name
    LB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${LB_ARN} \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region ${AWS_REGION})
    
    echo "Service created successfully!"
    echo "Application will be available at: http://${LB_DNS}"
else
    echo "Updating existing ECS service..."
    aws ecs update-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --task-definition bedrock-ocr-app \
        --force-new-deployment \
        --region ${AWS_REGION}
    
    echo "Service updated successfully!"
fi

echo "Deployment completed successfully!"