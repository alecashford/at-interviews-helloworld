# Alec's Homework
Welcome!  If you're reading this readme, in all likelihood you are evaluating me (Alec) for the Build/Release Engineer role at AllTrails. This is my homework assignment deliverable, which I'd like to walk you through now.

The tools I use in my current role for for build pipelines include a mixture of AWS CodeBuild and Jenkins; however since AllTrails uses it, I took this as an opportunity to learn and try out CircleCI. The biggest challenge for me during this assignment, therefore, was learning the new tool. Fortunately, I found it user-friendly and pretty similar to other tools I am familiar with.

As a best-practice, I try to ensure that builds build the same way regardless of where they are run, be that your local machine or a CI host. CircleCI accommodated this design pattern beautifully, since it sets up a workspace for each run inside a fresh Docker container (the image for which you can define yourself!). As a result, I opted to develop a build env image (hosted on Dockerhub, [here](https://hub.docker.com/repository/docker/alecashford/at-build-env)), which I used both for local builds and for the build and deploy in CircleCI.

The build env image is based on CentOS and comes with all of the necessary dependencies to build and deploy this application pre-installed (I am including the Dockerfile in this repo, Build-Env-Dockerfile). Note that this implementation offers a possible solution to devs developing and building on M1 hardware. To build locally inside this dedicated build container, simply do the following:

```
# Pull the latest build env image from Dockerhub...
$ docker pull alecashford/at-build-env:latest

# cd into the at-interviews-helloworld repo, then run:
$ docker run \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.aws/credentials:/root/.aws/credentials \
  -v $PWD:$PWD \
  -w $PWD \
  -it \
  alecashford/at-build-env:latest \
  /bin/bash

# You're inside the build env container now...run local-deploy.sh, it should Just Work™
[root@294421fd81f9 at-interviews-helloworld]# ./local-deploy.sh
```

Another challenge I ran into initially was discovering that my user had initially not been set up with the appropriate permissions to deploy to the test Kubernetes cluster. My first clue that something was wrong came up shortly after I forked the repo and went through the initial local setup and run of the local-deploy.sh script, upon which I received this error:

`Error: Kubernetes cluster unreachable: the server has asked for the client to provide credentials`

Digging further, kubectl itself seemed unable to connect:

```
$ kubectl get svc
error: You must be logged in to the server (Unauthorized)
```

That led me to [this page](https://aws.amazon.com/premiumsupport/knowledge-center/eks-api-server-unauthorized-error/) from the EKS docs and [this StackOverflow](https://stackoverflow.com/questions/50791303/kubectl-error-you-must-be-logged-in-to-the-server-unauthorized-when-accessing), which said that initially, only the creator of an EKS cluster has the permissions to make calls to the Kubernetes API server using kubectl. Subsequent users must be explicitly added to the ConfigMap.

As a Kubernetes non-expert (to put it lightly), I wasn't sure whether I was doing something wrong, or if there was an underlying problem, but when I received identical errors in my dockerized build env and on CircleCI, that reinforced my theory. So, I reached back out to Alaina to confirm whether my IAM user has the needed permissions to interact with the API server, after which I was unblocked.

## How would I modify my pipeline to accommodate different environments?

The answer to this depends on the git branching model and development cycle, but for simplicity's sake I'll assume the use of a [git-flow-like](https://nvie.com/posts/a-successful-git-branching-model/) workflow with a develop and main branch.

This model works particularly well if you have a limited number of (or only one) test environments. In a nutshell, we would add logic to the .circleci/config.yml file to check which branch the commit that triggered the build was being merged into, and use that to control which env to deploy the build to. Merging to develop would automatically deploy the build to dev, merging to main would automatically deploy the build to prod.

Another model to look at would be the "trunk based development" paradigm wherein we only have one permanent branch (main), which is being continuously merged to and deployed to prod. There are some nice features of this model, but we would need more test envs than there were specified in the prompt, potentially one for each PR, to ensure that each commit, when merged, was fully qualified and tested.

# Hello World Sample App
Welcome!  If you're cloning this repo, in all likelihood you are starting the QA/Build/Release Engineer Homework assignment.  We're so happy that you've made it this far in the process!  By now you should have received a message from HR with login credentials to our Candidate AWS Environment, and the specifics of the Homework Assignment.  The document you're reading now (this README) is intended to help get you into the AWS environment, and that your account has all the permissions it needs to test locally, and actually complete the assignment.  

# Recommended Tooling (for local deployment/testing)
We recommend having the following tools to hand: 

[Docker](https://www.docker.com/products/docker-desktop)

[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

[Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/#install-with-homebrew-on-macos)

[Helm](https://helm.sh)

# AWS Console Access
You should have received a username and (temporary) password from HR.  With that, you can log into the [AWS Console](at-interviews.signin.aws.amazon.com/) and take a look around, if you are so inclined.  

# AWS API Access
Presuming you're on a Linux or MacOS machine, you can create/edit the file `~/.aws/credentials`.  Add a new section similar to the following, substituting the example values for the ones shared by HR: 
```
[at-interviews]
aws_access_key_id =  AKIA....
aws_secret_access_key = IKGkr....
```

To verify, you should now be able to run the command:
```
$ aws --profile at-interviews \
    sts get-caller-identity
```
This should output something similar to: 
```
{
    "UserId": "AKIA....",
    "Account": "310228935478",
    "Arn": "arn:aws:iam::310228935478:user/your_user_name_here"
}
```

# Manual Build/Deploy Steps
Our toy application is already able to be built, pushed, and deployed locally. We've got the particulars crammed into the `local-deploy.sh` script, but if you'd prefer a longer-form rundown of what's going on where, read on! 

## Build

Confirm all desired changes to the toy application are committed locally (not necessarily pushed), and then:
```
$ export COMMIT_ID=$(git rev-parse --verify --short HEAD) # This gives us a short, unique tag that we'll use when building/tagging the Docker image

```
```
$ docker build \
    --no-cache \
    --build-arg GIT_COMMIT=$COMMIT_ID \
    -t helloworld:$COMMIT_ID \
    -t 310228935478.dkr.ecr.us-west-2.amazonaws.com/helloworld:$COMMIT_ID \
    .
```

We should now have a local container built and able to be run locally 'in the usual fashion'.

## Login to external services
We'll need to authenticate to some of the external services in order to send our container on its merry way: 

Elastic Container Repository
```
$ aws ecr get-login-password \
    --region us-west-2 \
    | docker login \
    --username AWS \
    --password-stdin \
    310228935478.dkr.ecr.us-west-2.amazonaws.com
```

Elastic Kubernetes Service
```
aws eks update-kubeconfig \
    --region us-west-2 \
    --name at-interviews-cluster
```

# Push
```
$ docker push \
    310228935478.dkr.ecr.us-west-2.amazonaws.com/helloworld:$COMMIT_ID
```
Using the credentials above, this sends our container to ECR where Kubernetes can pull it down and actually deploy it in the next step.  

# Deploy
We're using Helm to abstract away as much of the complexity of Kubernetes as we possibly can.  Presuming our container is safely in ECR (above), deployment to Kubernetes and all the associated wiring should be as simple as: 
```
helm upgrade \
    --install \
    --namespace $(whoami) \
    --create-namespace \
    helloworld \
    --set image.tag=$COMMIT_ID \
    helm/helloworld
```
That should plug n' chug for a minute, then spit out some `kubectl` commands that will have an Internet Accessible URL™ serving up the toy application (it may take up to 5 minutes for DNS to propagate, FWIW).  And that is the manual deploy process, annotated.  You shouldn't need to run everything command-by-command, as that's what the `local-deploy.sh` script is for, but hopefully that gives you some context helpful to completing the homework assignment.  

