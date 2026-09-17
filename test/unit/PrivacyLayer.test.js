const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * Smoke tests for the confidential settlement / privacy layer. Exercises the
 * mechanism-agnostic seam (IPrivacyLayer) and the registry that resolves
 * domains by name, using the NOTARY domain — the only one that needs no ZK
 * proving artifacts (.wasm/.zkey), so it runs standalone in this repo.
 *
 * The ZK domains (HarpoZkPrivacyLayer / HarpoPlonkPrivacyLayer) compile here
 * too, but exercising them end-to-end requires circuit artifacts that live
 * in harpo-zk/circuits.
 */
describe("Confidential settlement — privacy layer reference implementation", function () {
  const DOMAIN_NAME = "HarpoNotaryPrivacyLayer";

  // ERC-165 interfaceId = XOR of the 4-byte selectors of every function in the
  // interface. Computed from the ABI instead of hardcoded so it can't drift
  // silently if IPrivacyLayer's signature ever changes.
  function computeInterfaceId(iface) {
    let id = 0n;
    for (const fn of iface.fragments) {
      if (fn.type !== "function") continue;
      id ^= BigInt(iface.getFunction(fn.name).selector);
    }
    return "0x" + id.toString(16).padStart(8, "0");
  }

  async function deployRegistry(admin) {
    const HarpoRegistry = await ethers.getContractFactory("HarpoRegistry");
    const registry = await HarpoRegistry.deploy(admin.address);
    await registry.waitForDeployment();
    return registry;
  }

  async function deployNotaryLayer(notary, auditAuthority) {
    const HarpoNotaryPrivacyLayer = await ethers.getContractFactory("HarpoNotaryPrivacyLayer");
    const layer = await HarpoNotaryPrivacyLayer.deploy(
      notary.address,
      auditAuthority.address,
      "harpo-notary",
    );
    await layer.waitForDeployment();
    return layer;
  }

  async function signSettlement(signer, verifyingContractAddress, chainId, commitment, publicInputs) {
    const domain = {
      name: "HarpoNotaryPrivacyLayer",
      version: "1",
      chainId,
      verifyingContract: verifyingContractAddress,
    };
    const types = {
      Settlement: [
        { name: "commitment", type: "bytes32" },
        { name: "publicInputsHash", type: "bytes32" },
      ],
    };
    const publicInputsHash = ethers.keccak256(publicInputs);
    return signer.signTypedData(domain, types, { commitment, publicInputsHash });
  }

  describe("HarpoRegistry — discovery, not trust", function () {
    it("resolves a registered name to its current address and versions on update", async function () {
      const [admin, other] = await ethers.getSigners();
      const registry = await deployRegistry(admin);

      await expect(registry.get("Anything")).to.be.revertedWith("HarpoRegistry: nao encontrado");
      expect(await registry.tryGet("Anything")).to.equal(ethers.ZeroAddress);

      const layerA = await deployNotaryLayer(admin, admin);
      await registry.connect(admin).set(DOMAIN_NAME, await layerA.getAddress());
      expect(await registry.get(DOMAIN_NAME)).to.equal(await layerA.getAddress());

      const [, , notaryB] = await ethers.getSigners();
      const layerB = await deployNotaryLayer(notaryB, admin);
      await registry.connect(admin).set(DOMAIN_NAME, await layerB.getAddress());

      const rec = await registry.record(DOMAIN_NAME);
      expect(rec[0]).to.equal(await layerB.getAddress());
      expect(rec[1]).to.equal(2n); // version

      const history = await registry.history(DOMAIN_NAME);
      expect(history).to.deep.equal([await layerA.getAddress(), await layerB.getAddress()]);

      await expect(
        registry.connect(other).set(DOMAIN_NAME, await layerA.getAddress()),
      ).to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount");
    });
  });

  describe("HarpoNotaryPrivacyLayer — a non-ZK domain behind the same IPrivacyLayer seam", function () {
    it("reports domainId/privacyModel and answers ERC-165 for IPrivacyLayer", async function () {
      const [admin, notary] = await ethers.getSigners();
      const layer = await deployNotaryLayer(notary, admin);

      const asIPrivacyLayer = await ethers.getContractAt("IPrivacyLayer", await layer.getAddress());
      const interfaceId = computeInterfaceId(asIPrivacyLayer.interface);

      expect(await layer.domainId()).to.equal("harpo-notary");
      expect(await layer.privacyModel()).to.equal(ethers.keccak256(ethers.toUtf8Bytes("NOTARY")));
      expect(await layer.supportsInterface(interfaceId)).to.equal(true);
      expect(await layer.supportsInterface("0xffffffff")).to.equal(false);
    });

    it("verifies a settlement signed by the registered notary, and never reverts on bad input", async function () {
      const [admin, notary, impostor] = await ethers.getSigners();
      const layer = await deployNotaryLayer(notary, admin);
      const { chainId } = await ethers.provider.getNetwork();

      const commitment = ethers.keccak256(ethers.toUtf8Bytes("settlement-commitment-1"));
      const publicInputs = ethers.toUtf8Bytes("anti-replay-nonce-1");

      const validSig = await signSettlement(
        notary,
        await layer.getAddress(),
        chainId,
        commitment,
        publicInputs,
      );
      expect(
        await layer.verifyConfidentialSettlement(commitment, validSig, publicInputs),
      ).to.equal(true);

      // Signed by someone who is NOT the registered notary -> false, not a revert.
      const wrongSig = await signSettlement(
        impostor,
        await layer.getAddress(),
        chainId,
        commitment,
        publicInputs,
      );
      expect(
        await layer.verifyConfidentialSettlement(commitment, wrongSig, publicInputs),
      ).to.equal(false);

      // publicInputs tampered after signing -> the bound hash no longer matches -> false.
      const tamperedInputs = ethers.toUtf8Bytes("anti-replay-nonce-2");
      expect(
        await layer.verifyConfidentialSettlement(commitment, validSig, tamperedInputs),
      ).to.equal(false);

      // Malformed signature bytes -> ECDSA.tryRecover fails gracefully -> false, no revert.
      expect(
        await layer.verifyConfidentialSettlement(commitment, "0x1234", publicInputs),
      ).to.equal(false);
    });
  });

  describe("Mechanism-agnostic composition: business consumer resolves the domain by name", function () {
    it("verifies the same commitment through the registry, independent of which domain backs it", async function () {
      const [admin, notary] = await ethers.getSigners();
      const registry = await deployRegistry(admin);
      const layer = await deployNotaryLayer(notary, admin);
      await registry.connect(admin).set(DOMAIN_NAME, await layer.getAddress());

      const { chainId } = await ethers.provider.getNetwork();
      const commitment = ethers.keccak256(ethers.toUtf8Bytes("settlement-commitment-2"));
      const publicInputs = ethers.toUtf8Bytes("anti-replay-nonce-3");
      const sig = await signSettlement(notary, await layer.getAddress(), chainId, commitment, publicInputs);

      // A consumer never holds the domain address directly — it resolves by name.
      const resolvedAddr = await registry.get(DOMAIN_NAME);
      const IPrivacyLayer = await ethers.getContractAt("IPrivacyLayer", resolvedAddr);
      expect(
        await IPrivacyLayer.verifyConfidentialSettlement(commitment, sig, publicInputs),
      ).to.equal(true);
    });
  });
});
