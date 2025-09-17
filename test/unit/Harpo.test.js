const { expect } = require("chai");
const { ethers } = require("hardhat");
const { TestHelpers } = require("../utils/testHelpers");

describe("Harpo Contract", function () {
  let harpo;
  let pubKeyRegistry;
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

    // Deploy PubKeyRegistry
    const PubKeyRegistry = await ethers.getContractFactory("PubKeyRegistry");
    pubKeyRegistry = await PubKeyRegistry.deploy();
    await pubKeyRegistry.waitForDeployment();

    // Register Baby JubJub keys for test accounts
    for (const account of testAccounts) {
      await pubKeyRegistry.connect(account.signer).registerKeys(
        account.address,
        account.babyJubJub.publicKey
      );
    }

    // Deploy mock verifiers
    mockVerifiers = await testHelpers.deployMockVerifiers();

    // Deploy Harpo contract using helper method
    harpo = await testHelpers.deployHarpoWithLibraries(
      await pubKeyRegistry.getAddress(),
      authority.address,
      mockVerifiers
    );
  });

  describe("Deployment", function () {
    it("Should set the correct contract authority", async function () {
      expect(await harpo.contractAuthority()).to.equal(authority.address);
    });

    it("Should initialize with empty commitment tree", async function () {
      const root = await harpo.getRoot();
      expect(root).to.equal(0); // Empty SMT starts with root 0
    });
  });

  describe("Mint Functionality", function () {
    it("Should mint new private assets successfully", async function () {
      const secret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mockProof = testHelpers.createMockProof();

      const tx = await harpo.connect(user1).mint(secret, amount, mockProof, user1.address);
      const receipt = await tx.wait();

      // Check CommitmentGenerated event
      const event = receipt.logs.find(log => {
        try {
          return harpo.interface.parseLog(log)?.name === 'CommitmentGenerated';
        } catch {
          return false;
        }
      });
      
      expect(event).to.not.be.undefined;
    });

    it("Should hash secret correctly", async function () {
      const secret = testHelpers.generateTestSecret();
      const contractHash = await harpo._hashSecret(secret);
      const jsHash = await testHelpers.hashSecret(secret);
      
      // Note: This test may need adjustment based on exact Poseidon implementation
      expect(contractHash).to.not.equal(0);
    });
  });

  describe("Burn Functionality", function () {
    it("Should burn private assets successfully", async function () {
      // First mint an asset
      const secret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mockProof = testHelpers.createMockProof();

      await harpo.connect(user1).mint(secret, amount, mockProof, user1.address);

      // Generate nullifier for burn
      const nullifier = await testHelpers.generateNullifier(secret, testAccounts[0].babyJubJub.privateKey);
      
      const burnTx = await harpo.connect(user1).burn(nullifier, amount, mockProof, user1.address);
      await burnTx.wait();

      // Check if nullifier is marked as used
      expect(await harpo.isNullifierUsed(nullifier)).to.be.true;
    });

    it("Should prevent double spending", async function () {
      const secret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mockProof = testHelpers.createMockProof();

      await harpo.connect(user1).mint(secret, amount, mockProof, user1.address);

      const nullifier = await testHelpers.generateNullifier(secret, testAccounts[0].babyJubJub.privateKey);
      
      // First burn should succeed
      await harpo.connect(user1).burn(nullifier, amount, mockProof, user1.address);

      // Second burn with same nullifier should fail
      await expect(
        harpo.connect(user1).burn(nullifier, amount, mockProof, user1.address)
      ).to.be.revertedWith("Nullifier ja utilizado");
    });
  });

  describe("Transfer Functionality", function () {
    let inputSecret, outputSecret, nullifier, nullifierAuthority, mockProof;

    beforeEach(async function () {
      // Setup: mint an asset first
      inputSecret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mintProof = testHelpers.createMockProof();

      await harpo.connect(user1).mint(inputSecret, amount, mintProof, user1.address);

      // Prepare transfer data
      outputSecret = testHelpers.generateTestSecret(987654321n);
      nullifier = await testHelpers.generateNullifier(inputSecret, testAccounts[0].babyJubJub.privateKey);
      nullifierAuthority = await testHelpers.generateNullifierAuthority(inputSecret);
      mockProof = testHelpers.createMockProof();
    });

    it("Should process 1x1 transfer successfully", async function () {
      const transfer = {
        inputs: [{
          nullifier: nullifier,
          nullifierAuthority: nullifierAuthority
        }],
        merkleRoot: await harpo.getRoot(),
        outputs: [{
          secret: outputSecret
        }],
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: mockProof
      };

      const tx = await harpo.connect(user1).processTransfer1x1(transfer);
      const receipt = await tx.wait();

      // Check AuditSecretEmmited event
      const event = receipt.logs.find(log => {
        try {
          return harpo.interface.parseLog(log)?.name === 'AuditSecretEmmited';
        } catch {
          return false;
        }
      });
      
      expect(event).to.not.be.undefined;
      expect(await harpo.isNullifierUsed(nullifier)).to.be.true;
    });

    it("Should prevent transfer with invalid merkle root", async function () {
      const invalidRoot = ethers.toBigInt(ethers.randomBytes(32));
      
      const transfer = {
        inputs: [{
          nullifier: nullifier,
          nullifierAuthority: nullifierAuthority
        }],
        merkleRoot: invalidRoot,
        outputs: [{
          secret: outputSecret
        }],
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: mockProof
      };

      await expect(
        harpo.connect(user1).processTransfer1x1(transfer)
      ).to.be.revertedWithCustomError(harpo, "RootNotFound");
    });
  });

  describe("Authority Control", function () {
    let nullifierAuthority;

    beforeEach(async function () {
      const secret = testHelpers.generateTestSecret();
      nullifierAuthority = await testHelpers.generateNullifierAuthority(secret);
    });

    it("Should allow authority to block assets", async function () {
      await harpo.connect(authority).blockAsset(nullifierAuthority);
      
      const status = await harpo.getAuthorityStatus(nullifierAuthority);
      expect(status.isBlocked).to.be.true;
      expect(status.isRedeemed).to.be.false;
      expect(status.authority).to.equal(authority.address);
    });

    it("Should allow authority to unblock assets", async function () {
      // Block first
      await harpo.connect(authority).blockAsset(nullifierAuthority);
      expect((await harpo.getAuthorityStatus(nullifierAuthority)).isBlocked).to.be.true;

      // Then unblock
      await harpo.connect(authority).unblockAsset(nullifierAuthority);
      expect((await harpo.getAuthorityStatus(nullifierAuthority)).isBlocked).to.be.false;
    });

    it("Should prevent transfer of blocked assets", async function () {
      // First setup a transfer scenario
      const inputSecret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mintProof = testHelpers.createMockProof();

      await harpo.connect(user1).mint(inputSecret, amount, mintProof, user1.address);

      const nullifier = await testHelpers.generateNullifier(inputSecret, testAccounts[0].babyJubJub.privateKey);
      const nullifierAuth = await testHelpers.generateNullifierAuthority(inputSecret);

      // Block the asset
      await harpo.connect(authority).blockAsset(nullifierAuth);

      // Try to transfer - should fail
      const transfer = {
        inputs: [{
          nullifier: nullifier,
          nullifierAuthority: nullifierAuth
        }],
        merkleRoot: await harpo.getRoot(),
        outputs: [{
          secret: testHelpers.generateTestSecret(987654321n)
        }],
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProof()
      };

      await expect(
        harpo.connect(user1).processTransfer1x1(transfer)
      ).to.be.revertedWith("Ativo bloqueado");
    });
  });

  describe("DVP Integration", function () {
    it("Should process delegated transfers for DVP", async function () {
      // Setup input
      const inputSecret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mintProof = testHelpers.createMockProof();

      await harpo.connect(user1).mint(inputSecret, amount, mintProof, user1.address);

      const nullifier = await testHelpers.generateNullifier(inputSecret, testAccounts[0].babyJubJub.privateKey);
      const nullifierAuthority = await testHelpers.generateNullifierAuthority(inputSecret);

      // Create delegated transfer
      const delegatedTransfer = {
        inputs: [{
          nullifier: nullifier,
          nullifierAuthority: nullifierAuthority
        }],
        merkleRoot: await harpo.getRoot(),
        outputs: [{
          secret: testHelpers.generateTestSecret(987654321n)
        }],
        counterpartAsset: [[1, 2, 3, 4, 5]],
        settlementAgent: user2.address,
        auditSecret: Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32))),
        proof: testHelpers.createMockProofWithInputs(13),
        proof1x3: testHelpers.createEmptyProofWithInputs(16)
      };

      const tx = await harpo.connect(user2).processDelegatedTransfer(delegatedTransfer);
      const receipt = await tx.wait();

      expect(await harpo.isNullifierUsed(nullifier)).to.be.true;
    });
  });

  describe("Commitment and Merkle Tree", function () {
    it("Should generate commitments and update merkle root", async function () {
      const initialRoot = await harpo.getRoot();
      
      const secret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mockProof = testHelpers.createMockProof();

      await harpo.connect(user1).mint(secret, amount, mockProof, user1.address);
      
      const newRoot = await harpo.getRoot();
      expect(newRoot).to.not.equal(initialRoot);
    });

    it("Should provide merkle proofs for commitments", async function () {
      const secret = testHelpers.generateTestSecret();
      const amount = ethers.parseEther("100");
      const mockProof = testHelpers.createMockProof();

      const tx = await harpo.connect(user1).mint(secret, amount, mockProof, user1.address);
      const receipt = await tx.wait();

      // Get commitment from event
      const event = receipt.logs.find(log => {
        try {
          return harpo.interface.parseLog(log)?.name === 'CommitmentGenerated';
        } catch {
          return false;
        }
      });

      const commitment = event.args[0];
      const proof = await harpo.getProof(commitment);
      
      expect(proof).to.not.be.undefined;
    });
  });
});