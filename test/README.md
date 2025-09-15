# Harpo Smart Contracts Testing

Esta estrutura de testes foi criada para testar os contratos inteligentes do sistema Harpo de privacidade ZK-UTXO.

## Estrutura dos Testes

```
test/
├── unit/                 # Testes unitários para contratos individuais
│   ├── Harpo.test.js    # Testes do contrato principal Harpo
│   └── PubKeyRegistry.test.js  # Testes do registro de chaves
├── integration/         # Testes de integração entre contratos
│   └── HarpoDVP.test.js # Testes do sistema DVP completo
├── utils/               # Utilitários e helpers para testes
│   └── testHelpers.js   # Funções auxiliares para testes
└── results/            # Relatórios de teste (gerados automaticamente)
```

## Como Executar os Testes

### Configuração Inicial

1. Instale as dependências:
```bash
npm install
```

2. Configure o arquivo de ambiente (opcional):
```bash
cp .env.example .env
```

### Executar Testes

```bash
# Todos os testes
npm test

# Apenas testes unitários
npm run test:unit

# Apenas testes de integração
npm run test:integration

# Testes com relatório HTML
npm run test:report

# Compilar contratos
npm run compile

# Limpar artefatos
npm run clean

# Executar node local
npm run node
```

## Recursos dos Testes

### TestHelpers Class

A classe `TestHelpers` fornece:

- **Geração de Segredos**: Criação de secrets determinísticos e aleatórios
- **Hashing Poseidon**: Implementação do hash Poseidon para commitments
- **Chaves Baby JubJub**: Geração de pares de chaves para testes
- **Nullifiers**: Geração de nullifiers e nullifier authorities
- **Provas Mock**: Criação de provas ZK simuladas para testes
- **Contas de Teste**: Setup automático de contas com chaves Baby JubJub

### Mock Contracts

O contrato `MockVerifier` simula verificadores ZK reais:
- Sempre retorna `true` para validação de provas
- Suporta diferentes tamanhos de entrada
- Compatível com todos os tipos de prova do sistema Harpo

### Cenários de Teste Cobertos

#### Testes Unitários - Harpo.sol
- Deployment e configuração inicial
- Funcionalidade de mint (criação de ativos)
- Funcionalidade de burn (destruição de ativos)
- Transferências (1x1, 1x2, 1x3, 2x2)
- Sistema de controle de autoridade
- Integração com DVP
- Árvore de Merkle e commitments

#### Testes Unitários - PubKeyRegistry.sol
- Gerenciamento de roles (Admin)
- Registro de chaves Baby JubJub
- Controles de acesso
- Casos extremos e validações

#### Testes de Integração - HarpoDVP
- Configuração completa do sistema DVP
- Matching e execução de transações
- Limpeza após execução
- Tratamento de erros

## Configurações de Teste

### Hardhat Configuration

O arquivo `hardhat.config.js` inclui:
- Otimizador Solidity habilitado
- IR-based code generation para melhor otimização
- Timeouts estendidos para operações ZK
- Gas reporter configurado
- Suporte a coverage

### Mocha Configuration

O arquivo `.mocharc.json` configura:
- Timeout de 120 segundos (necessário para operações ZK)
- Reporter spec para output limpo
- Cores habilitadas
- Exit automático após testes

## Utilitários de Desenvolvimento

### Scripts Disponíveis

- `npm run coverage` - Gera relatório de cobertura de código
- `npm run test:watch` - Executa testes em modo watch
- `npm run deploy` - Script de deployment (a ser implementado)

### Debugging

Para debug detalhado:
```bash
# Com logs verbose
DEBUG=* npm test

# Apenas logs específicos
DEBUG=harpo:* npm test
```

## Estrutura dos Dados de Teste

### Secrets
- Arrays de 15 elementos uint256
- Geração determinística para reprodutibilidade
- Hashing usando Poseidon compatível com contratos

### Baby JubJub Keys
- Pares de chaves gerados para cada conta de teste
- Registrados automaticamente no PubKeyRegistry
- Compatíveis com sistema de assinatura EdDSA

### Provas ZK Mock
- Estruturas compatíveis com Groth16
- Diferentes tamanhos de entrada (4, 12, 13, 14, 16 elementos)
- Sempre válidas para testes funcionais

## Boas Práticas

1. **Isolamento**: Cada teste é independente com setup próprio
2. **Determinismo**: Uso de seeds determinísticas quando possível
3. **Cleanup**: Reset automático de estado entre testes
4. **Coverage**: Cobertura abrangente de casos normais e extremos
5. **Performance**: Timeouts apropriados para operações ZK

## Próximos Passos

- [ ] Testes de performance para operações batch
- [ ] Testes de stress com grande volume de transações
- [ ] Integração com circuits reais (não mock)
- [ ] Testes de upgrade de contratos
- [ ] Benchmark de gas consumption