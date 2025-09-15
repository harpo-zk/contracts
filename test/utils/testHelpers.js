const { ethers } = require("hardhat");
const { buildPoseidon } = require("circomlibjs");

class TestHelpers {
  constructor() {
    this.poseidon = null;
  }

  async initialize() {
    if (!this.poseidon) {
      this.poseidon = await buildPoseidon();
    }
  }

  // Generate a random secret array of 15 elements
  generateRandomSecret() {
    const secret = [];
    for (let i = 0; i < 15; i++) {
      secret.push(ethers.randomBytes(32));
    }
    return secret;
  }

  // Generate a test secret with predefined values for deterministic tests
  generateTestSecret(baseValue = 123456789n) {
    const secret = [];
    for (let i = 0; i < 15; i++) {
      secret.push(ethers.toBeHex(baseValue + BigInt(i), 32));
    }
    return secret;
  }

  // Hash secret using Poseidon (mimics contract behavior)
  async hashSecret(secret) {
    await this.initialize();
    
    // Convert secret to BigInt array
    const secretBigInt = secret.map(s => BigInt(s));
    
    // Hash in chunks of 5 (following contract pattern)
    const h1 = this.poseidon([
      secretBigInt[0], secretBigInt[1], secretBigInt[2], 
      secretBigInt[3], secretBigInt[4]
    ]);
    
    const d1 = this.poseidon([
      secretBigInt[5], secretBigInt[6], secretBigInt[7], 
      secretBigInt[8], secretBigInt[9]
    ]);
    
    const d2 = this.poseidon([
      secretBigInt[10], secretBigInt[11], secretBigInt[12], 
      secretBigInt[13], secretBigInt[14]
    ]);
    
    // Final hash
    const commitment = this.poseidon([h1, d1, d2]);
    return commitment.toString();
  }

  // Generate baby jubjub key pair (mock for testing)
  generateBabyJubJubKeyPair() {
    const privateKey = ethers.randomBytes(32);
    // In real implementation, this would derive public key from private key
    // For testing, we generate random public key coordinates
    const publicKey = [
      ethers.toBigInt(ethers.randomBytes(32)),
      ethers.toBigInt(ethers.randomBytes(32))
    ];
    return { privateKey, publicKey };
  }

  // Generate nullifier from secret and private key
  async generateNullifier(secret, privateKey) {
    // For testing, just generate a simple deterministic nullifier
    const secretHash = ethers.keccak256(ethers.toUtf8Bytes(secret.join('')));
    const privateKeyHash = typeof privateKey === 'string' ? privateKey : ethers.hexlify(privateKey);
    const combined = ethers.concat([secretHash, privateKeyHash]);
    return ethers.toBigInt(ethers.keccak256(combined));
  }

  // Generate nullifier authority
  async generateNullifierAuthority(secret, authorityKey = 12345n) {
    // For testing, just generate a simple deterministic nullifier authority
    const secretHash = ethers.keccak256(ethers.toUtf8Bytes(secret.join('')));
    const combined = ethers.concat([secretHash, ethers.toBeHex(authorityKey, 32)]);
    return ethers.toBigInt(ethers.keccak256(combined));
  }

  // Create mock proof structure
  createMockProof() {
    return {
      pA: [ethers.toBigInt(ethers.randomBytes(32)), ethers.toBigInt(ethers.randomBytes(32))],
      pB: [
        [ethers.toBigInt(ethers.randomBytes(32)), ethers.toBigInt(ethers.randomBytes(32))],
        [ethers.toBigInt(ethers.randomBytes(32)), ethers.toBigInt(ethers.randomBytes(32))]
      ],
      pC: [ethers.toBigInt(ethers.randomBytes(32)), ethers.toBigInt(ethers.randomBytes(32))]
    };
  }

  // Create mock proof with specific input count
  createMockProofWithInputs(inputCount) {
    const proof = this.createMockProof();
    proof.inR = [];
    for (let i = 0; i < inputCount; i++) {
      proof.inR.push(ethers.toBigInt(ethers.randomBytes(32)));
    }
    return proof;
  }

  // Create empty proof structure (all zeros)
  createEmptyProofWithInputs(inputCount) {
    return {
      pA: [0n, 0n],
      pB: [[0n, 0n], [0n, 0n]],
      pC: [0n, 0n],
      inR: Array(inputCount).fill(0n)
    };
  }

  // Deploy libraries required by Harpo contract
  async deployLibraries() {
    const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
    const PoseidonT4 = await ethers.getContractFactory("PoseidonT4");
    const PoseidonT6 = await ethers.getContractFactory("PoseidonT6");
    
    const poseidonT3 = await PoseidonT3.deploy();
    const poseidonT4 = await PoseidonT4.deploy();
    const poseidonT6 = await PoseidonT6.deploy();
    
    await poseidonT3.waitForDeployment();
    await poseidonT4.waitForDeployment();
    await poseidonT6.waitForDeployment();
    
    const SmtLib = await ethers.getContractFactory("SmtLib", {
      libraries: {
        PoseidonT3: await poseidonT3.getAddress(),
        PoseidonT4: await poseidonT4.getAddress()
      }
    });
    
    const smtLib = await SmtLib.deploy();
    await smtLib.waitForDeployment();
    
    return {
      PoseidonT3: await poseidonT3.getAddress(),
      PoseidonT4: await poseidonT4.getAddress(),
      PoseidonT6: await poseidonT6.getAddress(), 
      SmtLib: await smtLib.getAddress()
    };
  }

  // Deploy mock verifier contracts
  async deployMockVerifiers() {
    // Deploy mock verifier contracts that always return true
    const MockVerifier = await ethers.getContractFactory("MockVerifier");
    
    const verifiers = {
      mint: await MockVerifier.deploy(),
      withdraw: await MockVerifier.deploy(),
      verify1x1: await MockVerifier.deploy(),
      verify1x2: await MockVerifier.deploy(),
      verify1x3: await MockVerifier.deploy(),
      verify2x2: await MockVerifier.deploy()
    };

    await Promise.all(Object.values(verifiers).map(v => v.waitForDeployment()));
    
    return verifiers;
  }

  // Deploy Harpo contract with linked libraries
  async deployHarpoWithLibraries(pubKeyRegistryAddress, authorityAddress, verifiers) {
    const libraries = await this.deployLibraries();
    
    const Harpo = await ethers.getContractFactory("Harpo", {
      libraries: {
        PoseidonT4: libraries.PoseidonT4,
        PoseidonT6: libraries.PoseidonT6,
        SmtLib: libraries.SmtLib
      }
    });
    
    const harpo = await Harpo.deploy(
      pubKeyRegistryAddress,
      authorityAddress,
      await verifiers.mint.getAddress(),
      await verifiers.withdraw.getAddress(),
      await verifiers.verify1x1.getAddress(),
      await verifiers.verify1x2.getAddress(),
      await verifiers.verify1x3.getAddress(),
      await verifiers.verify2x2.getAddress()
    );
    
    await harpo.waitForDeployment();
    return harpo;
  }

  // Create test accounts with Baby JubJub keys
  async createTestAccounts(count = 3) {
    const accounts = await ethers.getSigners();
    const testAccounts = [];
    
    for (let i = 0; i < count && i < accounts.length; i++) {
      const keyPair = this.generateBabyJubJubKeyPair();
      testAccounts.push({
        signer: accounts[i],
        address: accounts[i].address,
        babyJubJub: keyPair
      });
    }
    
    return testAccounts;
  }

  // Wait for transaction and get receipt
  async waitForTx(txPromise) {
    const tx = await txPromise;
    const receipt = await tx.wait();
    return { tx, receipt };
  }

  // Extract event args from receipt
  getEventArgs(receipt, eventName) {
    const event = receipt.logs.find(log => {
      try {
        return log.fragment && log.fragment.name === eventName;
      } catch {
        return false;
      }
    });
    return event ? event.args : null;
  }

  // Time manipulation helpers
  async increaseTime(seconds) {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine", []);
  }

  async mineBlocks(blockCount) {
    for (let i = 0; i < blockCount; i++) {
      await ethers.provider.send("evm_mine", []);
    }
  }
}

module.exports = { TestHelpers };