 #!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
containerIds=$(docker ps -q)

echo "docker system df"
docker system df

reclaimableSpace=$(docker system df | grep Images | awk '{print $5}' | sed 's/GB//')
if [[ $(echo "$reclaimableSpace > 10" | bc -l) ]]; then
    echo "$reclaimableSpace of space can be reclaimed with docker system prune"
fi

echo "Disk space available on each docker container"
df -h | grep overlay | head -n 1 | awk '{print $4}'
echo "----------"

for container in $containerIds
do

    echo "Container: $container"
    workspaceSpace=$(docker exec $container sh -c "du -sh /home/jenkins/workspace")
    echo $workspaceSpace
    workspaceSpaceNumber=$(echo $workspaceSpace | awk '{print $1}')
    if [[ $workspaceSpaceNumber -gt 3000000 ]]; then
        echo "Container $container's workspace directory is using $workspaceSpaceNumber in space. Could use some clearing up"
    fi

done