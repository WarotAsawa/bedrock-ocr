# Deployment Guide for Bedrock OCR App

This guide explains how to deploy the Bedrock OCR application to AWS ECS (Elastic Container Service) using Fargate.

## Prerequisites

Before deploying, ensure you have:

1. AWS CLI installed and configured with appropriate permissions
2. Docker installed and running
3. jq installed (for JSON processing)
4. Git installed (for versioning)

## Required AWS Permissions

The AWS user or role executing the deployment script needs the following permissions:

- ECR: CreateRepository, DescribeRepositories, GetAuthorizationToken
- ECS: CreateCluster, CreateService, DescribeClusters, DescribeServices, RegisterTaskDefinition, UpdateService
- IAM: AttachRolePolicy, CreateRole, GetRole, PutRolePolicy
- EC2: AuthorizeSecurityGroupIngress, CreateSecurityGroup, DescribeSubnets, DescribeVpcs
- ELB: CreateListener, CreateLoadBalancer, CreateTargetGroup, DescribeLoadBalancers
- CloudWatch Logs: CreateLogGroup, DescribeLogGroups
- SSM: GetParameter, PutParameter
- STS: GetCallerIdentity

## Deployment Steps

1. **Configure AWS credentials**:
   ```
   aws configure
   ```

2. **Set environment variables** (optional):
   ```
   export AWS_REGION=us-east-1  # Change to your preferred region
   ```

3. **Run the deployment script**:
   ```
   ./deploy/deploy.sh
   ```

The script will:
- Create an ECR repository if it doesn't exist
- Build and push the Docker image
- Create necessary IAM roles
- Create a CloudWatch Logs group
- Create an ECS cluster if it doesn't exist
- Register the ECS task definition
- Create or update the ECS service
- Set up a load balancer if creating a new service

## Post-Deployment

After successful deployment, the script will output the URL where your application is accessible.

## Monitoring

You can monitor your application using:

- **CloudWatch Logs**: Check logs at `/ecs/bedrock-ocr-app`
- **ECS Console**: View task status and service health
- **Load Balancer Console**: Monitor request traffic and health checks

## Troubleshooting

If deployment fails:

1. Check CloudWatch Logs for application errors
2. Verify IAM roles have correct permissions
3. Ensure your AWS account has access to Amazon Bedrock
4. Check security group settings allow traffic to port 8080

## Cleanup

To remove all resources:

1. Delete the ECS service
2. Delete the ECS cluster
3. Delete the load balancer and target group
4. Delete the ECR repository
5. Delete the IAM roles
6. Delete the CloudWatch Logs group
7. Delete the SSM parameter