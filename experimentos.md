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
