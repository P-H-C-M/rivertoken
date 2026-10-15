# Front-end (dApp)

Página única (`index.html`) que conversa com o contrato **RiverDAO1155** na Sepolia via MetaMask + ethers.js.

## Rodar localmente

```bash
cd frontend
python3 -m http.server 8000
# abra http://localhost:8000
```

O endereço do contrato está na constante `CONTRACT` dentro do `index.html`.
Se você fizer um novo deploy, atualize essa constante.
