# Diagnóstico da aplicação original

Evidências coletadas com a aplicação original no ar (commit `5394cf9`), logo depois das 3 medições da linha de base. Todos os scripts são somente leitura: não alteram dados, índices nem configuração.

| Arquivo | O que mede | Como foi gerado |
| --- | --- | --- |
| [01-tabelas-e-indices.sql](01-tabelas-e-indices.sql) → [.txt](01-tabelas-e-indices.txt) | Tamanho das tabelas, índices existentes, seq scan x index scan acumulados, parâmetros do PostgreSQL, consultas disparadas por `GET /clientes/:id/pedidos` | `docker compose exec -T banco psql -X -U loja -d loja -f - < diagnostico/01-tabelas-e-indices.sql > diagnostico/01-tabelas-e-indices.txt` |
| [02-explain-consultas.sql](02-explain-consultas.sql) → [.txt](02-explain-consultas.txt) | `EXPLAIN (ANALYZE, BUFFERS)` de cada consulta de `api/src/rotas.js`, com o banco sem carga | `docker compose exec -T banco psql -X -e -U loja -d loja -f - < diagnostico/02-explain-consultas.sql > diagnostico/02-explain-consultas.txt` |
| [03-custo-conexao.js](03-custo-conexao.js) → [.txt](03-custo-conexao.txt) | Tempo de `SELECT 1` abrindo conexão nova (como o `db.js` original) x conexão reutilizada, 200 vezes cada | `docker compose exec -T api node - < diagnostico/03-custo-conexao.js > diagnostico/03-custo-conexao.txt` |
| [04-volume-de-log.txt](04-volume-de-log.txt) | Volume do log da API, que imprime o corpo de cada resposta | `docker compose logs --no-log-prefix api` + `awk` (comando no próprio arquivo) |

> Os tempos do `EXPLAIN ANALYZE` são de uma consulta isolada, com o banco ocioso. Sob a carga do k6 (20 usuários, banco com 1 CPU) as consultas disputam a mesma CPU e os tempos por requisição em `resultados/` são muito maiores.

## Achados

### A1. Nenhum índice além das chaves primárias
- Só existem `clientes_pkey`, `produtos_pkey`, `pedidos_pkey` e `itens_pedido_pkey` (01, "Índices existentes").
- `itens_pedido` (1,5 milhão de linhas) teve **1.823 seq scans**, **1.314.000.000 linhas lidas** e **0 index scans** desde a subida do banco; `pedidos` teve 946 seq scans e 225.500.000 linhas lidas (01, "Seq scan x index scan").
- Consultas afetadas (02):
  - `pedidos WHERE cliente_id = 42`: `Parallel Seq Scan on pedidos`, 166.665 linhas descartadas por worker, 59,9 ms para devolver 5 linhas.
  - `itens_pedido WHERE pedido_id = …`: `Parallel Seq Scan on itens_pedido`, 499.999 linhas descartadas por worker, 121,4 ms para devolver 2 linhas.
  - `clientes WHERE lower(email) = …`: `Seq Scan on clientes`, 99.999 linhas descartadas, 27,7 ms para 1 linha. Um índice comum em `email` não serviria, porque a consulta compara `lower(email)`.
  - `produtos WHERE nome ILIKE '%cadeira%'`: `Seq Scan on produtos`, 22,1 ms. `ILIKE` com `%` no começo não usa índice B-tree.

### A2. `GET /clientes/:id/pedidos` faz N+1 consultas (rota com 20% da carga)
- `rotas.js` faz 1 consulta do cliente, 1 dos pedidos, **1 por pedido** (itens) e **1 por item** (produto), em sequência.
- Média de **22 consultas por requisição**, máximo de 32 (01, "Média de pedidos e itens por cliente": 5 pedidos e 15 itens por cliente).
- Cada consulta de itens sozinha faz um seq scan de 1,5 milhão de linhas (A1): ~5 seq scans de `itens_pedido` por requisição. É a rota mais lenta da linha de base (mediana por rota acima de 19 s nas 3 execuções em `resultados/`).

### A3. Uma conexão TCP nova por consulta
- `db.js` cria `new Client()`, conecta e desconecta a cada consulta. No PostgreSQL, cada conexão nova é um processo novo no servidor.
- Medido dentro do container da API: `SELECT 1` com conexão nova tem **mediana de 6,361 ms**; com conexão reutilizada, **0,199 ms** (03). Em `GET /clientes/:id/pedidos`, com 22 consultas em média, isso soma o custo de conexão 22 vezes por requisição.

### A4. `GET /pedidos`: contagem completa + OFFSET grande + ordenação em disco
- `count(*) WHERE status = 'pago'` lê a tabela inteira: 163,6 ms (02).
- A página 1000 (`OFFSET 19980`) ordena 300 mil pedidos `pago` e o sort não cabe em `work_mem` (4 MB, 01): `Sort Method: external merge  Disk: 32632kB`, **612,8 ms** (02). A página 1 leva 115,1 ms.
- O banco acumulou **101 arquivos temporários / 2008 MB** em disco desde a subida (01, `pg_stat_database`).
- `SELECT *` traz `observacoes`, que tem em média **274 bytes**, contra ~22 bytes das demais colunas, e não é usada na resposta (01).

### A5. `GET /relatorios/vendas-por-dia`: filtro que impede índice e agregação feita no Node.js
- O filtro `criado_em::date BETWEEN …` aplica uma função na coluna; o plano faz `Parallel Seq Scan on pedidos` e `Parallel Seq Scan on itens_pedido` inteiros: 446,0 ms (02).
- O banco manda **12.945 linhas** (com 3468 kB só de `observacoes`, que não é usada) para o Node.js agrupar por dia (02). A agregação poderia ser feita no banco com `GROUP BY`.

### A6. `GET /relatorios/top-produtos`: agregação de 1,35 milhão de itens a cada chamada
- Hash join de `itens_pedido` x `pedidos` x `produtos` com 450.000 linhas por worker (3 processos) e agregação: **1.429,7 ms** com o banco ocioso (02). Sob carga, 2 das 3 execuções da linha de base tiveram timeout nessa rota.
- O resultado depende só de dados históricos e não de parâmetros além do `limite`.

### A7. Log com o corpo inteiro de cada resposta
- `server.js` faz `console.log(JSON.stringify({..., resposta: corpo}))` em toda resposta: média de **1160 bytes por requisição**, maior linha com 6324 bytes (04).
- Na vazão atual (menos de 3 req/s) o volume é pequeno (0,9 MiB no total). O custo cresce com a vazão: deve pesar mais depois que os gargalos do banco forem resolvidos. Prioridade baixa no diagnóstico atual.

### A8. Configuração do PostgreSQL no padrão
- `shared_buffers` = 16384 × 8 kB (128 MB), `work_mem` = 4 MB, `random_page_cost` = 4, `jit` = on (01). Taxa de acerto do cache: 81,96% (01).
- O banco ficou entre 97% e 98% de CPU média nas 3 medições (`resultados/*/recursos.txt`): o gargalo é a CPU do banco, consumida pelos seq scans de A1–A6, e não a API (6% a 7% de CPU).

## Ordem de ataque proposta (maior impacto primeiro)

1. A3 — pool de conexões (`api/src/db.js`)
2. A1 — índices (`banco/03-indices.sql`)
3. A2 — eliminar o N+1 em `GET /clientes/:id/pedidos`
4. A4/A5/A6 — reescrever consultas dos relatórios e da paginação, sem `SELECT *`
5. A7/A8 — log e parâmetros do PostgreSQL, se ainda fizer diferença
