-- Índices secundários para eliminar Sequential Scans nas rotas de leitura.
-- Roda automaticamente na criação do banco (após 01-estrutura.sql e 02-dados.sql).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GET /clientes?email= (busca case-insensitive com lower(email) ordenada por id)
CREATE INDEX idx_clientes_email_lower_id
    ON clientes (lower(email), id);

-- GET /clientes/:id/pedidos (pedidos de um cliente ordenados do mais recente ao mais antigo)
CREATE INDEX idx_pedidos_cliente_criado_id
    ON pedidos (cliente_id, criado_em DESC, id DESC)
    INCLUDE (status);

-- GET /pedidos?status=&pagina= (contagem e paginação por status ordenadas por criado_em DESC, id DESC)
CREATE INDEX idx_pedidos_status_criado_id
    ON pedidos (status, criado_em DESC, id DESC)
    INCLUDE (cliente_id);

-- GET /relatorios/vendas-por-dia (filtro por intervalo de criado_em em pedidos não cancelados)
CREATE INDEX idx_pedidos_criado_em_ativos
    ON pedidos (criado_em, id)
    WHERE status <> 'cancelado';

-- GET /clientes/:id/pedidos e relatórios (itens por pedido com cobertura para Index-Only Scan)
CREATE INDEX idx_itens_pedido_pedido_id
    ON itens_pedido (pedido_id, id)
    INCLUDE (produto_id, quantidade, preco_unitario_centavos);

-- GET /produtos/busca?q= (busca textual case-insensitive por substring com ILIKE)
CREATE INDEX idx_produtos_nome_trgm
    ON produtos USING gin (nome gin_trgm_ops);

ANALYZE;
