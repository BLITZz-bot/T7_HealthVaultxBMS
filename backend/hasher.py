"""
hasher.py — Canonical JSON hashing for HealthVault Trust Layer
──────────────────────────────────────────────────────────────
THIS FILE IS THE SINGLE SOURCE OF TRUTH for hashing logic.

Rules (must match Dart BlockchainService and JS web app exactly):
  1. Fields in VITALS_FIELDS order — no extra fields allowed
  2. Numeric fields rounded to 2 decimal places
  3. JSON with no spaces: separators=(',', ':')
  4. UTF-8 encoded
  5. keccak256 (not sha256) — for on-chain compatibility

Cross-language test vector:
  Input : {"hr":84,"sbp":120,"dbp":80,"map":93.33,"temp":37.0,"spo2":98,"resp":16,"age":32,"recorded_at":"2026-09-28T12:00:00Z"}
  Output: 0x6147f5d305c2aa8964b010f936b20bd5b93dfdb0409cf7ebbe524ece5791de7d
"""

import json
from web3 import Web3


# ─── Field order for vitals canonical JSON ────────────────────────────────────
# MUST match Dart and JS exactly. Never change without updating all 3 clients.
VITALS_FIELDS = [
    "hr",           # heart rate (bpm)
    "sbp",          # systolic blood pressure (mmHg)
    "dbp",          # diastolic blood pressure (mmHg)
    "map",          # mean arterial pressure (mmHg)
    "temp",         # temperature (°C)
    "spo2",         # oxygen saturation (%)
    "resp",         # respiratory rate (breaths/min)
    "age",          # patient age (years)
    "recorded_at",  # ISO-8601 UTC string e.g. "2026-09-28T12:00:00Z"
]


def canonical_vitals_json(record: dict) -> str:
    """
    Build the canonical JSON string from a vitals record.
    Rules:
      - Integer values stay as integers (no 84.0 → stays 84)
      - Float values that are not whole numbers are rounded to 2 decimal places
      - String fields are kept as-is
      - Missing fields become empty string ""
    This matches JS JSON.stringify behavior exactly.
    """
    ordered: dict = {}
    for field in VITALS_FIELDS:
        val = record.get(field, "")
        if isinstance(val, float):
            # Keep as int if it's a whole number (e.g. 37.0 stays 37)
            rounded = round(val, 2)
            ordered[field] = int(rounded) if rounded == int(rounded) else rounded
        elif isinstance(val, int):
            ordered[field] = val
        else:
            ordered[field] = str(val) if val is not None else ""
    return json.dumps(ordered, separators=(",", ":"), ensure_ascii=True)


def keccak256_of_vitals(record: dict) -> str:
    """
    Returns the 0x-prefixed keccak256 hex of the canonical vitals JSON.
    This is the value anchored on-chain via RecordAnchor.anchor().
    """
    canonical = canonical_vitals_json(record)
    return "0x" + Web3.keccak(text=canonical).hex()


def beneficiary_commitment(beneficiary_id: str, family_salt: str) -> bytes:
    """
    keccak256(beneficiaryId + familySalt)
    — No PII on chain. Used as patient identifier in ConsentRegistry.
    — family_salt is stored securely in the relay DB, never on-chain.
    """
    raw = beneficiary_id + family_salt
    return Web3.keccak(text=raw)


def visit_key(b_commitment: bytes, task_type: int, period: str) -> bytes:
    """
    keccak256(beneficiaryCommitment.hex() + str(taskType) + period)
    period = "YYYY-MM" (e.g. "2026-09") — prevents same-month replay attacks.
    This is what the worker submits to StipendVault.submitVisit().
    """
    raw = b_commitment.hex() + str(task_type) + period
    return Web3.keccak(text=raw)


def ai_digest(model_version: str, input_hash: str, output_label: str) -> bytes:
    """
    keccak256(modelVersion + inputHash + outputLabel)
    — Anchors the AI inference result alongside the vitals record.
    — output_label: "HIGH", "LOW", "MODERATE", etc.
    """
    raw = model_version + input_hash + output_label
    return Web3.keccak(text=raw)


# ─── Test vector validation ────────────────────────────────────────────────────

TEST_VECTOR_INPUT = {
    "hr": 84, "sbp": 120, "dbp": 80, "map": 93.33,
    "temp": 37.0, "spo2": 98, "resp": 16, "age": 32,
    "recorded_at": "2026-09-28T12:00:00Z"
}
# Verified against JS (ethers.keccak256) and Hardhat test suite:
# Canonical: {"hr":84,"sbp":120,"dbp":80,"map":93.33,"temp":37,"spo2":98,"resp":16,"age":32,"recorded_at":"2026-09-28T12:00:00Z"}
EXPECTED_HASH = "0x0713a9e100fc83fef75f58ca0176fbe06b44272f98ced343ca333a9e2dd0cf38"


def validate_test_vector() -> bool:
    """Run at startup to confirm Python hashing matches JS/Dart."""
    got = keccak256_of_vitals(TEST_VECTOR_INPUT)
    if got != EXPECTED_HASH:
        raise RuntimeError(
            f"HASH MISMATCH — cross-language test vector failed!\n"
            f"  Expected: {EXPECTED_HASH}\n"
            f"  Got     : {got}\n"
            f"  Fix the field order or rounding in hasher.py"
        )
    return True
