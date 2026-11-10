// Diagnóstico 03: quanto custa abrir uma conexão nova por consulta (como faz api/src/db.js)
// comparado a reutilizar uma conexão já aberta. Somente leitura: roda "SELECT 1".
// Roda dentro do container da API, com a mesma biblioteca pg e a mesma rede até o banco:
//   docker compose exec -T api node - < diagnostico/03-custo-conexao.js > diagnostico/03-custo-conexao.txt
const { Client } = require('pg');

const config = { host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, database: process.env.DB_NAME };
const REPETICOES = 200;

function resumo(nome, tempos) {
  const ordenados = [...tempos].sort((a, b) => a - b);
  const mediana = ordenados[Math.floor(ordenados.length / 2)];
  const p95 = ordenados[Math.floor(ordenados.length * 0.95)];
  const media = tempos.reduce((s, t) => s + t, 0) / tempos.length;
  console.log(`${nome.padEnd(48)} n=${tempos.length}  media=${media.toFixed(3)} ms  mediana=${mediana.toFixed(3)} ms  p95=${p95.toFixed(3)} ms`);
}

async function main() {
  // Igual ao db.js original: connect + query + end a cada consulta.
  const novaConexao = [];
  for (let i = 0; i < REPETICOES; i += 1) {
    const inicio = process.hrtime.bigint();
    const cliente = new Client(config);
    await cliente.connect();
    await cliente.query('SELECT 1');
    await cliente.end();
    novaConexao.push(Number(process.hrtime.bigint() - inicio) / 1e6);
  }

  // Uma conexão aberta uma vez e reutilizada.
  const reutilizada = [];
  const cliente = new Client(config);
  await cliente.connect();
  for (let i = 0; i < REPETICOES; i += 1) {
    const inicio = process.hrtime.bigint();
    await cliente.query('SELECT 1');
    reutilizada.push(Number(process.hrtime.bigint() - inicio) / 1e6);
  }
  await cliente.end();

  console.log(`Data: ${new Date().toISOString()}  (banco sem carga do k6)`);
  resumo('conexao nova por consulta (db.js original)', novaConexao);
  resumo('conexao reutilizada', reutilizada);
}

main().catch((erro) => { console.error(erro); process.exit(1); });
