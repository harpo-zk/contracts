# 🔐 Harpo Smart Contracts

<div align="center">

```
██╗  ██╗ █████╗ ██████╗ ██████╗  ██████╗
██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔═══██╗
███████║███████║██████╔╝██████╔╝██║   ██║
██╔══██║██╔══██║██╔══██╗██╔═══╝ ██║   ██║
██║  ██║██║  ██║██║  ██║██║     ╚██████╔╝
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝      ╚═════╝
```

**🔒 Camada de liquidação confidencial, agnóstica de mecanismo, para EVM**

*Uma interface neutra para plugar diferentes mecanismos de privacidade — ZK-SNARK
(Groth16, PLONK), assinatura de notário, ou outros — sem acoplar a aplicação a
nenhum deles*

[![Solidity](https://img.shields.io/badge/Solidity-0.8.27-blue)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Framework-Hardhat-yellow)](https://hardhat.org/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)

</div>

---

## 🎯 Visão geral

Uma aplicação em EVM público que precisa liquidar algo confidencialmente
normalmente acopla o mecanismo de privacidade (um verifier ZK específico, por
exemplo) direto na sua lógica de negócio. Trocar o mecanismo — ou suportar mais
de um — significa reescrever o contrato consumidor.

Este repositório resolve isso com uma interface pequena e estável,
`IPrivacyLayer`, e várias implementações (**domínios**) atrás dela:

- **`domainId()`** — identificador legível do domínio.
- **`privacyModel()`** — a família do mecanismo (`ZK`, `NOTARY`, ...).
- **`verifyConfidentialSettlement(commitment, proof, publicInputs)`** — a
  pergunta central: essa liquidação confidencial é válida?

A aplicação consumidora fala só com a interface. Trocar o domínio por trás dela
é uma chamada de registry — sem tocar no contrato de negócio.

### Domínios de referência incluídos

| Domínio | Mecanismo |
|---|---|
| `HarpoZkPrivacyLayer` | ZK-SNARK (Groth16) |
| `HarpoPlonkPrivacyLayer` | ZK-SNARK (PLONK, setup universal) |
| `HarpoNotaryPrivacyLayer` | Assinatura EIP-712 de um notário confiável — zero ZK |
| `HarpoTokenPrivacyLayer` | Domínio ZK para liquidação de transferência de token |
| `HarpoZkPrivacyLayerAuditable` | Variante do domínio ZK com trilha de auditoria on-chain |

Todos implementam `ERC-165` (`supportsInterface`), então é possível descobrir
em tempo de execução se um endereço é um domínio `IPrivacyLayer` válido.

## 🏗️ Estrutura

```
contracts/
├── interfaces/
│   ├── IPrivacyLayer.sol                      # núcleo de 3 métodos
│   └── IAuditableConfidentialSettlementDomain.sol  # extensão opcional de auditoria
├── HarpoZkPrivacyLayer.sol                    # domínio ZK/Groth16
├── HarpoPlonkPrivacyLayer.sol                 # domínio ZK/PLONK
├── HarpoNotaryPrivacyLayer.sol                # domínio notary (sem ZK)
├── HarpoTokenPrivacyLayer.sol                 # domínio de liquidação de token
├── HarpoZkPrivacyLayerAuditable.sol           # domínio ZK auditável
├── HarpoRegistry.sol                          # address book (nome → endereço, versionado)
├── HarpoResolver.sol                          # mixin de resolução por nome, com trilha de uso
├── HarpoRegistryGuardian.sol                  # guardião M-de-N + timelock na frente do registry
├── HarpoSettlementConsumer.sol                # consumidor de referência
├── HarpoSelectiveDisclosure.sol               # autorização de auditoria por quórum
├── verifiers/                                 # verifiers Groth16/PLONK (código gerado)
└── mocks/                                     # mocks para teste local
```

## ⚙️ Instalação e uso

### Pré-requisitos

- Node.js 18+
- npm

### Configuração

```bash
npm install
npx hardhat compile
```

### Testes

```bash
npx hardhat test
```

Os testes cobrem o domínio `NOTARY` de ponta a ponta (assinatura EIP-712
válida/inválida/adulterada, `ERC-165`, resolução por nome via `HarpoRegistry`,
composição registry → consumidor) sem depender de artefatos de circuito ZK
(`.wasm`/`.zkey`). Os circuitos que os domínios ZK verificam vivem em
[`harpo-zk/circuits`](https://github.com/harpo-zk/circuits).

## 📦 Uso básico

```solidity
// 1. Deploy de um domínio (exemplo: notary)
HarpoNotaryPrivacyLayer layer = new HarpoNotaryPrivacyLayer(
    notaryAddress,
    auditAuthorityAddress,
    "meu-dominio-notary"
);

// 2. Registro por nome
registry.set("PrivacyLayer", address(layer));

// 3. Um consumidor resolve pelo nome e nunca precisa saber qual mecanismo está por trás
IPrivacyLayer domain = IPrivacyLayer(registry.get("PrivacyLayer"));
bool ok = domain.verifyConfidentialSettlement(commitment, proof, publicInputs);
```

Trocar `HarpoNotaryPrivacyLayer` por `HarpoZkPrivacyLayer` (ou qualquer outra
implementação de `IPrivacyLayer`) é uma única chamada `registry.set(...)` —
nada no consumidor muda.

## 🧪 Teste de referência

[`test/unit/PrivacyLayer.test.js`](test/unit/PrivacyLayer.test.js) demonstra o
fluxo completo (deploy do domínio, registro por nome, verificação de uma
liquidação, casos de rejeição) sem depender de artefatos de circuito ZK.

## 📄 Licença

Apache-2.0 (ver [`LICENSE`](LICENSE)). Alguns arquivos individuais podem
declarar uma licença diferente no próprio cabeçalho SPDX.
