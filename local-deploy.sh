#!/bin/bash
set -eox pipefail

# You can pick a unique single-word namespace by passing it as an argument
# to this script, or it'll try to make one for you from your local
# machine's username

AWS_ACCOUNT="310228935478"

# This confirms we're pointing at the appropriate AWS account before trying
# to do anything
CURRENT_AWS_TARGET=$(aws --profile at-interviews \
    sts get-caller-identity \
    | grep Account \
    | awk -F: '{print $2}' \
    | tr -d \"\,\ \
    )

if [[ ! "$CURRENT_AWS_TARGET" = "$AWS_ACCOUNT" ]]; then
    echo "We don't appear to be authenticating to the Alltrails AWS account"
    echo "Please double-check your AWS access key and try again"
    echo
    echo "Expected AWS account number of $AWS_ACCOUNT, got $CURRENT_AWS_TARGET instead" 
    exit 1
fi

if [[ $(arch) == 'arm64' ]]; then
  echo "Hello there!  We're terribly sorry about this, but you seem to be running"
  echo "on one of the M1 macs, or some other non-x86-based system!"
  echo "Unfortuantely this 'local build process' script doesn't support this.  It will"
  echo "cheerfully build an ARM-compatible container, send it to EKS/k8s, which will"
  echo "promptly choke on it and start throwing inscrutable, hard to debug errors."
  echo "What you may be able to do is use this script to inform what a CI pipeline"
  echo "should do, then write/test/deploy that pipeline directly to test it."
  echo "Again, we are deeply sorry about the inconvenience, but we do wish you the"
  echo "very best of luck!"
  exit 1
fi


# Let's try to set a unique-ish namespace for local testing
if [ $# -eq 0 ]; then
    # namespaces must consist of lower case alphanumeric characters or '-', and must startand end with an alphanumeric
    # character (e.g. 'my-name',  or '123-abc', regex used for validation is '[a-z0-9]([-a-z0-9]*[a-z0-9])?')
    NAMESPACE=$(whoami | sed "s/[^[:alnum:]-]//g")
else
    NAMESPACE=$1
fi

export COMMIT_ID=$(git rev-parse --verify --short HEAD)
echo commit ID is $COMMIT_ID

# This updates your local ~/.kube/config file with authentication info
# for our test EKS cluster
aws eks update-kubeconfig \
    --profile at-interviews \
    --region us-west-2 \
    --name at-interviews-cluster

kubectl config \
    use-context \
    arn:aws:eks:us-west-2:310228935478:cluster/at-interviews-cluster

# Then we log in to the Elastic Container Registry (ECR) so we have an 
# AWS-accessible place to push the Docker container we're about to build...
aws ecr get-login-password \
    --profile at-interviews \
    --region us-west-2 \
    | docker login \
    --username AWS \
    --password-stdin \
    $AWS_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com

# Container gets built at this step.  Those tags are needed so the following
# 'docker push' step sends the container to the right ECR repo
docker build \
    --no-cache \
    --build-arg GIT_COMMIT=$COMMIT_ID \
    -t helloworld:$COMMIT_ID \
    -t $AWS_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/helloworld:$COMMIT_ID \
    .

# If we've tagged our container appropriately above, this should send the 
# container to ECR, where Kubernetes/Helm can pull it down
docker push \
    $AWS_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/helloworld:$COMMIT_ID

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
