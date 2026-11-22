include .env
export SHARE_HOST

.PHONY: publish unpublish server

# Publish a copy of SITE (a built folder with index.html) at its secret URL, creating the URL on first
# publish, and bring the server up to date
publish: server
	./site.sh publish "$(SITE)"

# Take SITE offline; its source folder is untouched
unpublish:
	./site.sh unpublish "$(SITE)"

# Start the Caddy container, or apply changes to compose.yaml and the Caddyfile without downtime.
# --wait holds until the healthcheck passes, so Caddy's admin API is up for the reload.
server:
	docker compose up -d --wait
	docker compose exec web caddy reload --config /share/Caddyfile --adapter caddyfile
