const { expect } = require("chai");
const { ethers } = require("hardhat");
const { TestHelpers } = require("../utils/testHelpers");

describe("PubKeyRegistry Contract", function () {
  let pubKeyRegistry;
  let testHelpers;
  let owner, user1, user2, admin;

  beforeEach(async function () {
    [owner, user1, user2, admin] = await ethers.getSigners();
    testHelpers = new TestHelpers();

    // Deploy PubKeyRegistry
    const PubKeyRegistry = await ethers.getContractFactory("PubKeyRegistry");
    pubKeyRegistry = await PubKeyRegistry.deploy();
    await pubKeyRegistry.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set deployer as admin", async function () {
      const ADMIN_ROLE = await pubKeyRegistry.ADMIN_ROLE();
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should have correct admin role hash", async function () {
      const expectedRole = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
      const actualRole = await pubKeyRegistry.ADMIN_ROLE();
      expect(actualRole).to.equal(expectedRole);
    });
  });

  describe("Role Management", function () {
    it("Should allow admin to grant admin role to another account", async function () {
      const ADMIN_ROLE = await pubKeyRegistry.ADMIN_ROLE();
      
      await pubKeyRegistry.connect(owner).grantRoleAdmin(admin.address);
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
    });

    it("Should allow admin to revoke admin role from another account", async function () {
      const ADMIN_ROLE = await pubKeyRegistry.ADMIN_ROLE();
      
      // Grant role first
      await pubKeyRegistry.connect(owner).grantRoleAdmin(admin.address);
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, admin.address)).to.be.true;

      // Then revoke
      await pubKeyRegistry.connect(owner).revokeRoleAdmin(admin.address);
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, admin.address)).to.be.false;
    });

    it("Should prevent non-admin from granting admin role", async function () {
      await expect(
        pubKeyRegistry.connect(user1).grantRoleAdmin(user2.address)
      ).to.be.reverted;
    });

    it("Should prevent non-admin from revoking admin role", async function () {
      await expect(
        pubKeyRegistry.connect(user1).revokeRoleAdmin(owner.address)
      ).to.be.reverted;
    });
  });

  describe("Key Registration", function () {
    let babyJubJubKey;

    beforeEach(function () {
      const keyPair = testHelpers.generateBabyJubJubKeyPair();
      babyJubJubKey = keyPair.publicKey;
    });

    it("Should allow user to register their own Baby JubJub key", async function () {
      const tx = await pubKeyRegistry.connect(user1).registerKeys(user1.address, babyJubJubKey);
      const receipt = await tx.wait();

      // Check KeyRegistered event
      const event = receipt.logs.find(log => {
        try {
          return pubKeyRegistry.interface.parseLog(log)?.name === 'KeyRegistered';
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
      expect(event.args[0]).to.equal(user1.address);
      expect(event.args[1][0]).to.equal(babyJubJubKey[0]);
      expect(event.args[1][1]).to.equal(babyJubJubKey[1]);
    });

    it("Should allow admin to register keys for any account", async function () {
      await pubKeyRegistry.connect(owner).registerKeys(user1.address, babyJubJubKey);
      
      const retrievedKey = await pubKeyRegistry.getBabyJubJubKey(user1.address);
      expect(retrievedKey[0]).to.equal(babyJubJubKey[0]);
      expect(retrievedKey[1]).to.equal(babyJubJubKey[1]);
    });

    it("Should prevent non-owner, non-admin from registering keys for another account", async function () {
      await expect(
        pubKeyRegistry.connect(user2).registerKeys(user1.address, babyJubJubKey)
      ).to.be.revertedWith("Not authorized Account");
    });

    it("Should prevent registering key for address that already has a key", async function () {
      // Register key first time
      await pubKeyRegistry.connect(user1).registerKeys(user1.address, babyJubJubKey);

      // Try to register again
      const newKeyPair = testHelpers.generateBabyJubJubKeyPair();
      await expect(
        pubKeyRegistry.connect(user1).registerKeys(user1.address, newKeyPair.publicKey)
      ).to.be.revertedWith("Key already exists");
    });

    it("Should retrieve Baby JubJub key correctly", async function () {
      await pubKeyRegistry.connect(user1).registerKeys(user1.address, babyJubJubKey);
      
      const retrievedKey = await pubKeyRegistry.getBabyJubJubKey(user1.address);
      expect(retrievedKey[0]).to.equal(babyJubJubKey[0]);
      expect(retrievedKey[1]).to.equal(babyJubJubKey[1]);
    });

    it("Should revert when trying to get key for address without registered key", async function () {
      await expect(
        pubKeyRegistry.getBabyJubJubKey(user1.address)
      ).to.be.revertedWith("Key not found");
    });
  });

  describe("Edge Cases", function () {
    it("Should handle zero values in Baby JubJub key", async function () {
      const zeroKey = [0n, 0n];
      
      await pubKeyRegistry.connect(user1).registerKeys(user1.address, zeroKey);
      
      const retrievedKey = await pubKeyRegistry.getBabyJubJubKey(user1.address);
      expect(retrievedKey[0]).to.equal(0n);
      expect(retrievedKey[1]).to.equal(0n);
    });

    it("Should handle maximum values in Baby JubJub key", async function () {
      const maxKey = [
        ethers.MaxUint256,
        ethers.MaxUint256
      ];
      
      await pubKeyRegistry.connect(user1).registerKeys(user1.address, maxKey);
      
      const retrievedKey = await pubKeyRegistry.getBabyJubJubKey(user1.address);
      expect(retrievedKey[0]).to.equal(ethers.MaxUint256);
      expect(retrievedKey[1]).to.equal(ethers.MaxUint256);
    });

    it("Should allow admin to register keys for the zero address", async function () {
      const keyPair = testHelpers.generateBabyJubJubKeyPair();
      const zeroAddress = ethers.ZeroAddress;
      
      await pubKeyRegistry.connect(owner).registerKeys(zeroAddress, keyPair.publicKey);
      
      const retrievedKey = await pubKeyRegistry.getBabyJubJubKey(zeroAddress);
      expect(retrievedKey[0]).to.equal(keyPair.publicKey[0]);
      expect(retrievedKey[1]).to.equal(keyPair.publicKey[1]);
    });
  });

  describe("Access Control Integration", function () {
    it("Should properly implement OpenZeppelin AccessControl", async function () {
      const ADMIN_ROLE = await pubKeyRegistry.ADMIN_ROLE();
      const DEFAULT_ADMIN_ROLE = await pubKeyRegistry.DEFAULT_ADMIN_ROLE();
      
      // Owner should have both roles initially
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
      expect(await pubKeyRegistry.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should allow role renouncement", async function () {
      const ADMIN_ROLE = await pubKeyRegistry.ADMIN_ROLE();
      
      // Grant admin role to user1
      await pubKeyRegistry.connect(owner).grantRoleAdmin(user1.address);
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, user1.address)).to.be.true;

      // User1 renounces their role
      await pubKeyRegistry.connect(user1).renounceRole(ADMIN_ROLE, user1.address);
      expect(await pubKeyRegistry.hasRole(ADMIN_ROLE, user1.address)).to.be.false;
    });
  });
});