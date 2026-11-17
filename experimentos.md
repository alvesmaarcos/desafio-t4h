# Experimentos

Uma linha por ideia aplicada. Todos os números saem dos arquivos gerados por `scripts/medir.sh` em `resultados/`, sem edição.

**Como comparar:** cada mudança roda 3 vezes com o mesmo rótulo. Na tabela vai a **mediana das 3 execuções** de cada métrica, tirada dos `resumo.txt` e `recursos.txt` de cada pasta. O **antes** de cada mudança é a **mudança anterior** (o antes da primeira é a linha de base).

**Parâmetros de todas as medições:** `VUS=20`, `DURACAO=60s`, `AQUECIMENTO=15s`, `SEMENTE=42` (registrados em `contexto.txt`). Limites dos containers: `api` 0,5 CPU / 256 MB e `banco` 1 CPU / 512 MB, salvo quando a mudança disser o contrário.

## Resumo

| # | Mudança | Status | Antes | req/s antes → depois | p95 antes → depois | CPU média banco antes → depois | Memória média api antes → depois | Conclusão |
|---|---|---|---|---|---|---|---|---|
| 00 | Linha de base (commit `45486c6`) | — | — | 2.67 | 24790.3 ms | 97.3% | 75.2 MiB | Ponto de partida |
| 01 | Pool de conexões (commit `f75f9c4`) | Aplicada e medida | 00 | 2.67 → 3.13 | 24790.3 ms → 22544.1 ms | 97.3% → 98.4% | 75.2 MiB → 32.5 MiB | Ganho pequeno; o gargalo continua na CPU do banco |
| 02 | Índices secundários e trigramas (commit `d07be10`) | Aplicada e medida | 01 | 3.13 → 12.84 | 22544.1 ms → 6381.4 ms | 98.4% → 97.6% | 32.5 MiB → 87.0 MiB | Vazão quadruplicou e mediana caiu de 1603,5 ms para 302,5 ms; CPU do banco segue saturada pelo N+1 e pelos relatórios |
| 03 | Eliminação do N+1 em `/clientes/:id/pedidos` (commit `2276929`) | Aplicada e medida | 02 | 12.84 → 12.66 | 6381.4 ms → 4836.8 ms | 97.6% → 96.7% | 87.0 MiB → 41.4 MiB | p95 geral caiu de 6381,4 para 4836,8 ms e a mediana da rota `pedidos-do-cliente` caiu de 2794,5 para 1316,4 ms; vazão total segue limitada na CPU do banco pelos relatórios |
| 04 | Projeção de colunas e agregação SQL em `vendas-por-dia` (commit `56b1d5f`) | Aplicada e medida | 03 | 12.66 → 22.44 | 4836.8 ms → 1655.7 ms | 96.7% → 99.7% | 41.4 MiB → 27.2 MiB | Vazão subiu para 22,44 req/s e p95 caiu para 1655,7 ms; `top-produtos` (mediana de 13797,1 ms) passa a ser o principal consumidor da CPU do banco |
| 05 | Materialized View `mv_top_produtos` (commit `c7aa489`) | Aplicada e medida | 04 | 22.44 → 144.74 | 1655.7 ms → 398.7 ms | 99.7% → 97.9% | 27.2 MiB → 29.5 MiB | Vazão saltou de 22,44 para 144,74 req/s, p95 caiu para 398,7 ms, p99 caiu de 12045,5 para 504,1 ms e memória do banco caiu de 445,4 para 347,6 MiB |
| 06 | Remoção do log do corpo da resposta em `server.js` (commit `b8affc2`) | Aplicada, sem ganho | 05 | 144.74 → 147.08 | 398.7 ms → 398.9 ms | 97.9% → 97.8% | 29.5 MiB → 30.0 MiB | Sem ganho relevante de vazão ou latência (variação dentro do ruído); CPU da API recuou de 13,4% para 12,6%, pois o teto do sistema continua sendo 1,0 CPU do banco |

## 00 · Linha de base

- **Commit:** `45486c6` (aplicação como veio)
- **Pastas:**
  - [20261110-160054-00-linha-de-base](resultados/20261110-160054-00-linha-de-base/)
  - [20261110-160250-00-linha-de-base](resultados/20261110-160250-00-linha-de-base/)
  - [20261110-160435-00-linha-de-base](resultados/20261110-160435-00-linha-de-base/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** |
|---|---|---|---|---|
| Requisições/s | 2.79 | 2.61 | 2.67 | **2.67** |
| Tempo de resposta: mediana | 1298.6 ms | 1302.4 ms | 1182.2 ms | **1298.6 ms** |
| Tempo de resposta: p95 | 23966.7 ms | 24790.3 ms | 25051.1 ms | **24790.3 ms** |
| Tempo de resposta: p99 | 25301.1 ms | 27952.7 ms | 29013.6 ms | **27952.7 ms** |
| Erros | 0.00% | 0.52% | 0.55% | **0.52%** |
| CPU média banco | 97.1% | 98.0% | 97.3% | **97.3%** |
| Memória média banco | 401.6 MiB | 405.7 MiB | 404.7 MiB | **404.7 MiB** |
| CPU média api | 6.8% | 6.2% | 6.3% | **6.3%** |
| Memória média api | 32.8 MiB | 75.7 MiB | 75.2 MiB | **75.2 MiB** |

## 01 · Pool de conexões

- **Problema (diagnóstico):** `api/src/db.js` abre e fecha uma conexão a cada consulta. `SELECT 1` com conexão nova: mediana 6,361 ms; com conexão reutilizada: 0,199 ms ([diagnostico/03-custo-conexao.txt](diagnostico/03-custo-conexao.txt)). `GET /clientes/:id/pedidos` faz em média 22 consultas por requisição ([diagnostico/01-tabelas-e-indices.txt](diagnostico/01-tabelas-e-indices.txt)).
- **Hipótese:** trocar a conexão nova por consulta por um `pg.Pool` deve aumentar as requisições/s e reduzir o p95 geral, porque cada consulta deixa de pagar o handshake e a criação de um processo novo no PostgreSQL.
- **Fontes:**
  - node-postgres. *Pooling*. https://node-postgres.com/features/pooling
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 52.2. How Connections Are Established*. https://www.postgresql.org/docs/16/connect-estab.html
- **Mudança:** commit `f75f9c4`, só em `api/src/db.js` (`new Client()` por consulta → `new Pool()` com a configuração padrão do `pg`)
- **Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta)
- **Pastas:**
  - [20261110-171233-01-pool-conexoes](resultados/20261110-171233-01-pool-conexoes/)
  - [20261110-171716-01-pool-conexoes](resultados/20261110-171716-01-pool-conexoes/)
  - [20261110-172047-01-pool-conexoes](resultados/20261110-172047-01-pool-conexoes/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** | Antes (00) |
|---|---|---|---|---|---|
| Requisições/s | 3.16 | 3.13 | 3.10 | **3.13** | 2.67 |
| Tempo de resposta: mediana | 1493.8 ms | 1604.7 ms | 1603.5 ms | **1603.5 ms** | 1298.6 ms |
| Tempo de resposta: p95 | 21947.0 ms | 22544.1 ms | 23407.0 ms | **22544.1 ms** | 24790.3 ms |
| Tempo de resposta: p99 | 26808.2 ms | 27404.7 ms | 27160.9 ms | **27160.9 ms** | 27952.7 ms |
| Erros | 0.00% | 0.00% | 0.00% | **0.00%** | 0.52% |
| CPU média banco | 95.6% | 98.6% | 98.4% | **98.4%** | 97.3% |
| Memória média banco | 405.4 MiB | 411.8 MiB | 399.0 MiB | **405.4 MiB** | 404.7 MiB |
| CPU média api | 5.9% | 5.0% | 5.8% | **5.8%** | 6.3% |
| Memória média api | 28.5 MiB | 33.6 MiB | 32.5 MiB | **32.5 MiB** | 75.2 MiB |

**Conclusão:**
- As requisições/s subiram (2.67 → 3.13) e o p95 caiu (24790.3 → 22544.1 ms). Mesmo a pior execução de 01 (3.10 req/s) ficou acima da melhor da linha de base (2.79 req/s).
- A mediana geral do tempo de resposta subiu (1298.6 → 1603.5 ms) porque a CPU do banco continuou saturada (97.3% → 98.4%) devido às leituras sequenciais de tabelas inteiras ([diagnostico/README.md](diagnostico/README.md), achado A1).

## 02 · Índices secundários e de trigramas no banco

- **Problema (diagnóstico):** o banco original possui apenas os índices das chaves primárias ([diagnostico/01-tabelas-e-indices.txt](diagnostico/01-tabelas-e-indices.txt)). As buscas por `lower(email)`, `pedidos.cliente_id`, `pedidos.status`, `itens_pedido.pedido_id` e `produtos.nome ILIKE '%termo%'` fazem *Sequential Scans* em tabelas de 20 mil a 1,5 milhão de linhas ([diagnostico/02-explain-consultas.txt](diagnostico/02-explain-consultas.txt)).
- **Hipótese:** criar índices B-Tree (funcionais, compostos ordenados e com `INCLUDE`) e um índice GIN com `pg_trgm` em `banco/03-indices.sql` deve reduzir drasticamente a mediana e o p95 gerais e multiplicar as requisições/s, substituindo varreduras completas de tabela por *Index Scans* e *Index-Only Scans*.
- **Fontes:**
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.1. Indexes: Introduction*. https://www.postgresql.org/docs/16/indexes-intro.html
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.7. Indexes on Expressions*. https://www.postgresql.org/docs/16/indexes-expressional.html
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.4. Indexes and ORDER BY*. https://www.postgresql.org/docs/16/indexes-ordering.html
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, F.35. pg_trgm*. https://www.postgresql.org/docs/16/pgtrgm.html
- **Mudança:** commit `d07be10`, adicionando `banco/03-indices.sql`
- **Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta)
- **Pastas:**
  - [20261116-231140-02-indices-banco](resultados/20261116-231140-02-indices-banco/)
  - [20261116-231312-02-indices-banco](resultados/20261116-231312-02-indices-banco/)
  - [20261116-231444-02-indices-banco](resultados/20261116-231444-02-indices-banco/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** | Antes (01) |
|---|---|---|---|---|---|
| Requisições/s | 12.01 | 13.21 | 12.84 | **12.84** | 3.13 |
| Tempo de resposta: mediana | 358.0 ms | 302.5 ms | 301.0 ms | **302.5 ms** | 1603.5 ms |
| Tempo de resposta: p95 | 6848.2 ms | 6381.4 ms | 6197.0 ms | **6381.4 ms** | 22544.1 ms |
| Tempo de resposta: p99 | 14396.7 ms | 11807.1 ms | 14242.9 ms | **14242.9 ms** | 27160.9 ms |
| Erros | 0.00% | 0.00% | 0.00% | **0.00%** | 0.00% |
| CPU média banco | 95.9% | 97.6% | 98.1% | **97.6%** | 98.4% |
| Memória média banco | 415.3 MiB | 411.9 MiB | 419.8 MiB | **415.3 MiB** | 405.4 MiB |
| CPU média api | 15.8% | 15.6% | 15.4% | **15.6%** | 5.8% |
| Memória média api | 48.8 MiB | 88.4 MiB | 87.0 MiB | **87.0 MiB** | 32.5 MiB |

**Conclusão:**
- As requisições/s quadruplicaram (3.13 → 12.84), a mediana geral caiu de 1603.5 ms para 302.5 ms, e o p95 geral caiu de 22544.1 ms para 6381.4 ms.
- Por rota (na execução `20261116-231444-02-indices-banco`): `cliente` caiu para mediana de 106.2 ms, `cliente-por-email` para 107.1 ms, `busca-produtos` para 195.5 ms, `pedidos-por-status` para 693.2 ms e `pedidos-do-cliente` para 2485.4 ms.
- A CPU do banco seguiu saturada em 97.6% porque: (1) `pedidos-do-cliente` (mediana de 2485.4 ms) ainda executa em média 22 consultas sequenciais por chamada (N+1); (2) `vendas-por-dia` (mediana de 2898.9 ms) aplica `criado_em::date` no filtro `WHERE` (impedindo o uso do índice em `criado_em`) e transfere milhares de linhas brutas para o Node.js; e (3) `top-produtos` (mediana de 15792.4 ms) varre e agrega 1,35 milhão de itens a cada chamada.

## 03 · Eliminação de consultas N+1 em `GET /clientes/:id/pedidos`

- **Problema (diagnóstico):** a rota `GET /clientes/:id/pedidos` (peso 20% na carga) executa 1 consulta para o cliente, 1 para os pedidos, 1 por pedido para os itens e 1 por item para o produto — média de 22 consultas sequenciais por requisição e máximo de 32 ([diagnostico/01-tabelas-e-indices.txt](diagnostico/01-tabelas-e-indices.txt)).
- **Hipótese:** substituir os dois loops aninhados de consultas em `api/src/rotas.js` por uma única consulta de itens com `JOIN produtos` (`WHERE i.pedido_id = ANY($1::int[]) ORDER BY i.pedido_id, i.id`) deve reduzir pela metade ou mais a mediana e o p95 da rota `pedidos-do-cliente` e o p95 geral.
- **Fontes:**
  - node-postgres. *Pooling*. https://node-postgres.com/features/pooling
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.1. Indexes: Introduction*. https://www.postgresql.org/docs/16/indexes-intro.html
- **Mudança:** commit `2276929`, em `api/src/rotas.js` (rota `GET /clientes/:id/pedidos`)
- **Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta)
- **Pastas:**
  - [20261116-232142-03-eliminar-n-mais-1](resultados/20261116-232142-03-eliminar-n-mais-1/)
  - [20261116-232311-03-eliminar-n-mais-1](resultados/20261116-232311-03-eliminar-n-mais-1/)
  - [20261116-232442-03-eliminar-n-mais-1](resultados/20261116-232442-03-eliminar-n-mais-1/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** | Antes (02) |
|---|---|---|---|---|---|
| Requisições/s | 12.66 | 13.81 | 11.83 | **12.66** | 12.84 |
| Tempo de resposta: mediana | 694.7 ms | 606.6 ms | 709.6 ms | **694.7 ms** | 302.5 ms |
| Tempo de resposta: p95 | 5503.8 ms | 4731.9 ms | 4836.8 ms | **4836.8 ms** | 6381.4 ms |
| Tempo de resposta: p99 | 13675.7 ms | 11445.7 ms | 13279.7 ms | **13279.7 ms** | 14242.9 ms |
| Mediana da rota `pedidos-do-cliente` | 1389.0 ms | 1098.4 ms | 1316.4 ms | **1316.4 ms** | 2794.5 ms |
| p95 da rota `pedidos-do-cliente` | 4057.8 ms | 4277.1 ms | 3357.3 ms | **4057.8 ms** | 8331.5 ms |
| Erros | 0.00% | 0.00% | 0.00% | **0.00%** | 0.00% |
| CPU média banco | 96.7% | 97.7% | 96.6% | **96.7%** | 97.6% |
| Memória média banco | 417.0 MiB | 411.9 MiB | 417.0 MiB | **417.0 MiB** | 415.3 MiB |
| CPU média api | 15.6% | 17.5% | 14.8% | **15.6%** | 15.6% |
| Memória média api | 41.4 MiB | 42.3 MiB | 41.2 MiB | **41.4 MiB** | 87.0 MiB |

**Conclusão:**
- A hipótese se confirmou na rota alvo e na cauda geral: na rota `pedidos-do-cliente`, a mediana caiu de **2794.5 ms para 1316.4 ms** e o p95 caiu de **8331.5 ms para 4057.8 ms**; o **p95 geral** caiu de **6381.4 ms para 4836.8 ms**, e a memória média da API caiu de **87.0 MiB para 41.4 MiB**.
- As requisições/s gerais ficaram estáveis (12.84 → 12.66) e a mediana geral subiu (302.5 → 694.7 ms) porque a CPU do banco permanece em **96.7%**, consumida pelas varreduras pesadas de `vendas-por-dia` (mediana de 4300.8 ms) e `top-produtos` (mediana de 15991.9 ms), que serão atacadas nos experimentos 04 e 05.

## 04 · Projeção de colunas e agregação SQL em `vendas-por-dia`

- **Problema (diagnóstico):** (1) `GET /relatorios/vendas-por-dia` filtra por `p.criado_em::date BETWEEN $1 AND $2`, aplicando cast na coluna (o que impede o uso de `idx_pedidos_criado_em_ativos`) e transfere em média 12.945 linhas brutas (com 3.468 kB só da coluna `observacoes`) para o Node.js agrupar em memória ([diagnostico/02-explain-consultas.txt](diagnostico/02-explain-consultas.txt)); (2) `GET /pedidos` e as demais rotas usam `SELECT *`, lendo a coluna `observacoes` (média de 274 bytes por linha contra ~22 bytes das demais colunas, [diagnostico/01-tabelas-e-indices.txt](diagnostico/01-tabelas-e-indices.txt)) e impedindo *Index-Only Scan* em `idx_pedidos_status_criado_id`.
- **Hipótese:** reescrever o filtro de data para um intervalo SARGable (`p.criado_em >= $1::timestamp AND p.criado_em < ($2::date + 1)::timestamp`), empurrar o `GROUP BY` de `vendas-por-dia` para o SQL e projetar apenas as colunas necessárias nas rotas deve reduzir drasticamente o tempo de resposta de `vendas-por-dia` e `pedidos-por-status`, diminuir o uso de CPU/memória da API e elevar as requisições/s gerais.
- **Fontes:**
  - Markus Winand. *Use The Index, Luke — Obfuscated Conditions: Dates*. https://use-the-index-luke.com/sql/where-clause/obfuscation/dates
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.4. Indexes and ORDER BY*. https://www.postgresql.org/docs/16/indexes-ordering.html
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 7.6. LIMIT and OFFSET*. https://www.postgresql.org/docs/16/queries-limit.html
- **Mudança:** commit `56b1d5f`, em `api/src/rotas.js`
- **Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta)
- **Pastas:**
  - [20261117-150741-04-otimizar-queries](resultados/20261117-150741-04-otimizar-queries/)
  - [20261117-150920-04-otimizar-queries](resultados/20261117-150920-04-otimizar-queries/)
  - [20261117-151055-04-otimizar-queries](resultados/20261117-151055-04-otimizar-queries/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** | Antes (03) |
|---|---|---|---|---|---|
| Requisições/s | 21.57 | 22.84 | 22.44 | **22.44** | 12.66 |
| Tempo de resposta: mediana | 397.7 ms | 399.1 ms | 303.1 ms | **397.7 ms** | 694.7 ms |
| Tempo de resposta: p95 | 1655.7 ms | 1601.5 ms | 1698.8 ms | **1655.7 ms** | 4836.8 ms |
| Tempo de resposta: p99 | 12470.1 ms | 11681.3 ms | 12045.5 ms | **12045.5 ms** | 13279.7 ms |
| Mediana da rota `vendas-por-dia` | 798.1 ms | 798.8 ms | 699.4 ms | **798.1 ms** | 4300.8 ms |
| p95 da rota `vendas-por-dia` | 1603.5 ms | 2324.4 ms | 1762.9 ms | **1762.9 ms** | 8659.0 ms |
| p95 da rota `pedidos-por-status` | 1608.3 ms | 1691.1 ms | 1707.7 ms | **1691.1 ms** | 5137.2 ms |
| Erros | 0.00% | 0.00% | 0.00% | **0.00%** | 0.00% |
| CPU média banco | 99.8% | 99.7% | 99.4% | **99.7%** | 96.7% |
| Memória média banco | 449.4 MiB | 445.4 MiB | 443.7 MiB | **445.4 MiB** | 417.0 MiB |
| CPU média api | 4.8% | 4.1% | 3.0% | **4.1%** | 15.6% |
| Memória média api | 25.7 MiB | 27.4 MiB | 27.2 MiB | **27.2 MiB** | 41.4 MiB |

**Conclusão:**
- Grande ganho em todas as métricas: as requisições/s subiram de **12.66 para 22.44**, a mediana geral caiu de **694.7 ms para 397.7 ms**, e o **p95 geral caiu de 4836.8 ms para 1655.7 ms**.
- Na rota `vendas-por-dia`, a mediana despencou de **4300.8 ms para 798.1 ms** e o p95 de **8659.0 ms para 1762.9 ms**; na rota `pedidos-por-status`, o p95 caiu de **5137.2 ms para 1691.1 ms**.
- O uso de CPU média da API caiu de **15.6% para 4.1%** e a memória média da API caiu de **41.4 MiB para 27.2 MiB**, pois o Node.js deixou de receber e iterar sobre dezenas de milhares de linhas brutas com `observacoes`.
- A CPU do banco permaneceu cravada em **99.7%** por causa de uma única rota restante: `top-produtos` (2% da carga, 28 chamadas em 60s), cuja mediana é **13797.1 ms** (p95 de **32000.3 ms**), varrendo 1,35 milhão de itens a cada execução. A próxima mudança (`05-mv-top-produtos`) ataca diretamente esse gargalo.

## 05 · Materialized View `mv_top_produtos` para `GET /relatorios/top-produtos`

- **Problema (diagnóstico):** a consulta de `GET /relatorios/top-produtos` faz *Hash Join* e agregação sobre 1,35 milhão de itens de pedidos não cancelados e 500 mil pedidos a cada chamada, levando 1.429,7 ms mesmo com o banco ocioso ([diagnostico/02-explain-consultas.txt](diagnostico/02-explain-consultas.txt)) e 13.797,1 ms de mediana sob carga no experimento 04.
- **Hipótese:** pré-agregar a soma de unidades e receita por produto em uma *Materialized View* (`mv_top_produtos`) indexada por `(receita_centavos DESC, id)` em `banco/04-mv-top-produtos.sql` deve eliminar a varredura de 1,35 milhão de itens em cada chamada, reduzindo drasticamente o tempo de `top-produtos`, o p95/p99 gerais e o uso de memória do banco, além de multiplicar a vazão geral.
- **Fontes:**
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 41.3. Materialized Views*. https://www.postgresql.org/docs/16/rules-materializedviews.html
  - PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.4. Indexes and ORDER BY*. https://www.postgresql.org/docs/16/indexes-ordering.html
- **Mudança:** commit `c7aa489`, adicionando `banco/04-mv-top-produtos.sql` e atualizando `GET /relatorios/top-produtos` em `api/src/rotas.js`
- **Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta)
- **Pastas:**
  - [20261117-152945-05-mv-top-produtos](resultados/20261117-152945-05-mv-top-produtos/)
  - [20261117-153106-05-mv-top-produtos](resultados/20261117-153106-05-mv-top-produtos/)
  - [20261117-153226-05-mv-top-produtos](resultados/20261117-153226-05-mv-top-produtos/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** | Antes (04) |
|---|---|---|---|---|---|
| Requisições/s | 30.25 | 144.74 | 146.20 | **144.74** | 22.44 |
| Tempo de resposta: mediana | 397.3 ms | 99.6 ms | 99.1 ms | **99.6 ms** | 397.7 ms |
| Tempo de resposta: p95 | 2199.1 ms | 398.3 ms | 398.7 ms | **398.7 ms** | 1655.7 ms |
| Tempo de resposta: p99 | 3611.4 ms | 504.1 ms | 502.6 ms | **504.1 ms** | 12045.5 ms |
| Mediana da rota `top-produtos` | 199.2 ms | 88.8 ms | 88.4 ms | **88.8 ms** | 13797.1 ms |
| p95 da rota `top-produtos` | 555.5 ms | 104.3 ms | 189.6 ms | **189.6 ms** | 32000.3 ms |
| Erros | 0.00% | 0.00% | 0.00% | **0.00%** | 0.00% |
| CPU média banco | 95.5% | 98.2% | 97.9% | **97.9%** | 99.7% |
| Memória média banco | 465.9 MiB | 347.6 MiB | 340.8 MiB | **347.6 MiB** | 445.4 MiB |
| CPU média api | 7.0% | 13.8% | 13.4% | **13.4%** | 4.1% |
| Memória média api | 26.8 MiB | 29.5 MiB | 29.6 MiB | **29.5 MiB** | 27.2 MiB |

**Conclusão:**
- Salto expressivo no desempenho geral: a mediana das requisições/s subiu de **22.44 para 144.74 req/s** (8.713 requisições em 60s), a mediana geral caiu de **397.7 ms para 99.6 ms**, o **p95 geral caiu de 1655.7 ms para 398.7 ms**, e o **p99 geral despencou de 12045.5 ms para 504.1 ms**.
- Na rota `top-produtos`, a mediana caiu de **13797.1 ms para 88.8 ms** e o p95 de **32000.3 ms para 189.6 ms**.
- A memória média do container do banco caiu de **445.4 MiB para 347.6 MiB**, pois o PostgreSQL deixou de alocar as tabelas de hash paralelas de `top-produtos`.

## 06 · Remoção do log do corpo da resposta em `api/src/server.js`

- **Problema (diagnóstico):** `api/src/server.js` intercepta `res.json` e executa `console.log(JSON.stringify({ ..., resposta: corpo }))` em toda requisição, serializando o payload duas vezes e gerando em média 1.160 bytes de log por chamada ([diagnostico/04-volume-de-log.txt](diagnostico/04-volume-de-log.txt)). Com a vazão de ~145 req/s alcançada no experimento 05, a CPU da API subiu de 4,1% para 13,4%.
- **Hipótese:** remover o middleware que serializa e imprime o corpo de cada resposta em `api/src/server.js` deve reduzir o uso de CPU da API e aumentar as requisições/s gerais.
- **Fonte:**
  - Express. *Performance Best Practices: Do logging correctly*. https://expressjs.com/en/advanced/best-practice-performance/
- **Mudança:** commit `b8affc2`, em `api/src/server.js`
- **Status:** **Aplicada, sem ganho** (variação de vazão e latência dentro da margem de ruído entre execuções)
- **Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta)
- **Pastas:**
  - [20261117-161009-06-remover-log-resposta](resultados/20261117-161009-06-remover-log-resposta/)
  - [20261117-161129-06-remover-log-resposta](resultados/20261117-161129-06-remover-log-resposta/)
  - [20261117-161248-06-remover-log-resposta](resultados/20261117-161248-06-remover-log-resposta/)

| Métrica | Execução 1 | Execução 2 | Execução 3 | **Mediana** | Antes (05) |
|---|---|---|---|---|---|
| Requisições/s | 147.81 | 147.08 | 145.18 | **147.08** | 144.74 |
| Tempo de resposta: mediana | 98.9 ms | 98.9 ms | 99.3 ms | **98.9 ms** | 99.6 ms |
| Tempo de resposta: p95 | 398.1 ms | 398.9 ms | 398.9 ms | **398.9 ms** | 398.7 ms |
| Tempo de resposta: p99 | 502.5 ms | 505.7 ms | 502.8 ms | **502.8 ms** | 504.1 ms |
| Erros | 0.00% | 0.00% | 0.00% | **0.00%** | 0.00% |
| CPU média banco | 98.6% | 97.2% | 97.8% | **97.8%** | 97.9% |
| Memória média banco | 185.2 MiB | 186.0 MiB | 186.2 MiB | **186.0 MiB** | 347.6 MiB |
| CPU média api | 12.3% | 13.0% | 12.6% | **12.6%** | 13.4% |
| Memória média api | 29.2 MiB | 30.0 MiB | 30.3 MiB | **30.0 MiB** | 29.5 MiB |

**Conclusão (por que não gerou ganho significativo):**
- A mediana de requisições/s variou de 144.74 para 147.08 (sendo que a 3ª execução do experimento 05 já havia atingido 146.20 req/s) e o p95 ficou estável (398.7 → 398.9 ms). A CPU média da API recuou apenas de 13.4% para 12.6%.
- **Por que não melhorou:** (1) o gargalo do sistema continua sendo a **CPU do banco de dados (97.8% de 1,0 CPU)** — em particular nas consultas de `pedidos-por-status` (mediana de 209.4 ms, que ainda executa `SELECT count(*)` e `OFFSET` de até 19.980 linhas a cada chamada) e `vendas-por-dia` (mediana de 300.0 ms) — enquanto a API opera com folga (~13% contra o limite de 50% = 0,5 CPU); e (2) segundo a própria documentação do Express, `console.log()` é síncrono quando o destino é um terminal (TTY) ou arquivo, mas em containers Docker sem TTY o `stdout` é um pipe gerenciado pelo daemon do container, cujo custo em ~147 req/s é pequeno frente ao tempo de espera pelo banco.
