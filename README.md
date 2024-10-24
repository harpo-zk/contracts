# Harpo

**Harpo** é uma solução que utiliza o conceito de *Zero Knowledge* (conhecimento zero) e o modelo *UTXO* (Unspent Transaction Output) para garantir a privacidade e anonimidade das transações em uma rede privada. Além disso, Harpo utiliza um *map de Nullifiers* para verificar UTXOs gastos, assegurando que uma transação seja única e não reutilizável.

## Visão Geral

Harpo foi projetado para resolver problemas de privacidade em redes de transações descentralizadas, aproveitando duas tecnologias principais:

- **Zero Knowledge Proofs**: Garante que transações possam ser verificadas sem revelar as informações privadas dos participantes.
- **Modelo UTXO**: Controla a movimentação de ativos entre as partes sem expor dados sensíveis.
- **Nullifiers Map**: Um mapa que rastreia e valida UTXOs já gastos, impedindo a reutilização de outputs e evitando ataques de gasto duplo.

## Funcionalidades

- **Privacidade total nas transações**: Assegurada pelo uso de provas de conhecimento zero.
- **Verificação de gasto único**: Implementada através de um mapa de Nullifiers, que monitora e invalida UTXOs gastos.
- **Modelo UTXO seguro**: Permite a movimentação de ativos em uma rede privada sem sacrificar a segurança e o anonimato.
  
## Arquitetura

1. **Zero Knowledge Proofs**: Usa um sistema de prova que permite verificar a validade de uma transação sem expor os detalhes, garantindo a privacidade dos dados dos usuários.
2. **Modelo UTXO**: Cada transação consome um ou mais UTXOs e cria novos UTXOs, com um conjunto de chaves privadas garantindo o controle sobre os ativos.
3. **Nullifiers**: Quando um UTXO é consumido em uma transação, ele é marcado como "gasto" através de um *nullifier* que é adicionado ao mapa de Nullifiers, garantindo que o mesmo UTXO não possa ser reutilizado.

## Como Funciona

- O usuário inicia uma transação fornecendo um UTXO e prova de conhecimento zero.
- O sistema valida a transação sem revelar detalhes sensíveis e marca o UTXO como gasto no *nullifier map*.
- Novos UTXOs são gerados e enviados aos respectivos destinatários de forma privada e segura.

## Requisitos

- [Linguagem/Plataforma] (e.g. Go, Rust, Solidity)
- Dependências para Zero Knowledge (e.g. ZK-SNARKs, zk-STARKs)
- Bibliotecas de criptografia para a gestão de UTXOs e Nullifiers

## Instalação

1. Clone este repositório:

```bash
git clone https://github.com/seu_usuario/harpo.git


## Install

Create a `.env` file with your private key and desired RPC provider information:
```bash
MNEMONIC="here is where your extracted twelve words mnemonic phrase should be put"
PRIVATE_KEY="YOUR_WALLET_PRIVATE_KEY"
POKT_API_KEY="********************************"
INFURA_API_KEY="********************************"
INFURA_API_SECRET="********************************"
ALCHEMY_API_KEY="="********************************""
ETHERSCAN_API_KEY="********************************"
```

Install the dependencies
```bash
npm install
```

## Usage
The scripts are supposed to be run with `npx ts-node`. 

Deploying the Ballot contract:
```bash
npx ts-node --files ./scripts/Deploy.ts "proposal1" "proposal2" "proposal3" "proposalN"
```

Create token:
```bash
npx ts-node --files ./scripts/GenerateToken.ts "0x6786ds876s8dfds8f7ds" "DREX" 10
```

Encrypt Data( Secret | Nullifier ):
```bash
npx ts-node --files ./scripts/GenerateSecret.ts '"ownerAddress":"0x6786ds876s8dfds8f7ds","type":"DREX","amount":"10","nonce":"d4eb7ced-a07c-4d7a-878e-8547d8a928c3"}' "0x82A94fFBfb194a6a39E944271D5aB"
```

Generate Commitment:
```bash
npx ts-node --files ./scripts/GenerateCommitment.ts "86359cdd92657800cbb07a8c427e05e14212ab68bab44cbb05ba98b6e82d59abf645967b093c97261a78326b10b0dc24460905975eb3e7e7d1372dec9df9ab2fc9a112720acae9627fe5455d3f6f0fa35755d97d72ac6aa0f3eb87399a0edc02df04552934596fc078f6abe2ab2801971f767d0472e1561357f5dc3426be5490"
```

## Contributors
This project was made by : 
- [Juliano Sales](https://github.com/tzdesing)
- [AAAA](https://github.com/AAAA)
- [BBBB](https://github.com/BBBB)
