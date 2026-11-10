# Registro de Experimentos

Todas as medições foram executadas na mesma máquina com os parâmetros padrão (`VUS=20`, `DURACAO=60s`, `AQUECIMENTO=15s`, `SEMENTE=42`) e com os mesmos limites de recursos (`banco`: 1,0 CPU e 512 MB; `api`: 0,5 CPU e 256 MB).

Os números de **antes** e **depois** riportados na tabela abaixo correspondem à **mediana das 3 execuções** de cada rótulo, geradas sem edição manual por `scripts/medir.sh`. Cada mudança é comparada contra a **mudança imediatamente anterior** (e a primeira mudança contra a `00-linha-de-base`).

## Linha de Base (`00-linha-de-base` — commit `45486c6`)

- **Pastas de resultados**:
  - [`resultados/20261110-160054-00-linha-de-base`](resultados/20261110-160054-00-linha-de-base/resumo.txt) (`2.79 req/s`, mediana `1298.6 ms`, p95 `23966.7 ms`, p99 `25301.1 ms`, erros `0.00%`, CPU média banco `97.1%`, mem média banco `401.6 MiB`, CPU média API `6.8%`, mem média API `32.8 MiB`)
  - [`resultados/20261110-160250-00-linha-de-base`](resultados/20261110-160250-00-linha-de-base/resumo.txt) (`2.61 req/s`, mediana `1302.4 ms`, p95 `24790.3 ms`, p99 `27952.7 ms`, erros `0.52%`, CPU média banco `98.0%`, mem média banco `405.7 MiB`, CPU média API `6.2%`, mem média API `75.7 MiB`)
  - [`resultados/20261110-160435-00-linha-de-base`](resultados/20261110-160435-00-linha-de-base/resumo.txt) (`2.67 req/s`, mediana `1182.2 ms`, p95 `25051.1 ms`, p99 `29013.6 ms`, erros `0.55%`, CPU média banco `97.3%`, mem média banco `404.7 MiB`, CPU média API `6.3%`, mem média API `75.2 MiB`)
- **Mediana das 3 execuções (`00-linha-de-base`)**:
  - **Vazão**: `2.67 req/s` (`191` requisições em 60s)
  - **Tempo de resposta**: mediana `1298.6 ms` | **p95 `24790.3 ms`** | p99 `27952.7 ms` | erros `0.52%`
  - **Recursos**: banco `97.3%` CPU média / `404.7 MiB` mem média; API `6.3%` CPU média / `75.2 MiB` mem média

---

## Tabela de Mudanças Aplicadas

| Mudança (Rótulo e Commit) | Hipótese | Fonte | Status | Antes (Mediana de 3 execuções) | Depois (Mediana de 3 execuções) | Pastas de resultados (Antes → Depois) | Conclusão |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`01-pool-conexoes`** (`commit f75f9c4`)<br>Troca de `new Client()` a cada query por `new Pool()` em `api/src/db.js` | Reutilizar conexões via `pg.Pool` deve aumentar a vazão (`req/s`) e reduzir o p95 e o uso de memória da API, pois elimina o handshake TCP e a criação/destruição de um processo backend no PostgreSQL a cada consulta (medido em `6.361 ms` vs `0.199 ms` em [`diagnostico/03-custo-conexao.txt`](diagnostico/03-custo-conexao.txt)). | [node-postgres — Pooling](https://node-postgres.com/features/pooling); [PostgreSQL 16 Docs — 52.2. How Connections Are Established](https://www.postgresql.org/docs/16/connect-estab.html) | Aplicada e medida | **Base (`00-linha-de-base`)**:<br>• `2.67 req/s` (`191` req)<br>• mediana `1298.6 ms`<br>• **p95 `24790.3 ms`**<br>• p99 `27952.7 ms`<br>• erros `0.52%`<br>• Banco: CPU `97.3%`, Mem `404.7 MiB`<br>• API: CPU `6.3%`, Mem `75.2 MiB` | **`01-pool-conexoes`**:<br>• **`3.13 req/s`** (`215` req)<br>• mediana `1603.5 ms`<br>• **p95 `22544.1 ms`**<br>• p99 `27160.9 ms`<br>• erros **`0.00%`**<br>• Banco: CPU `98.4%`, Mem `405.4 MiB`<br>• API: CPU `5.8%`, Mem **`32.5 MiB`** | **Antes**:<br>[`20261110-160054-00-linha-de-base`](resultados/20261110-160054-00-linha-de-base/resumo.txt),<br>[`20261110-160250-00-linha-de-base`](resultados/20261110-160250-00-linha-de-base/resumo.txt),<br>[`20261110-160435-00-linha-de-base`](resultados/20261110-160435-00-linha-de-base/resumo.txt)<br><br>**Depois**:<br>[`20261110-171233-01-pool-conexoes`](resultados/20261110-171233-01-pool-conexoes/resumo.txt),<br>[`20261110-171716-01-pool-conexoes`](resultados/20261110-171716-01-pool-conexoes/resumo.txt),<br>[`20261110-172047-01-pool-conexoes`](resultados/20261110-172047-01-pool-conexoes/resumo.txt) | **Ganho moderado, revelando o gargalo real no banco**: a vazão subiu **+17,2%** (`2.67` → `3.13 req/s`), o p95 caiu **-9,1%** (`24790.3` → `22544.1 ms`), os erros de timeout zeraram (`0.52%` → `0.00%`) e a memória média da API caiu **-56,8%** (`75.2` → `32.5 MiB`). Porém, a CPU do banco seguiu saturada em `98.4%` porque as consultas continuam fazendo *Sequential Scans* em tabelas de até 1,5M linhas. |
