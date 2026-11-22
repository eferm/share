include .env
export SHARE_HOST

.PHONY: list publish unpublish server

list:
	./site.sh list

publish: server
	./site.sh publish "$(SITE)"

unpublish:
	./site.sh unpublish "$(SITE)"

# --wait: the reload needs Caddy's admin API up
server:
	docker compose up -d --wait
	docker compose exec web caddy reload --config /share/Caddyfile --adapter caddyfile
