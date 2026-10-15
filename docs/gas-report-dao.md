## Tabela 7 — DAO completa: ERC-1155 unificado vs ERC-20 + ERC-721 (gas)

| Operação | ERC-1155 unificado | ERC-20 + ERC-721 |
|---|---:|---:|
| Deploy (total) | 3.611.789 | 4.076.501 |
| verificarIdentidade() | 167.902 | 129.369 |
| comprar() | 110.776 | 103.447 |
| criarProposta() | 150.213 | 150.288 |
| votar() [quadrático] | 176.323 | 176.190 |
| encerrarProposta() | 44.551 | 44.573 |
