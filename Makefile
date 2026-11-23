include .env
export SHARE_HOST

.PHONY: help list publish unpublish server

help:
	@echo 'make list                  every folder in sites/ with its source and status'
	@echo 'make publish SITE=<dir>    publish a folder, or update its site'
	@echo 'make unpublish SITE=<dir>  take a folder'\''s site offline, keeping its URL'
	@echo 'make server                start the container or reload the Caddyfile'

list:
	./sites.sh list

publish: server
	./sites.sh publish "$(SITE)"

unpublish:
	./sites.sh unpublish "$(SITE)"

# --wait: the reload needs Caddy's admin API up
server:
	docker compose up -d --wait
	docker compose exec web caddy reload --config /share/Caddyfile --adapter caddyfile
