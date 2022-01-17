 #!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
containerIds=$(docker ps -q)

echo "docker system df"
docker system df
echo ""

for container in $containerIds
do

    workspaceSpace=$(docker exec $container sh -c "du -sh /home/jenkins/workspace" 2> /dev/null)
    if [[ $? -eq 0 ]]; then
        echo "Container: $container"
        echo "$workspaceSpace"
        echo ""
    fi

done