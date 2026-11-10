-- Diagnóstico 01: tamanho das tabelas, índices existentes e uso de seq scan x index scan.
-- Somente leitura. Rodado com a aplicação original (commit 5394cf9), logo após as 3 medições da linha de base.
-- Como rodar: docker compose exec -T banco psql -U loja -d loja -f - < diagnostico/01-tabelas-e-indices.sql > diagnostico/01-tabelas-e-indices.txt

\echo '=== Versão e parâmetros relevantes do PostgreSQL ==='
SELECT version();
SELECT name, setting, unit
  FROM pg_settings
 WHERE name IN ('shared_buffers', 'work_mem', 'effective_cache_size', 'max_connections',
                'random_page_cost', 'max_parallel_workers_per_gather', 'jit')
 ORDER BY name;

\echo '=== Linhas e tamanho de cada tabela (dados + índices) ==='
SELECT c.relname                                         AS tabela,
       c.reltuples::bigint                               AS linhas_estimadas,
       pg_size_pretty(pg_relation_size(c.oid))           AS tamanho_dados,
       pg_size_pretty(pg_indexes_size(c.oid))            AS tamanho_indices,
       pg_size_pretty(pg_total_relation_size(c.oid))     AS tamanho_total
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
 ORDER BY pg_total_relation_size(c.oid) DESC;

\echo '=== Índices existentes ==='
SELECT tablename AS tabela, indexname AS indice, indexdef AS definicao
  FROM pg_indexes
 WHERE schemaname = 'public'
 ORDER BY tablename, indexname;

\echo '=== Seq scan x index scan acumulados desde a subida do banco (inclui as 3 medições da linha de base) ==='
SELECT relname        AS tabela,
       seq_scan,
       seq_tup_read   AS linhas_lidas_por_seq_scan,
       idx_scan,
       idx_tup_fetch  AS linhas_lidas_por_indice
  FROM pg_stat_user_tables
 ORDER BY seq_tup_read DESC;

\echo '=== Conexões abertas no banco desde a subida (cada conexão nova = um processo backend novo) ==='
SELECT datname, numbackends AS conexoes_ativas_agora, xact_commit AS transacoes_confirmadas,
       blks_read AS blocos_lidos_do_disco, blks_hit AS blocos_lidos_do_cache,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS taxa_acerto_cache_pct,
       temp_files AS arquivos_temporarios, pg_size_pretty(temp_bytes) AS bytes_temporarios,
       stats_reset
  FROM pg_stat_database
 WHERE datname = 'loja';

\echo '=== Distribuição dos pedidos por status (base do GET /pedidos) ==='
SELECT status, count(*) AS pedidos FROM pedidos GROUP BY status ORDER BY status;

\echo '=== Tamanho médio da coluna observacoes (trafegada por SELECT * em pedidos) ==='
SELECT round(avg(octet_length(observacoes))) AS bytes_medios_observacoes,
       round(avg(octet_length(status) + 8 + 4 + 4)) AS bytes_medios_demais_colunas_aprox
  FROM pedidos;

\echo '=== Quantas consultas o GET /clientes/:id/pedidos dispara (1 + 1 + N pedidos + M itens) ==='
SELECT c.id AS cliente_id,
       count(DISTINCT p.id)                         AS pedidos,
       count(i.id)                                  AS itens,
       2 + count(DISTINCT p.id) + count(i.id)       AS consultas_disparadas_pela_rota
  FROM clientes c
  LEFT JOIN pedidos p ON p.cliente_id = c.id
  LEFT JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE c.id IN (7, 42, 31337, 99999)
 GROUP BY c.id
 ORDER BY c.id;

\echo '=== Média de pedidos e itens por cliente (todos os clientes) ==='
SELECT round(avg(pedidos), 2) AS media_pedidos_por_cliente,
       round(avg(itens), 2)   AS media_itens_por_cliente,
       round(avg(2 + pedidos + itens), 2) AS media_consultas_por_requisicao,
       max(2 + pedidos + itens) AS maximo_consultas_por_requisicao
  FROM (
    SELECT c.id,
           count(DISTINCT p.id) AS pedidos,
           count(i.id)          AS itens
      FROM clientes c
      LEFT JOIN pedidos p ON p.cliente_id = c.id
      LEFT JOIN itens_pedido i ON i.pedido_id = p.id
     GROUP BY c.id
  ) por_cliente;
