const { expect } = require("chai");
const { ethers } = require("hardhat");
const { TestHelpers } = require("../utils/testHelpers");

describe("HarpoDVP Integration Tests", function () {
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

    // Deploy two Harpo contracts using the helper method (representing different assets)
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

  describe("DVP Setup", function () {
    it("Should deploy DVP contract with correct asset addresses", async function () {
      expect(await harpoDVP.getAssetA()).to.equal(await harpoA.getAddress());
      expect(await harpoDVP.getAssetB()).to.equal(await harpoB.getAddress());
    });

    it("Should initialize with zero transaction counter", async function () {
      expect(await harpoDVP.transactionCounter()).to.equal(0);
    });
  });

  describe("Transaction Matching and Execution", function () {
    let secretA1, secretA2, secretB1, secretB2;
    let nullifierA, nullifierB;
    let nullifierAuthorityA, nullifierAuthorityB;

    beforeEach(async function () {
      // Generate secrets for both assets
      secretA1 = testHelpers.generateTestSecret(111111n);
      secretA2 = testHelpers.generateTestSecret(222222n);
      secretB1 = testHelpers.generateTestSecret(333333n);
      secretB2 = testHelpers.generateTestSecret(444444n);

      // Mint initial assets in both Harpo contracts
      const amountA = ethers.parseEther("100");
      const amountB = ethers.parseEther("50");
      const mockProof = testHelpers.createMockProof();

      await harpoA.connect(user1).mint(secretA1, amountA, mockProof, user1.address);
      await harpoB.connect(user2).mint(secretB1, amountB, mockProof, user2.address);

      // Generate nullifiers
      nullifierA = await testHelpers.generateNullifier(secretA1, testAccounts[0].babyJubJub.privateKey);
      nullifierB = await testHelpers.generateNullifier(secretB1, testAccounts[1].babyJubJub.privateKey);
      
      nullifierAuthorityA = await testHelpers.generateNullifierAuthority(secretA1);
      nullifierAuthorityB = await testHelpers.generateNullifierAuthority(secretB1);
    });

    it("Should execute DVP when transactions match", async function () {
      // Convert secrets to arrays for counterpart matching
      const secretA2Array = secretA2.map(s => ethers.toBigInt(s));
      const secretB2Array = secretB2.map(s => ethers.toBigInt(s));

      // Create first transaction (wanting to give A, receive B)
      const transferA = {
        inputs: [{
          nullifier: nullifierA,
          nullifierAuthority: nullifierAuthorityA
        }],
        merkleRoot: await harpoA.getRoot(),
        outputs: [{
          secret: secretA2
        }],
        counterpartAsset: [secretB2Array], // Expecting secretB2
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      // Create second transaction (wanting to give B, receive A)
      const transferB = {
        inputs: [{
          nullifier: nullifierB,
          nullifierAuthority: nullifierAuthorityB
        }],
        merkleRoot: await harpoB.getRoot(),
        outputs: [{
          secret: secretB2
        }],
        counterpartAsset: [secretA2Array], // Expecting secretA2
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      // Add first transaction
      await harpoDVP.addTransaction(transferA);
      expect(await harpoDVP.transactionCounter()).to.equal(1);

      // Add second transaction - should trigger DVP execution
      const tx = await harpoDVP.addTransaction(transferB);
      const receipt = await tx.wait();

      // Check TransferExecuted event
      const event = receipt.logs.find(log => {
        try {
          return harpoDVP.interface.parseLog(log)?.name === 'TransferExecuted';
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
      expect(event.args[0]).to.equal(0); // First transaction ID
      expect(event.args[1]).to.equal(1); // Second transaction ID

      // Verify nullifiers are used in both contracts
      expect(await harpoA.isNullifierUsed(nullifierA)).to.be.true;
      expect(await harpoB.isNullifierUsed(nullifierB)).to.be.true;

      // Verify transaction counter increased
      expect(await harpoDVP.transactionCounter()).to.equal(2);
    });

    it("Should store transactions when no match is found", async function () {
      const secretA2Array = secretA2.map(s => ethers.toBigInt(s));

      const transferA = {
        inputs: [{
          nullifier: nullifierA,
          nullifierAuthority: nullifierAuthorityA
        }],
        merkleRoot: await harpoA.getRoot(),
        outputs: [{
          secret: secretA2
        }],
        counterpartAsset: [secretA2Array],
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      await harpoDVP.addTransaction(transferA);
      
      expect(await harpoDVP.transactionCounter()).to.equal(1);
      
      // Transaction should be stored but not executed
      const storedTx = await harpoDVP.transactions(0);
      expect(storedTx.merkleRoot).to.equal(await harpoA.getRoot());
      expect(await harpoA.isNullifierUsed(nullifierA)).to.be.false;
    });

    it("Should handle multiple outputs in transaction matching", async function () {
      // Create secrets for multiple outputs
      const outputSecrets = [
        testHelpers.generateTestSecret(555555n),
        testHelpers.generateTestSecret(666666n)
      ];
      
      const counterpartSecrets = outputSecrets.map(secret => 
        secret.map(s => ethers.toBigInt(s))
      );

      const transferA = {
        inputs: [{
          nullifier: nullifierA,
          nullifierAuthority: nullifierAuthorityA
        }],
        merkleRoot: await harpoA.getRoot(),
        outputs: outputSecrets.map(secret => ({ secret })),
        counterpartAsset: counterpartSecrets,
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      const transferB = {
        inputs: [{
          nullifier: nullifierB,
          nullifierAuthority: nullifierAuthorityB
        }],
        merkleRoot: await harpoB.getRoot(),
        outputs: outputSecrets.map(secret => ({ secret })), // Same outputs
        counterpartAsset: counterpartSecrets,
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      await harpoDVP.addTransaction(transferA);
      
      const tx = await harpoDVP.addTransaction(transferB);
      const receipt = await tx.wait();

      // Should execute DVP with multiple outputs
      const event = receipt.logs.find(log => {
        try {
          return harpoDVP.interface.parseLog(log)?.name === 'TransferExecuted';
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
    });
  });

  describe("Error Handling", function () {
    let secretA1, nullifierA, nullifierAuthorityA;

    beforeEach(async function () {
      secretA1 = testHelpers.generateTestSecret(111111n);
      const amountA = ethers.parseEther("100");
      const mockProof = testHelpers.createMockProof();

      await harpoA.connect(user1).mint(secretA1, amountA, mockProof, user1.address);

      nullifierA = await testHelpers.generateNullifier(secretA1, testAccounts[0].babyJubJub.privateKey);
      nullifierAuthorityA = await testHelpers.generateNullifierAuthority(secretA1);
    });

    it("Should revert if settlement agent is not the caller", async function () {
      const transfer = {
        inputs: [{
          nullifier: nullifierA,
          nullifierAuthority: nullifierAuthorityA
        }],
        merkleRoot: await harpoA.getRoot(),
        outputs: [{
          secret: testHelpers.generateTestSecret(222222n)
        }],
        counterpartAsset: [[1, 2, 3]],
        settlementAgent: user2.address, // Different from caller
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      // Try to process delegated transfer directly in Harpo (not through DVP)
      await expect(
        harpoA.connect(user1).processDelegatedTransfer(transfer)
      ).to.be.revertedWith("Only the settlement agent can call this function");
    });

    it("Should clean up transactions after successful DVP execution", async function () {
      const secretA2 = testHelpers.generateTestSecret(222222n);
      const secretB1 = testHelpers.generateTestSecret(333333n);
      const secretB2 = testHelpers.generateTestSecret(444444n);

      // Mint asset B
      await harpoB.connect(user2).mint(secretB1, ethers.parseEther("50"), testHelpers.createMockProof(), user2.address);

      const nullifierB = await testHelpers.generateNullifier(secretB1, testAccounts[1].babyJubJub.privateKey);
      const nullifierAuthorityB = await testHelpers.generateNullifierAuthority(secretB1);

      const secretA2Array = secretA2.map(s => ethers.toBigInt(s));
      const secretB2Array = secretB2.map(s => ethers.toBigInt(s));

      const transferA = {
        inputs: [{ nullifier: nullifierA, nullifierAuthority: nullifierAuthorityA }],
        merkleRoot: await harpoA.getRoot(),
        outputs: [{ secret: secretA2 }],
        counterpartAsset: [secretB2Array],
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      const transferB = {
        inputs: [{ nullifier: nullifierB, nullifierAuthority: nullifierAuthorityB }],
        merkleRoot: await harpoB.getRoot(),
        outputs: [{ secret: secretB2 }],
        counterpartAsset: [secretA2Array],
        settlementAgent: await harpoDVP.getAddress(),
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      await harpoDVP.addTransaction(transferA);
      await harpoDVP.addTransaction(transferB);

      // Transactions should be deleted after execution
      const tx1 = await harpoDVP.transactions(0);
      const tx2 = await harpoDVP.transactions(1);
      
      // All fields should be zero/empty after deletion
      expect(tx1.merkleRoot).to.equal(0);
      expect(tx2.merkleRoot).to.equal(0);
    });
  });
});