const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("\n═══════════════════════════════════════════════════════");
  console.log("  HealthVault × MST Blockchain — Contract Deployment");
  console.log("═══════════════════════════════════════════════════════");
  console.log(`  Network    : ${network.name} (chainId: ${network.chainId})`);
  console.log(`  Deployer   : ${deployer.address}`);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`  Balance    : ${ethers.formatEther(balance)} MSTC`);

  if (balance === 0n) {
    throw new Error("❌ Deployer has 0 balance — claim MSTC from https://faucet.masterstroke.academy");
  }

  console.log("\n--- Step 1: Deploying WorkerRegistry ---");
  const WorkerRegistry = await ethers.getContractFactory("WorkerRegistry");
  const workerRegistry = await WorkerRegistry.deploy();
  await workerRegistry.waitForDeployment();
  const wrAddress = await workerRegistry.getAddress();
  console.log(`✅ WorkerRegistry  : ${wrAddress}`);

  console.log("\n--- Step 2: Deploying CareCoin (ERC-20) ---");
  const CareCoin = await ethers.getContractFactory("CareCoin");
  const careCoin = await CareCoin.deploy();
  await careCoin.waitForDeployment();
  const ccAddress = await careCoin.getAddress();
  console.log(`✅ CareCoin         : ${ccAddress}`);

  console.log("\n--- Step 3: Deploying StipendVault ---");
  const StipendVault = await ethers.getContractFactory("StipendVault");
  const stipendVault = await StipendVault.deploy(wrAddress, ccAddress);
  await stipendVault.waitForDeployment();
  const svAddress = await stipendVault.getAddress();
  console.log(`✅ StipendVault     : ${svAddress}`);

  console.log("\n--- Step 4: Deploying ConsentRegistry ---");
  const ConsentRegistry = await ethers.getContractFactory("ConsentRegistry");
  const consentRegistry = await ConsentRegistry.deploy(wrAddress);
  await consentRegistry.waitForDeployment();
  const crAddress = await consentRegistry.getAddress();
  console.log(`✅ ConsentRegistry  : ${crAddress}`);

  console.log("\n--- Step 5: Deploying RecordAnchor ---");
  const RecordAnchor = await ethers.getContractFactory("RecordAnchor");
  const recordAnchor = await RecordAnchor.deploy(wrAddress);
  await recordAnchor.waitForDeployment();
  const raAddress = await recordAnchor.getAddress();
  console.log(`✅ RecordAnchor     : ${raAddress}`);

  // ─── Post-deploy configuration ────────────────────────────────────────────

  console.log("\n--- Step 6: Funding StipendVault with 100,000 CARE ---");
  const fundAmount = ethers.parseEther("100000");
  const fundTx = await careCoin.transfer(svAddress, fundAmount);
  await fundTx.wait();
  console.log(`✅ Vault funded     : ${ethers.formatEther(fundAmount)} CARE`);

  console.log("\n--- Step 7: Setting task rates ---");
  const rates = [
    { type: 1, name: "Home Visit",       amount: "10"  },
    { type: 2, name: "ANC Checkup",      amount: "15"  },
    { type: 3, name: "Immunization",     amount: "12"  },
    { type: 4, name: "Delivery Escort",  amount: "25"  },
    { type: 5, name: "Neonatal Visit",   amount: "10"  },
  ];
  for (const r of rates) {
    const tx = await stipendVault.setRate(r.type, ethers.parseEther(r.amount));
    await tx.wait();
    console.log(`  Rate [${r.type}] ${r.name.padEnd(18)}: ${r.amount} CARE`);
  }

  const hospitalAddr = process.env.HOSPITAL_ADDRESS;
  if (hospitalAddr && hospitalAddr !== "0x_HOSPITAL_BRIDGEKEY_ADDRESS_HERE") {
    console.log("\n--- Step 8: Authorizing hospital ---");
    const hospTx = await stipendVault.setHospital(hospitalAddr, true);
    await hospTx.wait();
    console.log(`✅ Hospital set     : ${hospitalAddr}`);
  } else {
    console.log("\n⚠️  Step 8 skipped  : Set HOSPITAL_ADDRESS in .env and run setHospital() later");
  }

  // ─── Save addresses ────────────────────────────────────────────────────────

  const deploymentInfo = {
    network:      network.name,
    chainId:      Number(network.chainId),
    rpc:          "https://testnetrpc.mstblockchain.com",
    explorer:     "https://mstscan.com",
    deployedAt:   new Date().toISOString(),
    deployer:     deployer.address,
    contracts: {
      WorkerRegistry:  wrAddress,
      CareCoin:        ccAddress,
      StipendVault:    svAddress,
      ConsentRegistry: crAddress,
      RecordAnchor:    raAddress,
    },
    rates: Object.fromEntries(rates.map(r => [r.name, `${r.amount} CARE`])),
  };

  const outPath = path.join(__dirname, "..", "contracts.json");
  fs.writeFileSync(outPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n✅ Addresses saved  : contracts.json`);

  const backendPath = path.join(__dirname, "..", "..", "backend", "contracts.json");
  if (fs.existsSync(path.dirname(backendPath))) {
    fs.writeFileSync(backendPath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`✅ Relay copy saved : backend/contracts.json`);
  }

  console.log("\n═══════════════════════════════════════════════════════");
  console.log("  DEPLOYMENT COMPLETE — Verify on https://mstscan.com");
  console.log("═══════════════════════════════════════════════════════\n");
  console.log("  WorkerRegistry   :", wrAddress);
  console.log("  CareCoin         :", ccAddress);
  console.log("  StipendVault     :", svAddress);
  console.log("  ConsentRegistry  :", crAddress);
  console.log("  RecordAnchor     :", raAddress);
  console.log("\n  📋 Copy these into your README and submission form!\n");
}

main().catch((err) => {
  console.error("\n❌ Deployment failed:", err.message);
  process.exitCode = 1;
});
