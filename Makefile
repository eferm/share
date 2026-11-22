include .env
export SHARE_HOST

.PHONY: publish unpublish server

publish: server
	./site.sh publish "$(SITE)"

unpublish:
	./site.sh unpublish "$(SITE)"

# --wait: the reload needs Caddy's admin API up
server:
	docker compose up -d --wait
	docker compose exec web caddy reload --config /share/Caddyfile --adapter caddyfile
