const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("HealthVault Trust Layer — Full Integration Tests", function () {
  let deployer, worker, hospital, stranger;
  let workerRegistry, careCoin, stipendVault, consentRegistry, recordAnchor;

  // ─── Shared canonical test vector ──────────────────────────────────────────
  // Verified: Python hasher.py produces 0x0713a9e1... for this exact string.
  // Rule: whole-number floats become integers (37.0 → 37). Must match Python+Dart.
  const TEST_VITALS_CANONICAL =
    '{"hr":84,"sbp":120,"dbp":80,"map":93.33,"temp":37,"spo2":98,"resp":16,"age":32,"recorded_at":"2026-09-28T12:00:00Z"}';
  const EXPECTED_HASH = "0x0713a9e100fc83fef75f58ca0176fbe06b44272f98ced343ca333a9e2dd0cf38";
  const TEST_RECORD_ROOT = ethers.keccak256(ethers.toUtf8Bytes(TEST_VITALS_CANONICAL));

  const FAMILY_SALT        = "salt_abc_123";
  const BENEFICIARY_ID     = "BEN_001";
  const PATIENT_COMMIT     = ethers.keccak256(ethers.toUtf8Bytes(BENEFICIARY_ID + FAMILY_SALT));
  const VISIT_PERIOD       = "2026-09";
  const TASK_HOME_VISIT    = 1;
  const TASK_ANC_CHECKUP   = 2;
  const TASK_IMMUNIZATION  = 3;
  const CRED_HASH          = ethers.keccak256(ethers.toUtf8Bytes("Bharath9876543210ABCD"));

  function makeVisitKey(commitment, taskType, period) {
    return ethers.keccak256(ethers.toUtf8Bytes(commitment + taskType.toString() + period));
  }

  beforeEach(async function () {
    [deployer, worker, hospital, stranger] = await ethers.getSigners();

    workerRegistry  = await (await ethers.getContractFactory("WorkerRegistry")).deploy();
    careCoin        = await (await ethers.getContractFactory("CareCoin")).deploy();
    stipendVault    = await (await ethers.getContractFactory("StipendVault"))
                        .deploy(await workerRegistry.getAddress(), await careCoin.getAddress());
    consentRegistry = await (await ethers.getContractFactory("ConsentRegistry"))
                        .deploy(await workerRegistry.getAddress());
    recordAnchor    = await (await ethers.getContractFactory("RecordAnchor"))
                        .deploy(await workerRegistry.getAddress());

    await careCoin.transfer(await stipendVault.getAddress(), ethers.parseEther("100000"));
    await stipendVault.setRate(TASK_HOME_VISIT, ethers.parseEther("10"));
    await stipendVault.setRate(TASK_ANC_CHECKUP, ethers.parseEther("30"));
    await stipendVault.setRate(TASK_IMMUNIZATION, ethers.parseEther("20"));
    await stipendVault.setHospital(hospital.address, true);
  });

  // ─── WorkerRegistry ────────────────────────────────────────────────────────

  describe("WorkerRegistry", function () {
    it("admin registers a worker", async function () {
      await workerRegistry.register(worker.address, CRED_HASH);
      expect(await workerRegistry.isActive(worker.address)).to.equal(true);
    });

    it("non-admin cannot register", async function () {
      await expect(workerRegistry.connect(stranger).register(worker.address, CRED_HASH))
        .to.be.revertedWith("WorkerRegistry: admin only");
    });

    it("admin revokes worker", async function () {
      await workerRegistry.register(worker.address, CRED_HASH);
      await workerRegistry.revoke(worker.address);
      expect(await workerRegistry.isActive(worker.address)).to.equal(false);
    });

    it("admin reactivates revoked worker", async function () {
      await workerRegistry.register(worker.address, CRED_HASH);
      await workerRegistry.revoke(worker.address);
      await workerRegistry.reactivate(worker.address);
      expect(await workerRegistry.isActive(worker.address)).to.equal(true);
    });
  });

  // ─── ConsentRegistry ───────────────────────────────────────────────────────

  describe("ConsentRegistry", function () {
    beforeEach(async function () {
      await workerRegistry.register(worker.address, CRED_HASH);
    });

    it("active worker grants consent", async function () {
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400 * 30);
      await expect(
        consentRegistry.connect(worker).grant(PATIENT_COMMIT, hospital.address, 3, expiry)
      ).to.emit(consentRegistry, "Granted");
    });

    it("revoked worker cannot grant consent", async function () {
      await workerRegistry.revoke(worker.address);
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400 * 30);
      await expect(
        consentRegistry.connect(worker).grant(PATIENT_COMMIT, hospital.address, 3, expiry)
      ).to.be.revertedWith("ConsentRegistry: worker not active");
    });

    it("hospital checks access and logs it", async function () {
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400 * 30);
      await consentRegistry.connect(worker).grant(PATIENT_COMMIT, hospital.address, 3, expiry);
      expect(await consentRegistry.isAllowed(0n, hospital.address, 1n)).to.equal(true);
      await expect(consentRegistry.connect(hospital).logAccess(0n, 1n))
        .to.emit(consentRegistry, "Accessed");
    });

    it("stranger cannot access consented data", async function () {
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400 * 30);
      await consentRegistry.connect(worker).grant(PATIENT_COMMIT, hospital.address, 3, expiry);
      expect(await consentRegistry.isAllowed(0n, stranger.address, 1n)).to.equal(false);
    });
  });

  // ─── RecordAnchor ──────────────────────────────────────────────────────────

  describe("RecordAnchor", function () {
    beforeEach(async function () {
      await workerRegistry.register(worker.address, CRED_HASH);
    });

    it("active worker anchors a record", async function () {
      await recordAnchor.connect(worker).anchor(TEST_RECORD_ROOT, ethers.ZeroHash);
      expect(await recordAnchor.exists(TEST_RECORD_ROOT)).to.equal(true);
    });

    it("same root cannot be anchored twice (immutability)", async function () {
      await recordAnchor.connect(worker).anchor(TEST_RECORD_ROOT, ethers.ZeroHash);
      await expect(recordAnchor.connect(worker).anchor(TEST_RECORD_ROOT, ethers.ZeroHash))
        .to.be.revertedWith("RecordAnchor: already anchored");
    });

    it("tamper detection: editing one vital changes the hash", async function () {
      const TAMPERED =
        '{"hr":85,"sbp":120,"dbp":80,"map":93.33,"temp":37.0,"spo2":98,"resp":16,"age":32,"recorded_at":"2026-09-28T12:00:00Z"}';
      const tamperedRoot = ethers.keccak256(ethers.toUtf8Bytes(TAMPERED));
      expect(tamperedRoot).to.not.equal(TEST_RECORD_ROOT);
      expect(await recordAnchor.exists(tamperedRoot)).to.equal(false);
    });

    it("AI digest anchored alongside record", async function () {
      const aiDigest = ethers.keccak256(ethers.toUtf8Bytes("v1" + TEST_RECORD_ROOT + "HIGH"));
      await recordAnchor.connect(worker).anchor(TEST_RECORD_ROOT, aiDigest);
      const a = await recordAnchor.getAnchor(TEST_RECORD_ROOT);
      expect(a.aiDigest).to.equal(aiDigest);
    });

    it("revoked worker cannot anchor", async function () {
      await workerRegistry.revoke(worker.address);
      await expect(recordAnchor.connect(worker).anchor(TEST_RECORD_ROOT, ethers.ZeroHash))
        .to.be.revertedWith("RecordAnchor: worker not active");
    });
  });

  // ─── StipendVault ──────────────────────────────────────────────────────────

  describe("StipendVault", function () {
    let visitKey;

    beforeEach(async function () {
      await workerRegistry.register(worker.address, CRED_HASH);
      visitKey = makeVisitKey(PATIENT_COMMIT, TASK_HOME_VISIT, VISIT_PERIOD);
    });

    it("full flow: submit → attest → CareCoin paid", async function () {
      const before = await careCoin.balanceOf(worker.address);
      await stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT);
      await expect(stipendVault.connect(hospital).attestAndPay(visitKey))
        .to.emit(stipendVault, "StipendPaid");
      const after = await careCoin.balanceOf(worker.address);
      expect(after - before).to.equal(ethers.parseEther("10"));
    });

    it("double-pay rejected", async function () {
      await stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT);
      await stipendVault.connect(hospital).attestAndPay(visitKey);
      await expect(stipendVault.connect(hospital).attestAndPay(visitKey))
        .to.be.revertedWith("StipendVault: already paid");
    });

    it("duplicate submit rejected", async function () {
      await stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT);
      await expect(stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT))
        .to.be.revertedWith("StipendVault: duplicate visit");
    });

    it("unauthorized stranger cannot attest", async function () {
      await stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT);
      await expect(stipendVault.connect(stranger).attestAndPay(visitKey))
        .to.be.revertedWith("StipendVault: not authorized");
    });

    it("admin can attest directly without separate hospital wallet", async function () {
      const before = await careCoin.balanceOf(worker.address);
      await stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT);
      await stipendVault.connect(deployer).attestAndPay(visitKey);
      const after = await careCoin.balanceOf(worker.address);
      expect(after - before).to.equal(ethers.parseEther("10"));
    });

    it("batchAttest approves an entire monthly survey batch in one transaction", async function () {
      const visitKey2 = makeVisitKey(PATIENT_COMMIT, TASK_ANC_CHECKUP, "2026-09-02");
      const visitKey3 = makeVisitKey(PATIENT_COMMIT, TASK_IMMUNIZATION, "2026-09-03");

      await stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT);     // 10 CARE
      await stipendVault.connect(worker).submitVisit(visitKey2, TASK_ANC_CHECKUP);   // 30 CARE
      await stipendVault.connect(worker).submitVisit(visitKey3, TASK_IMMUNIZATION);  // 20 CARE

      const before = await careCoin.balanceOf(worker.address);
      // Admin batch-approves all 3 in a single on-chain transaction
      await stipendVault.connect(deployer).batchAttest([visitKey, visitKey2, visitKey3]);
      const after = await careCoin.balanceOf(worker.address);

      // Total = 10 + 30 + 20 = 60 CARE
      expect(after - before).to.equal(ethers.parseEther("60"));
    });

    it("revoked worker cannot submit", async function () {
      await workerRegistry.revoke(worker.address);
      await expect(stipendVault.connect(worker).submitVisit(visitKey, TASK_HOME_VISIT))
        .to.be.revertedWith("StipendVault: worker not active");
    });
  });

  // ─── Cross-language hash test vector ───────────────────────────────────────

  describe("Canonical Hash Test Vector", function () {
    it("logs keccak256 for Python+Dart cross-validation", function () {
      const computed = ethers.keccak256(ethers.toUtf8Bytes(TEST_VITALS_CANONICAL));
      console.log("\n    CROSS-LANGUAGE TEST VECTOR");
      console.log("    Input  :", TEST_VITALS_CANONICAL);
      console.log("    Output :", computed);
      // Must match Python hasher.py and Dart BlockchainService
      expect(computed).to.equal(EXPECTED_HASH);
    });
  });
});
