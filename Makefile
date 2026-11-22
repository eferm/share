include .env
export SHARE_HOST

.PHONY: list publish unpublish server

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
