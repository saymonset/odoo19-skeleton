 sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf

docker compose -f docker-compose.yaml down --remove-orphans
docker compose -f docker-compose.yaml up -d