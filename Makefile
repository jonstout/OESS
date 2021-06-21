OESS_VERSION=2.0.11
<<<<<<< Updated upstream
OESS_NETWORK=oess-network
=======
OESS_NETWORK=testenv-nso-arroyo-5.5.1-jonstout
>>>>>>> Stashed changes

container:
	docker build -f Dockerfile.dev --tag oess:${OESS_VERSION} .
dev:
	docker run -it \
	--rm \
	--env-file .env \
	--publish 8000:80 \
	--network ${OESS_NETWORK} \
	--mount type=bind,src=${PWD}/perl-lib/OESS/lib/OESS,dst=/usr/share/perl5/vendor_perl/OESS \
	--mount type=bind,src=${PWD}/frontend,dst=/usr/share/oess-frontend \
	--mount type=bind,src=${PWD}/perl-lib/OESS/share,dst=/usr/share/doc/perl-OESS-2.0.10/share \
	oess:${OESS_VERSION} /bin/bash

start-nso-testbed:
	docker stack deploy --compose-file docker-compose.yml oess-nso

populate-nso-testbed:
	docker exec -t $$(docker ps | grep "nso:5.3" | awk '{print $$1}') /bin/bash -lc 'echo -e "configure\n load merge /tmp/nso/devices.txt\n commit" | ncs_cli --stop-on-error -u admin'
	docker exec -t $$(docker ps | grep "nso:5.3" | awk '{print $$1}') /bin/bash -lc 'echo -e "request devices fetch-ssh-host-keys" | ncs_cli --stop-on-error -u admin'
	docker exec -t $$(docker ps | grep "nso:5.3" | awk '{print $$1}') /bin/bash -lc 'echo -e "request devices sync-from" | ncs_cli --stop-on-error -u admin'
	docker exec -t $$(docker ps | grep "nso:5.3" | awk '{print $$1}') /bin/bash -lc 'echo -e "configure\n load merge /tmp/nso/interfaces.txt\n commit" | ncs_cli --stop-on-error -u admin'
	docker exec -t $$(docker ps | grep "nso:5.3" | awk '{print $$1}') /bin/bash -lc 'echo -e "configure\n load merge /tmp/nso/resource-pool-init.xml\n commit" | ncs_cli --stop-on-error -u admin'
