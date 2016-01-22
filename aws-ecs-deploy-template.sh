region=$(get_octopusvariable "Region")
aws configure set region $region

cluster=$(get_octopusvariable "Cluster")
service=$(get_octopusvariable "Service")
taskDefinition=$(get_octopusvariable "TaskDefinition") 
dockerUser=$(get_octopusvariable "DockerRepoUser")
dockerPassword=$(get_octopusvariable "DockerRepoPassword")
dockerRepo=$(get_octopusvariable "DockerRepo")
dockerBuildTag=$(get_octopusvariable "DockerBuildTag")

i="0"
echo "Checking if the Octopus Build image is registered in the Docker Hub repository ..."
while [ $i -lt 10 ] && [ $(curl -s -m 2 --retry 3 --retry-delay 2 --retry-max-time 10 --user $dockerUser:$dockerPassword https://index.docker.io/v1/repositories/$dockerRepo/tags | jq ".[].name" | grep -c "$dockerBuildTag") -eq 0 ] ;
do
    echo "Octopus Build image is not registered yet, sleeping 30 seconds and going to check back again (-_-)zzz"
    i=$[$i+1]
    sleep 30
done

if [ $i -eq 6 ] ; then
    echo "Error!, Could not find the Octopus Build image ($dockerBuildTag) in the Docker Hub registry, deployment to AWS ECS will not continue :(."
    exit 1
fi

echo "Getting Active task defintion, and replacing the image name with the new one ..."
taskDefinitionBody=$(aws ecs describe-task-definition --task-definition $taskDefinition | jq '.taskDefinition.containerDefinitions' | jq ".[].image = \"$dockerRepo:$dockerBuildTag\"")

echo "Registering new task definition revision containing the generated image ..."
aws ecs register-task-definition --family $taskDefinition --container-definitions "$taskDefinitionBody"

echo "Updating ECS service ..."
aws ecs update-service --cluster $cluster --service $service --task-definition $taskDefinition

sleep 10
aws ecs wait services-stable --cluster $cluster --services $service

echo "Application successfully deployed"