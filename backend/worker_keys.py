"""
worker_keys.py — Custodial key store for ASHA worker accounts
──────────────────────────────────────────────────────────────
For the MST Buildathon pilot, the relay holds private keys for workers
(custodial flow). This is stated honestly in the README.

Each worker gets a fresh Ethereum account created by the relay at registration.
The private key is encrypted with Fernet (AES-128 CBC + HMAC-SHA256) using
the RELAY_SECRET as the master key.

Keys are stored in a local JSON file for the hackathon demo.
In production: replace with a KMS/HSM backend (e.g. AWS KMS, GCP Cloud KMS).
"""

import json
import os
import secrets
from pathlib import Path

from cryptography.fernet import Fernet
from eth_account import Account

# ─── Key store path ────────────────────────────────────────────────────────────
_KEYSTORE_PATH = Path(__file__).parent / "worker_keys.json"


def _fernet() -> Fernet:
    """Derive Fernet key from RELAY_SECRET env var."""
    secret = os.getenv("RELAY_SECRET", "change_me_to_a_long_random_secret")
    # Fernet requires a 32-byte URL-safe base64 key
    import base64, hashlib
    key_bytes = hashlib.sha256(secret.encode()).digest()
    return Fernet(base64.urlsafe_b64encode(key_bytes))


def _load_store() -> dict:
    if _KEYSTORE_PATH.exists():
        with open(_KEYSTORE_PATH) as f:
            return json.load(f)
    return {}


def _save_store(store: dict) -> None:
    with open(_KEYSTORE_PATH, "w") as f:
        json.dump(store, f, indent=2)


# ─── Public API ────────────────────────────────────────────────────────────────

def create_worker_account(worker_name: str, phone: str, aadhaar_last4: str) -> dict:
    """
    Generate a fresh Ethereum account for a new worker.
    Encrypt and store the private key. Return public info only.
    """
    account = Account.create(extra_entropy=secrets.token_hex(32))
    pk_hex  = account.key.hex()

    # Encrypt the private key
    encrypted = _fernet().encrypt(pk_hex.encode()).decode()

    store = _load_store()
    store[account.address.lower()] = {
        "address":       account.address,
        "encrypted_key": encrypted,
        "worker_name":   worker_name,
        "phone_last4":   phone[-4:] if phone else "",
    }
    _save_store(store)

    # Credential hash for on-chain registration
    from web3 import Web3
    cred_hash = Web3.keccak(text=worker_name + phone + aadhaar_last4).hex()

    return {
        "address":    account.address,
        "cred_hash":  cred_hash,
    }


def load_worker_account(worker_address: str):
    """
    Load and decrypt a worker's private key.
    Returns an eth_account LocalAccount object.
    Raises KeyError if worker not found.
    """
    store = _load_store()
    key   = worker_address.lower()
    if key not in store:
        raise KeyError(f"Worker not found in key store: {worker_address}")

    encrypted_key = store[key]["encrypted_key"]
    pk_hex        = _fernet().decrypt(encrypted_key.encode()).decode()
    return Account.from_key(pk_hex)


def list_workers() -> list[dict]:
    """Return all registered workers (public info only, no keys)."""
    store = _load_store()
    return [
        {"address": v["address"], "worker_name": v["worker_name"]}
        for v in store.values()
    ]


def worker_exists(worker_address: str) -> bool:
    store = _load_store()
    return worker_address.lower() in store
