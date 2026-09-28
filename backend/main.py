"""
main.py — HealthVault Trust Layer Relay API
───────────────────────────────────────────
FastAPI backend that:
  1. Creates custodial worker wallets and registers them on-chain (admin flow)
  2. Receives APK outbox payloads and relays them to MST contracts
  3. Provides a public /verify endpoint for the hospital web verifier

Routes:
  POST /register-worker   ← Admin web app calls this (BridgeKey authenticated)
  POST /consent           ← APK outbox → ConsentRegistry
  POST /anchor            ← APK outbox → RecordAnchor
  POST /visit             ← APK outbox → StipendVault
  GET  /verify/{hash}     ← Hospital verifier (public read-only)
  GET  /worker/{address}  ← Worker balance + status
  GET  /health            ← Chain connectivity check
"""

import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

load_dotenv()

from hasher import (
    keccak256_of_vitals,
    beneficiary_commitment,
    visit_key,
    ai_digest,
    validate_test_vector,
    EXPECTED_HASH,
)
from chain import ChainClient
from worker_keys import (
    create_worker_account,
    load_worker_account,
    worker_exists,
    list_workers,
)

# ─── App lifecycle ─────────────────────────────────────────────────────────────

chain: ChainClient | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global chain
    # Validate cross-language hash test vector at startup
    print("🔍 Validating canonical hash test vector...")
    validate_test_vector()
    print(f"✅ Test vector OK: {EXPECTED_HASH}")

    # Connect to MST chain
    print("🔗 Connecting to MST Testnet...")
    try:
        chain = ChainClient()
        h = chain.health()
        print(f"✅ Connected — Block #{h['block']}, ChainID {h['chain_id']}")
        print(f"   Relay address: {h['relay_address']}")
    except Exception as e:
        print(f"⚠️  Chain connection warning: {e}")
        print("   Running in offline mode — blockchain calls will fail")
        chain = None

    yield  # App is running

    print("👋 Relay shutting down")


app = FastAPI(
    title="HealthVault Trust Layer Relay",
    description=(
        "Relay backend for HealthVault × MST Blockchain. "
        "Signs and submits worker transactions to the MST testnet."
    ),
    version="2.0.0",
    lifespan=lifespan,
)

# CORS — allow the web app and APK to call us
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict to your domains in production
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ─── Admin auth (simple shared secret for hackathon) ──────────────────────────

def _check_admin(x_admin_secret: str | None):
    """Verify the X-Admin-Secret header matches RELAY_SECRET env var."""
    expected = os.getenv("RELAY_SECRET", "change_me_to_a_long_random_secret")
    if x_admin_secret != expected:
        raise HTTPException(status_code=401, detail="Invalid admin secret")


# ─── Request / Response models ─────────────────────────────────────────────────

class RegisterWorkerRequest(BaseModel):
    worker_name:   str = Field(..., description="Full name of the ASHA worker")
    phone:         str = Field(..., description="Worker phone number")
    aadhaar_last4: str = Field(..., description="Last 4 digits of Aadhaar (not stored on-chain)")
    admin_address: str = Field(..., description="BridgeKey address of the registering admin")


class ConsentRequest(BaseModel):
    worker_address:    str = Field(..., description="Relay-held worker address")
    beneficiary_id:    str = Field(..., description="Internal beneficiary ID (not Aadhaar)")
    family_salt:       str = Field(..., description="Per-family random salt (stored only in relay)")
    provider_address:  str = Field(..., description="Hospital BridgeKey address")
    categories:        int = Field(3, description="Bitmask: 1=maternal, 2=general, 4=emergency")
    duration_days:     int = Field(30, description="Consent validity in days")


class AnchorRequest(BaseModel):
    worker_address:  str = Field(..., description="Relay-held worker address")
    vitals:          dict = Field(..., description="Raw vitals dict — relay computes the hash")
    beneficiary_id:  str = Field(..., description="For cross-referencing (not stored on-chain)")
    # Optional AI output
    model_version:   str | None = Field(None, description="e.g. 'sepsis-v1'")
    ai_output_label: str | None = Field(None, description="'HIGH', 'LOW', 'MODERATE'")


class VisitRequest(BaseModel):
    worker_address:  str = Field(..., description="Relay-held worker address")
    beneficiary_id:  str = Field(..., description="Internal beneficiary ID")
    family_salt:     str = Field(..., description="Per-family random salt")
    task_type:       int = Field(1, description="1=Home Visit, 2=ANC, 3=Immunization, 4=Delivery, 5=Neonatal")
    period:          str = Field(..., description="'YYYY-MM' e.g. '2026-09' — prevents same-month replay")


class BatchAttestRequest(BaseModel):
    visit_keys: list[str] = Field(..., description="List of visit keys (hex) to attest and pay in one batch")



# ─── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health_check():
    """Chain connectivity and relay status."""
    if chain is None:
        return {"connected": False, "message": "Relay running in offline mode"}
    try:
        return chain.health()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Chain error: {str(e)}")


@app.post("/register-worker")
async def register_worker(
    req: RegisterWorkerRequest,
    x_admin_secret: str | None = Header(None),
):
    """
    Admin registers a new ASHA worker.
    Creates a custodial wallet, registers it on-chain via WorkerRegistry.
    Protected by X-Admin-Secret header.
    """
    _check_admin(x_admin_secret)

    # 1. Create wallet
    worker_info = create_worker_account(req.worker_name, req.phone, req.aadhaar_last4)
    worker_address = worker_info["address"]
    cred_hash      = worker_info["cred_hash"]

    # 2. Register on-chain
    if chain is None:
        return {
            "worker_address": worker_address,
            "cred_hash":      cred_hash,
            "tx_hash":        None,
            "warning":        "Relay in offline mode — not registered on-chain",
        }

    try:
        tx_hash = chain.register_worker(worker_address, cred_hash)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"On-chain registration failed: {str(e)}")

    return {
        "worker_address": worker_address,
        "cred_hash":      cred_hash,
        "tx_hash":        tx_hash,
        "explorer":       f"https://mstscan.com/tx/{tx_hash}",
    }


@app.post("/consent")
async def grant_consent(req: ConsentRequest):
    """
    APK outbox → ConsentRegistry.grant()
    Worker grants patient consent for a provider.
    Beneficiary commitment (keccak hash) goes on-chain — no PII.
    """
    if chain is None:
        raise HTTPException(status_code=503, detail="Relay in offline mode")

    if not worker_exists(req.worker_address):
        raise HTTPException(status_code=404, detail="Worker not found in key store")

    worker_account = load_worker_account(req.worker_address)

    # Compute patient commitment (no PII on-chain)
    patient_commit = beneficiary_commitment(req.beneficiary_id, req.family_salt)

    # Expiry
    expiry_unix = int(
        datetime.now(timezone.utc).timestamp() + req.duration_days * 86400
    )

    try:
        tx_hash, consent_id = chain.grant_consent(
            patient_commitment=patient_commit,
            provider_address=req.provider_address,
            categories=req.categories,
            expiry_unix=expiry_unix,
            worker_account=worker_account,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Consent grant failed: {str(e)}")

    return {
        "tx_hash":    tx_hash,
        "consent_id": consent_id,
        "expires_at": datetime.fromtimestamp(expiry_unix, tz=timezone.utc).isoformat(),
        "explorer":   f"https://mstscan.com/tx/{tx_hash}",
    }


@app.post("/anchor")
async def anchor_record(req: AnchorRequest):
    """
    APK outbox → RecordAnchor.anchor()
    Relay recomputes the canonical vitals hash (guarantees consistency)
    and anchors it on-chain with optional AI digest.
    """
    if chain is None:
        raise HTTPException(status_code=503, detail="Relay in offline mode")

    if not worker_exists(req.worker_address):
        raise HTTPException(status_code=404, detail="Worker not found in key store")

    # Recompute hash server-side (canonical rules enforced here)
    record_root_hex = keccak256_of_vitals(req.vitals)

    # Optional AI digest
    ai_digest_hex = "0x" + "00" * 32  # zero bytes32 = no AI flag
    if req.model_version and req.ai_output_label:
        ai_digest_hex = "0x" + ai_digest(
            req.model_version,
            record_root_hex,
            req.ai_output_label,
        ).hex()

    worker_account = load_worker_account(req.worker_address)

    try:
        tx_hash = chain.anchor_record(
            record_root_hex=record_root_hex,
            ai_digest_hex=ai_digest_hex,
            worker_account=worker_account,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Anchor failed: {str(e)}")

    return {
        "tx_hash":         tx_hash,
        "record_hash":     record_root_hex,
        "ai_digest":       ai_digest_hex,
        "beneficiary_ref": req.beneficiary_id,
        "explorer":        f"https://mstscan.com/tx/{tx_hash}",
    }


@app.post("/visit")
async def submit_visit(req: VisitRequest):
    """
    APK outbox → StipendVault.submitVisit()
    Relay computes the visit key and submits it for hospital attestation.
    """
    if chain is None:
        raise HTTPException(status_code=503, detail="Relay in offline mode")

    if not worker_exists(req.worker_address):
        raise HTTPException(status_code=404, detail="Worker not found in key store")

    worker_account = load_worker_account(req.worker_address)

    # Compute visit key
    b_commit = beneficiary_commitment(req.beneficiary_id, req.family_salt)
    vk_bytes = visit_key(b_commit, req.task_type, req.period)
    vk_hex   = "0x" + vk_bytes.hex()

    try:
        tx_hash = chain.submit_visit(
            visit_key_hex=vk_hex,
            task_type=req.task_type,
            worker_account=worker_account,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Visit submit failed: {str(e)}")

    return {
        "tx_hash":   tx_hash,
        "visit_key": vk_hex,
        "explorer":  f"https://mstscan.com/tx/{tx_hash}",
    }


@app.post("/batch-attest")
async def batch_attest_visits(
    req: BatchAttestRequest,
    x_admin_secret: str | None = Header(None),
):
    """
    Admin: Batch-attests an ASHA worker's monthly survey batch in 1 on-chain transaction.
    Transfers CareCoin rewards directly to worker wallets without bureaucratic delay.
    """
    _check_admin(x_admin_secret)

    if chain is None:
        raise HTTPException(status_code=503, detail="Relay in offline mode")

    if not req.visit_keys:
        raise HTTPException(status_code=400, detail="Empty visit keys list")

    try:
        tx_hash = chain.batch_attest(req.visit_keys)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Batch attest failed: {str(e)}")

    return {
        "status":         "success",
        "tx_hash":        tx_hash,
        "attested_count": len(req.visit_keys),
        "explorer":       f"https://mstscan.com/tx/{tx_hash}",
    }



@app.get("/verify/{record_hash}")
async def verify_record(record_hash: str):
    """
    Public read-only endpoint for hospital verifier web app.
    Given a record hash (from QR code), returns full on-chain status.
    """
    if chain is None:
        raise HTTPException(status_code=503, detail="Relay in offline mode")

    # Normalize
    if not record_hash.startswith("0x"):
        record_hash = "0x" + record_hash

    try:
        anchor = chain.get_anchor(record_hash)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Verify failed: {str(e)}")

    worker_active = False
    if anchor["exists"] and anchor["anchoredBy"] != "0x" + "00" * 20:
        try:
            worker_active = chain.is_worker_active(anchor["anchoredBy"])
        except Exception:
            pass

    return {
        "record_hash":     record_hash,
        "anchored":        anchor["exists"],
        "anchored_by":     anchor.get("anchoredBy"),
        "anchored_at":     anchor.get("anchoredAt"),
        "ai_digest":       anchor.get("aiDigest"),
        "worker_active":   worker_active,
        "explorer":        f"https://mstscan.com/address/{record_hash}" if anchor["exists"] else None,
    }


@app.get("/worker/{address}")
async def worker_status(address: str):
    """Worker's on-chain status and CareCoin balance."""
    if chain is None:
        raise HTTPException(status_code=503, detail="Relay in offline mode")

    try:
        active  = chain.is_worker_active(address)
        balance = chain.care_coin_balance(address)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {
        "address":    address,
        "active":     active,
        "care_balance": balance,
    }


@app.get("/workers")
async def list_all_workers(x_admin_secret: str | None = Header(None)):
    """Admin: list all registered workers (no private keys exposed)."""
    _check_admin(x_admin_secret)
    return list_workers()
