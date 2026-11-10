-- Diagnóstico 02: EXPLAIN (ANALYZE, BUFFERS) de cada consulta que a API original executa (api/src/rotas.js).
-- Somente leitura. Os parâmetros ($1, $2...) foram trocados por valores usados no contrato ou na carga.
-- Rodado com o banco sem carga, então os tempos aqui são de UMA consulta isolada, não de requisições sob carga.
-- Como rodar: docker compose exec -T banco psql -X -e -U loja -d loja -f - < diagnostico/02-explain-consultas.sql > diagnostico/02-explain-consultas.txt

\echo ''
\echo '############ GET /clientes/:id  (peso 25%) ############'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM clientes WHERE id = 500;

\echo ''
\echo '############ GET /clientes?email=  (peso 15%) ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM clientes WHERE lower(email) = lower('cliente3@exemplo.com') ORDER BY id;

\echo ''
\echo '############ GET /clientes/:id/pedidos  (peso 20%) ############'
\echo '--- consulta 1: o cliente ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM clientes WHERE id = 42;
\echo '--- consulta 2: os pedidos do cliente ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos WHERE cliente_id = 42 ORDER BY criado_em DESC, id DESC;
\echo '--- consulta 3 (repetida 1 vez POR PEDIDO): os itens de um pedido ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM itens_pedido WHERE pedido_id = (SELECT min(id) FROM pedidos WHERE cliente_id = 42) ORDER BY id;
\echo '--- consulta 4 (repetida 1 vez POR ITEM): o produto de um item ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE id = 10061;

\echo ''
\echo '############ GET /pedidos?status=&pagina=  (peso 15%) ############'
\echo '--- consulta 1: contagem do status ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
\echo '--- consulta 2: página 1 ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 0;
\echo '--- consulta 2: página 1000 (maior página sorteada pela carga) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;

\echo ''
\echo '############ GET /produtos/busca?q=  (peso 15%) ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM produtos WHERE nome ILIKE '%' || 'cadeira' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM produtos WHERE nome ILIKE '%' || 'modelo 12' || '%' ORDER BY nome, id LIMIT 20;

\echo ''
\echo '############ GET /relatorios/vendas-por-dia  (peso 8%) ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos
  FROM pedidos p
  JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em::date BETWEEN '2024-01-01'::date AND '2024-01-07'::date
   AND p.status <> 'cancelado';
\echo '--- volume de linhas e bytes que essa consulta manda para o Node.js agrupar ---'
SELECT count(*) AS linhas_enviadas_para_a_api,
       pg_size_pretty(sum(octet_length(p.observacoes))::bigint) AS bytes_so_de_observacoes
  FROM pedidos p
  JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em::date BETWEEN '2024-01-01'::date AND '2024-01-07'::date
   AND p.status <> 'cancelado';

\echo ''
\echo '############ GET /relatorios/top-produtos  (peso 2%) ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT pr.id, pr.nome, pr.categoria,
       sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i
  JOIN pedidos p ON p.id = i.pedido_id
  JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria
 ORDER BY receita_centavos DESC, pr.id
 LIMIT 10;
