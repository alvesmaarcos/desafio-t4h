-- Materialized View para o relatório GET /relatorios/top-produtos.
-- Pré-agrega unidades e receita por produto (excluindo pedidos cancelados).

CREATE MATERIALIZED VIEW mv_top_produtos AS
SELECT pr.id,
       pr.nome,
       pr.categoria,
       sum(i.quantidade)::bigint AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos)::bigint AS receita_centavos
  FROM itens_pedido i
  JOIN pedidos p ON p.id = i.pedido_id
  JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria;

CREATE UNIQUE INDEX idx_mv_top_produtos_id
    ON mv_top_produtos (id);

CREATE INDEX idx_mv_top_produtos_receita
    ON mv_top_produtos (receita_centavos DESC, id);

ANALYZE mv_top_produtos;
