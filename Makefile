# Pintasan operasional. Jalankan dari root repo (/opt/devops).
SHELL := /bin/bash
.DEFAULT_GOAL := help
LAYERS := 01-infra 02-monitoring 03-services 00-gateway

help: ## daftar perintah
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

network: ## buat network global (sekali)
	@docker network inspect global-gateway-net >/dev/null 2>&1 || docker network create global-gateway-net

up: network ## nyalakan semua layer infra berurutan (bukan aplikasi)
	@for l in $(LAYERS); do echo "== $$l"; docker compose -f $$l/docker-compose.yml up -d; done

down: ## matikan semua layer infra (data di volume aman)
	@for l in 00-gateway 03-services 02-monitoring 01-infra; do docker compose -f $$l/docker-compose.yml down; done

ps: ## status semua container
	@docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | sort

logs: ## log satu container: make logs C=infra_postgres
	@docker logs -f --tail 200 $(C)

nginx-test: ## cek sintaks config nginx gateway
	@docker exec global_gateway nginx -t

nginx-reload: nginx-test ## reload nginx tanpa downtime
	@docker exec global_gateway nginx -s reload && echo "reloaded"

cert: ## terbitkan SSL: make cert D="wa.example.com www.wa.example.com"
	@./scripts/issue-cert.sh $(D)

app-db: ## buat database+user aplikasi: make app-db A=wa_gateway
	@./scripts/create-app-db.sh $(A)

deploy: ## deploy/update aplikasi: make deploy A=wa-gateway
	@./scripts/deploy-app.sh $(A)

backup: ## backup postgres sekarang
	@./scripts/backup-postgres.sh && tail -3 scripts/logs/backup.log

pg: ## psql ke postgres sebagai superuser
	@docker exec -it -e PGPASSWORD="$$(grep ^POSTGRES_PASSWORD= 01-infra/.env | cut -d= -f2-)" infra_postgres psql -U postgres

pgbouncer-stats: ## SHOW POOLS di pgbouncer
	@docker exec -it -e PGPASSWORD="$$(grep ^PGBOUNCER_AUTH_PASSWORD= 01-infra/.env | cut -d= -f2-)" infra_postgres \
	  psql -h infra_pgbouncer -p 5432 -U pgbouncer_auth pgbouncer -c 'SHOW POOLS;' -c 'SHOW STATS;'

slow-queries: ## 15 query terlambat (pg_stat_statements)
	@docker exec -e PGPASSWORD="$$(grep ^POSTGRES_PASSWORD= 01-infra/.env | cut -d= -f2-)" infra_postgres psql -U postgres -c \
	  "select calls, round(mean_exec_time::numeric,1) ms, rows, left(query,90) q from pg_stat_statements order by mean_exec_time desc limit 15;"

secrets-check: ## pastikan tidak ada secret yang ter-track git
	@! git ls-files | grep -E '(^|/)\.env$$|\.key$$|privkey|\.pem$$|userlist\.txt$$' || (echo "!! secret ter-track di atas" && exit 1)
	@echo "ok: tidak ada secret ter-track"

.PHONY: help network up down ps logs nginx-test nginx-reload cert app-db deploy backup pg pgbouncer-stats slow-queries secrets-check
