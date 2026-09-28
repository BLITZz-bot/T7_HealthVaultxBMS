# T7 HealthVault — Comprehensive System Architecture & Engineering Specification

## 1. Executive Summary

**T7 HealthVault** is an enterprise-grade, offline-first clinical Electronic Health Record (EHR) and **Blockchain-Verified Incentive Platform** engineered for Accredited Social Health Activists (ASHA), Community Health Officers (CHOs), and Primary Health Centres (PHCs) across India.

The platform solves two massive systemic issues:
1. **Lack of offline clinical intelligence**: By running quantized LLMs and NEWS2 algorithms entirely on-device, ASHAs get zero-latency decision support without internet.
2. **Delayed stipends & phantom paperwork**: By introducing a zero-PII cryptographic proof-of-visit system anchored to the **MST EVM Blockchain**, the platform automatically disburses `CareCoin` (MSTC) tokens upon verification, eliminating payment delays and blocking duplicate/fraudulent claims.

---

## 2. System Architecture & Component Topology

```text
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       CLIENT TIER                                            │
│  ┌─────────────────────────────────────┐      ┌───────────────────────────────────────────┐  │
│  │         Flutter Mobile App          │      │            Next.js Web Portal             │  │
│  │        (ASHA Offline Client)        │      │         (Admin / Hospital Verifier)       │  │
│  │                                     │      │                                           │  │
│  │ • Local SQLite (chain_outbox queue) │      │ • Dashboard analytics                     │  │
│  │ • On-Device Qwen GGUF LLM           │      │ • Supabase Real-time Subscriptions        │  │
│  │ • Keccak-256 Hashing Engine         │      │ • BridgeKey / MetaMask Integration        │  │
│  │ • Patient QR Code Identity Hash     │      │ • Trigger /batch-attest to Relayer        │  │
│  └──────────────────┬──────────────────┘      └─────────────────────┬─────────────────────┘  │
└─────────────────────┼───────────────────────────────────────────────┼────────────────────────┘
            Offline-to-Online Sync                             Admin API Calls
┌─────────────────────▼───────────────────────────────────────────────▼────────────────────────┐
│                               RELAYER & API TIER (Python)                                    │
│  ┌────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              FastAPI Blockchain Relayer                                │  │
│  │ • Validates Zero-PII Hashes from Mobile      • Prepares Payload for Smart Contract     │  │
│  │ • Interacts with Supabase (Database)         • Signs Tx with ADMIN_PRIVATE_KEY         │  │
│  │ • Acts as a Gas Station for ASHAs            • Broadcasts to MST RPC                   │  │
│  └───────────────────────────────────┬──────────────────────────────┬─────────────────────┘  │
└──────────────────────────────────────┼──────────────────────────────┼────────────────────────┘
                                       │                              │
┌──────────────────────────────────────▼────────────┐  ┌──────────────▼────────────────────────┐
│                 DATA PERSISTENCE                  │  │          MST EVM BLOCKCHAIN           │
│  ┌─────────────────────────────────────────────┐  │  │  ┌─────────────────────────────────┐  │
│  │           Supabase (PostgreSQL)             │  │  │  │         CareCoin.sol            │  │
│  │ • Cloud Sync for Medical Records            │  │  │  │  (ERC-20 Token for Incentives)  │  │
│  │ • Row-Level Security (RLS) policies         │  │  │  ├─────────────────────────────────┤  │
│  │ • User Authentication & Roles               │  │  │  │       StipendVault.sol          │  │
│  │ • Mapping: ABHA ID <-> Wallet <-> Clinics   │  │  │  │  (Escrow & Batch Verification)  │  │
│  └─────────────────────────────────────────────┘  │  │  └─────────────────────────────────┘  │
└───────────────────────────────────────────────────┘  └───────────────────────────────────────┘
```

---

## 3. Detailed Component Specifications

### 3.1 Flutter Mobile App (The Edge Node)
* **Architecture**: Offline-first MVVM.
* **Database**: Encrypted SQLite (sqflite). Stores families, members, vitals, and the `chain_outbox`.
* **Clinical Intelligence**:
  * **NEWS2 Scoring**: National Early Warning Score 2 algorithms calculate acute illness severity dynamically.
  * **Sepsis AI**: On-device statistical models assess deterioration risk using physiological deltas.
  * **Generative LLM**: `Qwen3-1.7B-Q4_K_M.gguf` (~1.05 GB) running locally via `fllama`/`langchain`. Explains medical conditions in 22 Indian languages.
* **Blockchain Responsibilities**:
  * Calculates `beneficiaryCommitment` (a hash of the patient's ABHA/ID + a salt) to embed in a QR code.
  * Applies `keccak256` hashing to the exact JSON schema of patient vitals locally.
  * Queues hashes in `chain_outbox` until connectivity is restored.

### 3.2 FastAPI Relayer (The Gas Station)
* **Architecture**: Stateless Python microservice.
* **Why it exists**: ASHA workers lack crypto literacy and funds. They cannot pay gas fees for blockchain transactions.
* **Mechanism**:
  * Receives signed hashes from the mobile app.
  * Uses `web3.py` and an injected `ADMIN_PRIVATE_KEY` (holding $MSTC) to format and sign the transaction.
  * Broadcasts the transaction to the MST testnet, completely abstracting the blockchain complexity from the end user.
* **Batching**: Exposes `/batch-attest` to allow the Admin portal to process up to 50 queued visits in a single transaction, reducing network load and gas costs by ~90%.

### 3.3 MST Blockchain Smart Contracts
* **Network**: MST Testnet (EVM Compatible, Cancun/Paris architecture).
* **CareCoin.sol**: An ERC-20 compliant token contract. Represents the monetary stipend the ASHA worker earns per verified visit.
* **StipendVault.sol**: The master escrow contract. 
  * Holds a reserve of CareCoins.
  * `batchAttest()`: Accepts an array of worker addresses and `taskHash` arrays.
  * Maps `executedTasks[taskHash] = true` to mathematically prevent replay attacks or duplicate paperwork fraud.
  * Transfers CareCoins to the ASHA worker's wallet instantly upon execution.

### 3.4 Supabase (PostgreSQL Cloud)
* **Role**: Primary cloud synchronization engine for human-readable data.
* **Mechanics**:
  * The Flutter app syncs the actual vital statistics (Heart rate, BP, glucose) to Supabase when online.
  * Supabase handles user authentication (Admin vs. ASHA).
  * Data is protected by strict Row-Level Security (RLS). ASHA workers can only read/write their assigned village; Admins can see aggregated district data.

### 3.5 Next.js Web Portal (The Verifier Dashboard)
* **Role**: The interface for PHC Hospital Admins and State Health Directors.
* **Capabilities**:
  * Pulls pending records from Supabase.
  * Scans the Patient's QR code when the patient physically visits the PHC for a referral.
  * Clicks "Approve Batch" to trigger the FastAPI Relayer, which finalizes the transaction on the blockchain and releases the funds.

---

## 4. Security, Privacy & The "Zero-PII" Protocol

### 4.1 HIPAA/ABHA Compliant Hashing
The core principle of HealthVault is that **no patient name, ID, or raw clinical data ever touches a public blockchain**.
1. **The Formula**: `taskHash = keccak256( beneficiaryCommitment + task_type + timestamp + keccak256(vitals_json) )`.
2. **The Result**: The blockchain only records a random-looking 32-byte string (e.g., `0x4f8b...`). 
3. **Verification**: If an auditor wants to verify the data later, they must possess the raw SQLite/Supabase data. Running the hash algorithm on the raw data will produce the exact same `taskHash` found on the blockchain, proving the data was not tampered with.

### 4.2 Mathematical Anti-Fraud
* **Phantom Paperwork**: ASHA workers cannot submit fake records for stipends. The `StipendVault.sol` contract registers every `taskHash`. Submitting the same hash twice results in an immediate EVM revert (`Duplicate visit proof: already claimed`).
* **Relay Rate-Limiting**: The FastAPI relayer blocks excessive requests from a single worker ID, preventing DDoS or brute-force stipend draining.

---

## 5. Directory & Repository Structure

```
T7_HealthVault/
├── flutter_app/                     # Flutter Edge Client
│   ├── lib/
│   │   ├── services/
│   │   │   ├── blockchain_service.dart # Hashing & Outbox management
│   │   │   ├── local_db_service.dart   # SQLite initialization
│   │   │   ├── on_device_llm_service.dart # GGUF neural engine
│   │   │   └── sepsis_inference_service.dart
│   │   ├── screens/
│   │   │   ├── qr_screen.dart          # Identity QR generator
│   │   │   ├── asha_home_screen.dart   
│   │   │   └── member_detail_screen.dart # EHR view with Chain Badges
│   │   └── models/
│
├── backend/                         # FastAPI Meta-Tx Relayer
│   ├── main.py                      # REST endpoints and Web3 logic
│   ├── hasher.py                    # Reference Keccak-256 implementation
│   ├── requirements.txt
│   └── Dockerfile
│
├── blockchain/                      # Hardhat Smart Contracts (MST Testnet)
│   ├── contracts/
│   │   ├── CareCoin.sol             
│   │   └── StipendVault.sol         
│   ├── test/
│   │   └── healthvault.test.js      # Comprehensive Mocha/Chai EVM tests
│   ├── scripts/
│   │   └── deploy.js                # Deployment pipeline
│   └── hardhat.config.js
│
└── web_app/                         # Next.js Verifier Dashboard (Pending)
    ├── src/
    │   ├── app/                     # Next 14 App Router
    │   ├── components/
    │   └── lib/supabase.ts          # Supabase client instantiation
    ├── package.json
    └── tailwind.config.ts
```
