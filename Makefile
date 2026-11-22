include .env
export SHARE_HOST

.PHONY: list publish unpublish server

list:
	@find sites -mindepth 2 -maxdepth 2 -name .source -exec grep -H . {} + \
	  | sed 's|^sites/\([^/]*\)/\.source:|\1 -> |' | sort

publish: server
	./deploy.sh publish "$(SITE)"

unpublish:
	./deploy.sh unpublish "$(SITE)"

# --wait: the reload needs Caddy's admin API up
server:
	docker compose up -d --wait
	docker compose exec web caddy reload --config /share/Caddyfile --adapter caddyfile
