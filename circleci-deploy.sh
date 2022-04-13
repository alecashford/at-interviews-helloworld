#!/bin/bash
set -eox pipefail

# You can pick a unique single-word namespace by passing it as an argument
# to this script, or it'll try to make one for you from your local
# machine's username

# Let's try to set a unique-ish namespace for local testing
if [ $# -eq 0 ]; then
    NAMESPACE=$(whoami)
else
    NAMESPACE=$1
fi

export COMMIT_ID=$(git rev-parse --verify --short HEAD)
echo commit ID is $COMMIT_ID

# This updates your local ~/.kube/config file with authentication info
# for our test EKS cluster
aws eks update-kubeconfig \
    --region us-west-2 \
    --name at-interviews-cluster

kubectl config \
    use-context \
    arn:aws:eks:us-west-2:310228935478:cluster/at-interviews-cluster

# Then we log in to the Elastic Container Registry (ECR) so we have an 
# AWS-accessible place to push the Docker container we're about to build...
aws ecr get-login-password \
    --region us-west-2 \
    | docker login \
    --username AWS \
    --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com

# Container gets built at this step.  Those tags are needed so the following
# 'docker push' step sends the container to the right ECR repo
docker build \
    --no-cache \
    --build-arg GIT_COMMIT=$COMMIT_ID \
    -t helloworld:$COMMIT_ID \
    -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/helloworld:$COMMIT_ID \
    .

# If we've tagged our container appropriately above, this should send the 
# container to ECR, where Kubernetes/Helm can pull it down
docker push \
    ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/helloworld:$COMMIT_ID

# This connects to Kubernetes (EKS) and tells it to deploy the above container
# It also has a bunch of niceties in there around setting up an ALB (so we can
# view it Across The Internet™, etc - this SHOULD be fairly hands-off.  Whatever
# $COMMIT_ID this repo has, is sent to ECR as a tag, and EKS/k8s uses that to
# pull down the appropriate build.  
helm upgrade \
    --install \
    --namespace $NAMESPACE \
    --create-namespace \
    helloworld \
    --set image.tag=$COMMIT_ID \
    helm/helloworld

echo "Deployed commit $COMMIT_ID to namespace $NAMESPACE"
unset COMMIT_ID
