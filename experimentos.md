# Experimentos

Uma linha por ideia aplicada. Todos os números saem dos arquivos gerados por `scripts/medir.sh` em `resultados/`, sem edição.

**Como comparar:** cada mudança roda 3 vezes com o mesmo rótulo. Na tabela vai a **mediana das 3 execuções** de cada métrica, tirada dos `resumo.txt` e `recursos.txt` de cada pasta. O **antes** de cada mudança é a **mudança anterior** (o antes da primeira é a linha de base).

**Parâmetros de todas as medições:** `VUS=20`, `DURACAO=60s`, `AQUECIMENTO=15s`, `SEMENTE=42` (registrados em `contexto.txt`). Limites dos containers: `api` 0,5 CPU / 256 MB e `banco` 1 CPU / 512 MB, salvo quando a mudança disser o contrário.

## Resumo

| # | Mudança | Status | Antes | req/s antes → depois | p95 antes → depois | CPU média banco antes → depois | Memória média api antes → depois | Conclusão |
|---|---|---|---|---|---|---|---|---|
| 00 | Linha de base (commit `45486c6`) | — | — | 2.67 | 24790.3 ms | 97.3% | 75.2 MiB | Ponto de partida |
| 01 | Pool de conexões (commit `f75f9c4`) | Aplicada e medida | 00 | 2.67 → 3.13 | 24790.3 ms → 22544.1 ms | 97.3% → 98.4% | 75.2 MiB → 32.5 MiB | Ganho pequeno; o gargalo continua na CPU do banco |

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
  > A hipótese foi escrita no plano antes da mudança, mas só entrou neste arquivo junto com os resultados (commit `151b845`). A partir da mudança 02, a hipótese é registrada aqui antes da mudança.
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
- A mediana geral do tempo de resposta **piorou** (1298.6 → 1603.5 ms). Uma explicação provável, ainda não verificada: com o pool, mais consultas chegam ao banco ao mesmo tempo e disputam a mesma CPU, que continua saturada (97.3% → 98.4%).
- Os erros foram de 0.52% para 0.00%, mas na linha de base eles vinham de 1 timeout em `top-produtos` (3 amostras por execução). Com tão poucas amostras, isso não sustenta uma conclusão.
- A memória média da API caiu (75.2 → 32.5 MiB), mas a 1ª execução da linha de base já tinha 32.8 MiB. A variação entre execuções é grande demais para atribuir a queda ao pool.
- **O gargalo não é a conexão, é o trabalho do banco:** a CPU do banco continua acima de 95% porque as consultas ainda leem tabelas inteiras ([diagnostico/README.md](diagnostico/README.md), achado A1). A próxima mudança ataca isso.
