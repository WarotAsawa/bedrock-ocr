echo "Building Docker image and tagging"
docker build -t bedrock-ocr:latest .
docker tag bedrock-ocr:latest 638806779113.dkr.ecr.us-east-1.amazonaws.com/bedrock-ocr:latest

echo "Loggin into ECR"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 638806779113.dkr.ecr.us-east-1.amazonaws.com

echo "Pusing Image into ECR"
docker push 638806779113.dkr.ecr.us-east-1.amazonaws.com/bedrock-ocr:latest

echo "Updating ECR Services"
aws ecs update-service --cluster gen-ai-km-demo --service bedrock-ocr-svc --force-new-deployment --region us-east-1
echo "Finishing updating ECR Services"
