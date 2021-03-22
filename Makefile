OESS_VERSION=2.0.11
OESS_NETWORK=oess-network

container:
	docker build -f Dockerfile.dev --tag oess:${OESS_VERSION} .
dev:
	docker run -it \
	--env-file .env \
	--publish 8000:80 \
	--network ${OESS_NETWORK} \
	--mount type=bind,src=${PWD}/perl-lib/OESS/lib/OESS,dst=/usr/share/perl5/vendor_perl/OESS \
	--mount type=bind,src=${PWD}/frontend,dst=/usr/share/oess-frontend \
	--mount type=bind,src=${PWD}/perl-lib/OESS/share,dst=/usr/share/doc/perl-OESS-2.0.10/share \
	oess:${OESS_VERSION} /bin/bash