"""
chain.py — web3.py wrapper for all MST contract interactions
─────────────────────────────────────────────────────────────
Provides one ChainClient class. All contract calls live here.
The relay's main.py calls these functions; it never touches web3 directly.
"""

import json
import os
from pathlib import Path
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware
from eth_account import Account
from eth_account.signers.local import LocalAccount
from dotenv import load_dotenv

load_dotenv()

# ─── ABI loader ────────────────────────────────────────────────────────────────
_ARTIFACTS_DIR = Path(__file__).parent.parent / "blockchain" / "artifacts" / "contracts"


def _load_abi(contract_name: str) -> list:
    """Load compiled ABI from Hardhat artifacts directory."""
    abi_path = _ARTIFACTS_DIR / f"{contract_name}.sol" / f"{contract_name}.json"
    if not abi_path.exists():
        raise FileNotFoundError(
            f"ABI not found: {abi_path}\n"
            f"Run 'npx hardhat compile' in blockchain/ first."
        )
    with open(abi_path) as f:
        return json.load(f)["abi"]


# ─── Minimal ABI fallbacks (used if artifacts not compiled yet) ────────────────
# These cover only the functions the relay actually calls.
_WORKER_REGISTRY_ABI = [
    {"inputs": [{"name": "worker", "type": "address"}, {"name": "credHash", "type": "bytes32"}],
     "name": "register", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"name": "worker", "type": "address"}],
     "name": "isActive", "outputs": [{"type": "bool"}], "stateMutability": "view", "type": "function"},
    {"inputs": [{"name": "worker", "type": "address"}],
     "name": "revoke", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
]
_CONSENT_REGISTRY_ABI = [
    {"inputs": [{"name": "patient", "type": "bytes32"}, {"name": "provider", "type": "address"},
                {"name": "categories", "type": "uint16"}, {"name": "expiry", "type": "uint64"}],
     "name": "grant", "outputs": [{"type": "uint256"}], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"name": "id", "type": "uint256"}, {"name": "who", "type": "address"},
                {"name": "category", "type": "uint16"}],
     "name": "isAllowed", "outputs": [{"type": "bool"}], "stateMutability": "view", "type": "function"},
    {"inputs": [{"name": "id", "type": "uint256"}],
     "name": "getConsent",
     "outputs": [{"components": [
         {"name": "patient", "type": "bytes32"}, {"name": "provider", "type": "address"},
         {"name": "categories", "type": "uint16"}, {"name": "expiry", "type": "uint64"},
         {"name": "revoked", "type": "bool"}, {"name": "grantedBy", "type": "address"}],
         "type": "tuple"}], "stateMutability": "view", "type": "function"},
]
_RECORD_ANCHOR_ABI = [
    {"inputs": [{"name": "root", "type": "bytes32"}, {"name": "aiDigest", "type": "bytes32"}],
     "name": "anchor", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"name": "root", "type": "bytes32"}],
     "name": "exists", "outputs": [{"type": "bool"}], "stateMutability": "view", "type": "function"},
    {"inputs": [{"name": "root", "type": "bytes32"}],
     "name": "getAnchor",
     "outputs": [{"components": [
         {"name": "anchoredBy", "type": "address"}, {"name": "anchoredAt", "type": "uint64"},
         {"name": "aiDigest", "type": "bytes32"}, {"name": "exists", "type": "bool"}],
         "type": "tuple"}], "stateMutability": "view", "type": "function"},
]
_STIPEND_VAULT_ABI = [
    {"inputs": [{"name": "visitKey", "type": "bytes32"}, {"name": "taskType", "type": "uint8"}],
     "name": "submitVisit", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"name": "visitKey", "type": "bytes32"}],
     "name": "getVisit",
     "outputs": [{"components": [
         {"name": "worker", "type": "address"}, {"name": "taskType", "type": "uint8"},
         {"name": "paid", "type": "bool"}, {"name": "submittedAt", "type": "uint64"}],
         "type": "tuple"}], "stateMutability": "view", "type": "function"},
]
_CARECOIN_ABI = [
    {"inputs": [{"name": "account", "type": "address"}],
     "name": "balanceOf", "outputs": [{"type": "uint256"}], "stateMutability": "view", "type": "function"},
]


class ChainClient:
    """
    Single entry point for all blockchain interactions.
    Instantiate once at startup; inject via FastAPI dependency.
    """

    def __init__(self):
        rpc_url = os.getenv("MST_RPC_URL", "https://testnetrpc.mstblockchain.com")
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        # POA middleware (MST uses PoA consensus)
        self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

        # Load relay signing account
        relay_key = os.getenv("RELAY_PRIVATE_KEY", "")
        if not relay_key or relay_key.startswith("0x_"):
            raise ValueError(
                "RELAY_PRIVATE_KEY not set in .env — relay cannot sign transactions"
            )
        self.relay_account: LocalAccount = Account.from_key(relay_key)

        # Load contract addresses
        contracts_path = Path(__file__).parent / "contracts.json"
        if contracts_path.exists():
            with open(contracts_path) as f:
                addrs = json.load(f)["contracts"]
        else:
            # Fallback to env vars
            addrs = {
                "WorkerRegistry":  os.getenv("WORKER_REGISTRY_ADDRESS", ""),
                "CareCoin":        os.getenv("CARECOIN_ADDRESS", ""),
                "StipendVault":    os.getenv("STIPEND_VAULT_ADDRESS", ""),
                "ConsentRegistry": os.getenv("CONSENT_REGISTRY_ADDRESS", ""),
                "RecordAnchor":    os.getenv("RECORD_ANCHOR_ADDRESS", ""),
            }

        # Bind contracts (use minimal fallback ABI — does not require compiled artifacts)
        def _contract(addr: str, abi: list):
            if not addr or addr == "0x":
                return None
            return self.w3.eth.contract(address=Web3.to_checksum_address(addr), abi=abi)

        self.worker_registry  = _contract(addrs.get("WorkerRegistry", ""),  _WORKER_REGISTRY_ABI)
        self.consent_registry = _contract(addrs.get("ConsentRegistry", ""), _CONSENT_REGISTRY_ABI)
        self.record_anchor    = _contract(addrs.get("RecordAnchor", ""),    _RECORD_ANCHOR_ABI)
        self.stipend_vault    = _contract(addrs.get("StipendVault", ""),    _STIPEND_VAULT_ABI)
        self.care_coin        = _contract(addrs.get("CareCoin", ""),        _CARECOIN_ABI)

    # ─── Internal tx builder ────────────────────────────────────────────────────

    def _send_tx(self, fn_call, signer: LocalAccount = None) -> str:
        """Build, sign, and send a transaction. Returns tx hash (hex string)."""
        acct = signer or self.relay_account
        nonce = self.w3.eth.get_transaction_count(acct.address)
        chain_id = int(os.getenv("CHAIN_ID", "91562037"))

        tx = fn_call.build_transaction({
            "from":     acct.address,
            "nonce":    nonce,
            "chainId":  chain_id,
            "gas":      500_000,
            "gasPrice": self.w3.eth.gas_price,
        })
        signed = acct.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt.status != 1:
            raise RuntimeError(f"Transaction reverted: {tx_hash.hex()}")

        return tx_hash.hex()

    # ─── WorkerRegistry ────────────────────────────────────────────────────────

    def register_worker(self, worker_address: str, cred_hash_hex: str) -> str:
        """Admin registers a new ASHA worker. Returns tx hash."""
        fn = self.worker_registry.functions.register(
            Web3.to_checksum_address(worker_address),
            bytes.fromhex(cred_hash_hex.removeprefix("0x"))
        )
        return self._send_tx(fn)

    def is_worker_active(self, worker_address: str) -> bool:
        return self.worker_registry.functions.isActive(
            Web3.to_checksum_address(worker_address)
        ).call()

    # ─── ConsentRegistry ───────────────────────────────────────────────────────

    def grant_consent(
        self,
        patient_commitment: bytes,
        provider_address: str,
        categories: int,
        expiry_unix: int,
        worker_account: LocalAccount,
    ) -> tuple[str, int]:
        """Worker grants consent. Returns (tx_hash, consent_id)."""
        fn = self.consent_registry.functions.grant(
            patient_commitment,
            Web3.to_checksum_address(provider_address),
            categories,
            expiry_unix,
        )
        tx_hash = self._send_tx(fn, signer=worker_account)
        # Read consent ID from event (last consent in registry)
        total = self.consent_registry.functions.totalConsents().call() \
            if hasattr(self.consent_registry.functions, "totalConsents") else 0
        return tx_hash, max(0, total - 1)

    def check_consent(self, consent_id: int, provider_address: str, category: int) -> bool:
        return self.consent_registry.functions.isAllowed(
            consent_id,
            Web3.to_checksum_address(provider_address),
            category,
        ).call()

    # ─── RecordAnchor ──────────────────────────────────────────────────────────

    def anchor_record(
        self,
        record_root_hex: str,
        ai_digest_hex: str,
        worker_account: LocalAccount,
    ) -> str:
        """Anchor a visit record root on-chain. Returns tx hash."""
        root = bytes.fromhex(record_root_hex.removeprefix("0x"))
        ai   = bytes.fromhex(ai_digest_hex.removeprefix("0x")) if ai_digest_hex else b"\x00" * 32
        fn = self.record_anchor.functions.anchor(root, ai)
        return self._send_tx(fn, signer=worker_account)

    def record_exists(self, record_root_hex: str) -> bool:
        root = bytes.fromhex(record_root_hex.removeprefix("0x"))
        return self.record_anchor.functions.exists(root).call()

    def get_anchor(self, record_root_hex: str) -> dict:
        root = bytes.fromhex(record_root_hex.removeprefix("0x"))
        a = self.record_anchor.functions.getAnchor(root).call()
        return {
            "anchoredBy": a[0],
            "anchoredAt": a[1],
            "aiDigest":   "0x" + a[2].hex(),
            "exists":     a[3],
        }

    # ─── StipendVault ──────────────────────────────────────────────────────────

    def submit_visit(
        self,
        visit_key_hex: str,
        task_type: int,
        worker_account: LocalAccount,
    ) -> str:
        """Worker submits a visit to the vault. Returns tx hash."""
        vk = bytes.fromhex(visit_key_hex.removeprefix("0x"))
        fn = self.stipend_vault.functions.submitVisit(vk, task_type)
        return self._send_tx(fn, signer=worker_account)

    def get_visit(self, visit_key_hex: str) -> dict:
        vk = bytes.fromhex(visit_key_hex.removeprefix("0x"))
        v = self.stipend_vault.functions.getVisit(vk).call()
        return {
            "worker":      v[0],
            "taskType":    v[1],
            "paid":        v[2],
            "submittedAt": v[3],
        }

    def batch_attest(self, visit_keys_hex: list[str]) -> str:
        """Admin or authorized verifier batch attests visits and disburses CareCoin. Returns tx hash."""
        keys = [bytes.fromhex(k.removeprefix("0x")) for k in visit_keys_hex]
        fn = self.stipend_vault.functions.batchAttest(keys)
        return self._send_tx(fn)

    # ─── CareCoin ──────────────────────────────────────────────────────────────

    def care_coin_balance(self, address: str) -> str:
        """Returns balance as string in whole CARE units."""
        raw = self.care_coin.functions.balanceOf(
            Web3.to_checksum_address(address)
        ).call()
        return str(raw // 10**18)

    # ─── Health check ──────────────────────────────────────────────────────────

    def health(self) -> dict:
        block = self.w3.eth.block_number
        chain_id = self.w3.eth.chain_id
        return {
            "connected":      True,
            "block":          block,
            "chain_id":       chain_id,
            "relay_address":  self.relay_account.address,
        }
