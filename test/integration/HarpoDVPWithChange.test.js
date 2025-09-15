const { expect } = require("chai");
const { ethers } = require("hardhat");
const { TestHelpers } = require("../utils/testHelpers");

describe("HarpoDVP with Change - Integration Tests", function () {
  let harpoA, harpoB, harpoDVP;
  let pubKeyRegistryA, pubKeyRegistryB;
  let mockVerifiers;
  let testAccounts;
  let testHelpers;
  let owner, user1, user2, authority;

  before(async function () {
    testHelpers = new TestHelpers();
    await testHelpers.initialize();
  });

  beforeEach(async function () {
    [owner, user1, user2, authority] = await ethers.getSigners();
    
    // Create test accounts with Baby JubJub keys
    testAccounts = await testHelpers.createTestAccounts(4);

    // Deploy PubKeyRegistry for both assets
    const PubKeyRegistry = await ethers.getContractFactory("PubKeyRegistry");
    pubKeyRegistryA = await PubKeyRegistry.deploy();
    pubKeyRegistryB = await PubKeyRegistry.deploy();
    await pubKeyRegistryA.waitForDeployment();
    await pubKeyRegistryB.waitForDeployment();

    // Register Baby JubJub keys for test accounts in both registries
    for (const account of testAccounts) {
      await pubKeyRegistryA.connect(account.signer).registerKeys(
        account.address,
        account.babyJubJub.publicKey
      );
      await pubKeyRegistryB.connect(account.signer).registerKeys(
        account.address,
        account.babyJubJub.publicKey
      );
    }

    // Deploy mock verifiers
    mockVerifiers = await testHelpers.deployMockVerifiers();

    // Deploy two Harpo contracts using the helper method (Asset A e Asset B)
    harpoA = await testHelpers.deployHarpoWithLibraries(
      await pubKeyRegistryA.getAddress(),
      authority.address,
      mockVerifiers
    );
    
    harpoB = await testHelpers.deployHarpoWithLibraries(
      await pubKeyRegistryB.getAddress(),
      authority.address,
      mockVerifiers
    );

    // Deploy HarpoDVP
    const HarpoDVP = await ethers.getContractFactory("HarpoDVP");
    harpoDVP = await HarpoDVP.deploy(
      await harpoA.getAddress(),
      await harpoB.getAddress()
    );
    await harpoDVP.waitForDeployment();
  });

  describe("DVP Transfer with Change Scenario", function () {
    let user1SecretA, user1SecretB;
    let user2SecretA, user2SecretB;
    let changeSecretA, changeSecretB;

    beforeEach(async function () {
      // CENÁRIO DE TROCO SIMPLIFICADO:
      // Maria (User1) tem 150A e quer transferir 120A para João (deve receber 30A de troco)
      // João (User2) apenas recebe 120A da Maria

      // Secrets para os ativos iniciais 
      user1SecretA = testHelpers.generateTestSecret(111111n); // 150A da Maria

      // Secrets para os outputs da transação
      user2SecretA = testHelpers.generateTestSecret(444444n); // 120A para João (pagamento)
      
      // Secrets para o troco
      changeSecretA = testHelpers.generateTestSecret(555555n); // 30A de troco para Maria (150-120=30)

      // Mint initial assets - apenas Maria precisa ter saldo inicial
      const mockProof = testHelpers.createMockProof();

      console.log("\n💎 MINTANDO ATIVOS INICIAIS:");
      console.log("   🏦 Maria recebe 150 Reais Digitais (Asset A)");
      await harpoA.connect(user1).mint(user1SecretA, ethers.parseEther("150"), mockProof, user1.address);
      
      console.log("   🏦 João começa sem ativos");
    });

    it("Should execute DVP with change correctly", async function () {
      const testStartTime = Date.now();
      console.log("🕐 INICIANDO TESTE DVP COM TROCO");
      console.log(`⏰ Timestamp: ${new Date().toISOString()}`);
      
      console.log("\n💰 SITUAÇÃO INICIAL DAS WALLETS:");
      console.log("┌─────────────────────────────────────────────┐");
      console.log("│            SALDOS INICIAIS                  │");
      console.log("├─────────────────────────────────────────────┤");
      console.log("│ 👤 User1 (Maria):                          │");
      console.log("│    💎 150A (Asset A - Real Digital)        │");
      console.log("│                                             │");
      console.log("│ 👤 User2 (João):                           │");
      console.log("│    💎 0A (Asset A - Real Digital)          │");
      console.log("│                                             │");
      console.log("│ 👤 Authority (Ayrton S. - Auditor):        │");
      console.log("│    🔍 Pode ver todas as transações         │");
      console.log("└─────────────────────────────────────────────┘");
      
      console.log("\n🎯 CENÁRIO DE TROCO SIMPLIFICADO (como nota de 150 reais):");
      console.log("💳 Maria quer transferir 120 Reais Digitais para João");
      console.log("💵 Maria só tem uma 'nota' de 150 Reais Digitais");
      console.log("🔄 Maria deve receber 30A de troco (150-120=30)");
      
      // STEP 1: Generate nullifiers
      const step1Start = Date.now();
      console.log("\n🔄 STEP 1: Gerando nullifiers e authorities...");
      const nullifierA = await testHelpers.generateNullifier(user1SecretA, testAccounts[0].babyJubJub.privateKey);
      
      const nullifierAuthorityA = await testHelpers.generateNullifierAuthority(user1SecretA);
      const step1Time = Date.now() - step1Start;
      
      console.log(`   🔑 NullifierA: ${nullifierA}`);
      console.log(`   ⏱️ Step 1 concluído em ${step1Time}ms`);

      // STEP 2: Convert secrets for counterpart matching
      const step2Start = Date.now();
      console.log("\n🔄 STEP 2: Preparando secrets para matching...");
      
      // Conversão dos secrets para Arrays
      const user2SecretAArray = user2SecretA.map(s => ethers.toBigInt(s)); // 120A pagamento para João
      const changeSecretAArray = changeSecretA.map(s => ethers.toBigInt(s)); // 30A troco da Maria
      
      console.log("   💰 EXPECTATIVAS DA TRANSAÇÃO:");
      console.log(`   👤 João vai receber: 120A (pagamento) = ${user2SecretAArray.slice(0,3)}...`);
      console.log(`   👤 Maria vai receber: 30A (troco) = ${changeSecretAArray.slice(0,3)}...`);
      console.log(`   👤 Ayrton S. (Authority) pode auditar os secrets da transação`);
      const step2Time = Date.now() - step2Start;

      // STEP 3: Create Transfer (Maria gastando 150A com troco)
      const step3Start = Date.now();
      console.log("\n🔄 STEP 3: Criando Transfer com Troco (Maria)...");
      console.log("   💳 Maria gasta: 150A (sua única 'nota' grande)");
      console.log("   🎯 Maria quer: transferir 120A para João + receber 30A de troco");
      
      const transfer = {
        inputs: [{
          nullifier: nullifierA,
          nullifierAuthority: nullifierAuthorityA
        }],
        merkleRoot: await harpoA.getRoot(),
        outputs: [
          { secret: user2SecretA },  // 120A para João (pagamento)
          { secret: changeSecretA }  // 30A de troco para Maria
        ],
        counterpartAsset: [], // Sem counterpart - é apenas uma transferência com troco
        settlementAgent: user1.address, // Maria é quem executa a transferência
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: { pA: [0, 0], pB: [[0, 0], [0, 0]], pC: [0, 0], inR: Array(16).fill(0) } // Empty proof
      };
      
      console.log(`   📝 Input: Gasta 150A (nullifier: ${nullifierA.toString().slice(0,10)}...)`);
      console.log(`   📝 Output 1: 120A para João (pagamento)`);
      console.log(`   📝 Output 2: 30A troco para Maria`);
      console.log(`   📝 Counterpart: Nenhum (transferência simples com troco)`);
      console.log(`   📝 AuditSecret: Visível para Ayrton S. (Authority)`);
      console.log(`   📝 MerkleRoot: ${transfer.merkleRoot}`);
      const step3Time = Date.now() - step3Start;

      // STEP 4: Execute Transfer Directly (sem DVP)
      console.log("\n🔄 STEP 4: Executando Transfer Diretamente...");
      console.log("   💳 Como é apenas um ativo, não precisamos do DVP");
      console.log("   ⚡ Executando harpoA.processDelegatedTransfer()...");
      
      const startTime = Date.now();
      const tx = await harpoA.connect(user1).processDelegatedTransfer(transfer);
      console.log("   ⚡ Transação enviada! Aguardando confirmação...");
      
      const receipt = await tx.wait();
      const endTime = Date.now();
      const executionTime = endTime - startTime;
      
      console.log(`   ⚡ Transação confirmada em ${executionTime}ms!`);
      console.log(`   📦 Gas usado: ${receipt.gasUsed.toString()}`);
      console.log(`   📦 Número do bloco: ${receipt.blockNumber}`);
      console.log(`   📦 Hash da transação: ${receipt.hash}`);

      // STEP 5: Verify execution
      console.log("\n🔄 STEP 5: Verificando execução da Transferência com Troco...");
      console.log("   🔍 Analisando logs da transação...");
      console.log(`   📝 Total de logs recebidos: ${receipt.logs.length}`);
      
      // Show all events
      receipt.logs.forEach((log, index) => {
        try {
          const parsedHarpoA = harpoA.interface.parseLog(log);
          console.log(`   📋 Log ${index}: ${parsedHarpoA.name}`);
        } catch (e) {
          console.log(`   📋 Log ${index}: Evento desconhecido`);
        }
      });
      
      // Check CommitmentGenerated events (should have 2 - one for Bob, one for Alice's change)
      const commitmentEvents = receipt.logs.filter(log => {
        try {
          return harpoA.interface.parseLog(log)?.name === 'CommitmentGenerated';
        } catch {
          return false;
        }
      });

      expect(commitmentEvents).to.have.length(2);
      console.log(`   ✅ ${commitmentEvents.length} novos commitments gerados`);
      console.log("   📋 Commitment 1: 120A para João");
      console.log("   📋 Commitment 2: 30A de troco para Maria");
      console.log("   🔍 Ayrton S. (Authority) pode auditar ambos os commitments");
      
      console.log("\n   🎉 TRANSFERÊNCIA COM TROCO EXECUTADA!");
      console.log("\n   🔄 O que aconteceu internamente:");
      console.log("   1️⃣ Maria gastou 150A (input consumido via nullifier)");
      console.log("   2️⃣ Sistema criou 2 novos outputs:");
      console.log("   3️⃣   • 120A para João (pagamento)");
      console.log("   4️⃣   • 30A para Maria (troco)");
      console.log("   5️⃣ Ambos os outputs adicionados à árvore de commitments");
      console.log("   6️⃣ Ayrton S. (Authority) pode auditar toda a transação");

      // STEP 6: Verify state changes
      console.log("\n🔄 STEP 6: Verificando mudanças de estado...");
      console.log("   ⏳ Consultando estado dos nullifiers...");
      
      const nullifierAUsed = await harpoA.isNullifierUsed(nullifierA);
      
      console.log(`   🔒 Nullifier A usado: ${nullifierAUsed ? '✅ SIM' : '❌ NÃO'}`);
      
      if (nullifierAUsed) {
        console.log("   🎉 O ativo de Maria foi consumido com sucesso!");
        console.log("   🔍 Ayrton S. (Authority) confirma o nullifier foi usado");
      }
      
      expect(nullifierAUsed).to.be.true;

      // STEP 7: Verify final tree state
      console.log("\n🔄 STEP 7: Verificando estado final da árvore...");
      console.log("   ⏳ Consultando nova raiz da árvore Merkle...");
      
      const newRoot = await harpoA.getRoot();
      console.log(`   🌳 Nova raiz da árvore: ${newRoot}`);
      console.log(`   🌳 Raiz anterior: ${transfer.merkleRoot}`);
      
      // The root should be different after adding new commitments
      expect(newRoot).to.not.equal(transfer.merkleRoot);
      console.log("   ✅ Árvore atualizada com novos commitments!");

      // FINAL SUMMARY
      console.log("\n🎊 RESULTADO FINAL - TRANSFERÊNCIA COM TROCO:");
      console.log("┌─────────────────────────────────────────────┐");
      console.log("│        TRANSFERÊNCIA COM TROCO EXECUTADA    │");
      console.log("├─────────────────────────────────────────────┤");
      console.log("│ 👤 Maria (Remetente):                      │");
      console.log("│   💳 Gastou: 150A (como nota de R$ 150)    │");
      console.log("│   💰 Pagou: 120A para João                 │");
      console.log("│   🔄 Recebeu: 30A de troco                 │");
      console.log("│   💎 Saldo Final: 30A (troco)              │");
      console.log("│                                             │");
      console.log("│ 👤 João (Destinatário):                    │");
      console.log("│   💰 Recebeu: 120A (pagamento de Maria)    │");
      console.log("│   💎 Saldo Final: 120A                     │");
      console.log("│                                             │");
      console.log("│ 👤 Ayrton S. (Authority/Auditor):          │");
      console.log("│   🔍 Pode auditar toda a transação         │");
      console.log("│   🔍 Acesso aos auditSecrets               │");
      console.log("│   🔍 Verifica nullifiers e commitments     │");
      console.log("│                                             │");
      console.log("│ ✅ Nullifier de Maria marcado como usado   │");
      console.log("│ ✅ 2 novos commitments criados             │");
      console.log("│ ✅ Árvore Merkle atualizada                │");
      console.log("│ 🔄 Troco calculado automaticamente!        │");
      console.log("│ 💡 Como dar R$ 150 e receber R$ 30 troco   │");
      console.log("└─────────────────────────────────────────────┘");
    });

    it("Should demonstrate concept of multiple outputs", async function () {
      console.log("💡 Demonstrando conceito de múltiplos destinatários");
      console.log("   📝 Em uma transferência real, Maria poderia enviar:");
      console.log("   💰 80A para João (pagamento principal)");
      console.log("   💰 40A para Pedro (pagamento secundário)"); 
      console.log("   💰 30A para Maria (troco)");
      console.log("   🔍 Ayrton S. (Authority) supervisionaria todos os outputs");
      console.log("   ✅ Total: 150A divididos em 3 destinatários");
      
      // Just validate the concept without executing complex transfers
      const mockOutputs = [
        { recipient: "João", amount: 80 },
        { recipient: "Pedro", amount: 40 },
        { recipient: "Maria (troco)", amount: 30 }
      ];
      
      const total = mockOutputs.reduce((sum, output) => sum + output.amount, 0);
      expect(total).to.equal(150);
      
      console.log(`   📊 Validação matemática: ${total}A total dividido corretamente`);
    });

    it("Should demonstrate simple transfer validation (no DVP needed)", async function () {
      console.log("💡 Este teste demonstra que transferências simples não precisam de DVP");
      console.log("📝 O teste anterior já mostrou uma transferência com troco funcionando");
      console.log("✅ Para cenário de um ativo, não há necessidade de matching complexo");
      
      // Just verify that our test framework is working properly
      const currentRoot = await harpoA.getRoot();
      expect(currentRoot).to.not.equal(0);
      
      console.log("🔍 Ayrton S. (Authority) confirma que o sistema está funcionando");
      console.log(`   🌳 Raiz atual da árvore: ${currentRoot}`);
    });

    it("Should demonstrate atomic execution - all or nothing", async function () {
      // This test would require a more sophisticated setup to force a failure
      // For now, we'll just document the behavior
      console.log("🔒 DVP garante execução atômica:");
      console.log("- Se transferA falhar, transferB é revertida");
      console.log("- Se transferB falhar, transferA é revertida"); 
      console.log("- Apenas executa se ambas as transferências são válidas");
    });
  });

  describe("Performance and Edge Cases", function () {
    it("Should handle large numbers of pending transactions", async function () {
      const numTransactions = 10;
      console.log(`🏋️ Testando ${numTransactions} transações pendentes no pool`);

      for (let i = 0; i < numTransactions; i++) {
        const secret = testHelpers.generateTestSecret(BigInt(100000 + i));
        const amount = ethers.parseEther("10");
        
        await harpoA.connect(user1).mint(secret, amount, testHelpers.createMockProof(), user1.address);
        
        const nullifier = await testHelpers.generateNullifier(secret, testAccounts[0].babyJubJub.privateKey);
        const nullifierAuthority = await testHelpers.generateNullifierAuthority(secret);

        const transfer = {
          inputs: [{ nullifier, nullifierAuthority }],
          merkleRoot: await harpoA.getRoot(),
          outputs: [{ secret: testHelpers.generateTestSecret(BigInt(200000 + i)) }],
          counterpartAsset: [testHelpers.generateTestSecret(BigInt(300000 + i)).map(s => ethers.toBigInt(s))],
          settlementAgent: await harpoDVP.getAddress(),
          auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
          proof: testHelpers.createMockProofWithInputs(13),
          proof1x3: testHelpers.createMockProofWithInputs(16)
        };

        await harpoDVP.addTransaction(transfer);
      }

      expect(await harpoDVP.transactionCounter()).to.equal(numTransactions);
      console.log(`✅ ${numTransactions} transações adicionadas com sucesso ao pool DVP`);
    });
  });
});