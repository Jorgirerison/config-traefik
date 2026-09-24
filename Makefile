server = ubuntu@my-first-vps-with-docker.duckdns.org
project_path = $(shell basename $(shell pwd))

.PHONY: rsync setup deploy ps logs

# Não envia os certificados locais nem o .git para a VPS
rsync:
	rsync -azv --exclude .git --exclude letsencrypt . $(server):$(project_path)

# First run for setup docker compose and traefik
setup: rsync
	ssh $(server) "cd ~/$(project_path) &&\
		mkdir -p letsencrypt &&\
		touch letsencrypt/acme.json &&\
		chmod 600 letsencrypt/acme.json &&\
		(docker network inspect traefik >/dev/null 2>&1 || docker network create traefik) &&\
		docker compose up -d"

# Recria só o que mudou, sem derrubar tudo antes
deploy: rsync
	ssh $(server) "cd $(project_path) && docker compose up -d"

ps:
	ssh $(server) "cd $(project_path) && docker compose ps"

logs:
	ssh $(server) "cd $(project_path) && docker compose logs --tail 100 traefik"
