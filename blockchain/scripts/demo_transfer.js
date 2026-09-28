const { ethers } = require("hardhat");
const contracts = require("../contracts.json");

async function main() {
  const [admin] = await ethers.getSigners();
  console.log(`\n👑 Admin Account: ${admin.address}`);

  // Recipient ASHA worker (demo worker address or custom target)
  const ashaWorkerAddress = process.argv[2] || "0x9876543210987654321098765432109876543210";
  const amountCARE = "50";

  console.log(`👩‍⚕️ Target ASHA Address: ${ashaWorkerAddress}`);
  console.log(`🪙 Transferring ${amountCARE} CareCoin (CARE) on MST Testnet...`);

  const CareCoin = await ethers.getContractFactory("CareCoin");
  const careCoin = CareCoin.attach(contracts.contracts.CareCoin);

  // Send tokens
  const tx = await careCoin.transfer(ashaWorkerAddress, ethers.parseEther(amountCARE));
  console.log(`⏳ Transaction sent! Tx Hash: ${tx.hash}`);
  
  await tx.wait();
  console.log(`✅ Transfer confirmed on block!`);
  console.log(`🔗 View on MST Explorer: https://testnet.mstscan.com/tx/${tx.hash}\n`);
}

main().catch((err) => {
  console.error("Transfer failed:", err);
  process.exit(1);
});
