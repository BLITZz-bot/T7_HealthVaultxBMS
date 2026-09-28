// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IReg.sol";

/// @title StipendVault — Automated CareCoin stipend payout on hospital attestation
/// @dev Flow:
///   1. Admin funds vault with CareCoin and sets rates per task type.
///   2. Admin authorizes hospital address(es).
///   3. Worker submits a visit key (off-chain computed, no PII).
///   4. Hospital calls attestAndPay — CareCoin sent automatically to worker.
///   5. Same visitKey can never be paid twice (double-pay guard).
///
///   visitKey = keccak256(beneficiaryCommitment + taskType + period)
///   period   = "2026-09" (year-month string, no timestamp/GPS — prevents replay)
contract StipendVault {
    address public admin;
    IReg    public immutable reg;
    IERC20  public immutable token;

    mapping(address => bool)   public hospitals;
    mapping(uint8 => uint256)  public rate;          // taskType → CARE amount (wei)

    struct Visit {
        address worker;
        uint8   taskType;
        bool    paid;
        uint64  submittedAt;
    }

    mapping(bytes32 => Visit) public visits;

    // Task type constants
    uint8 public constant TASK_HOME_VISIT      = 1;
    uint8 public constant TASK_ANC_CHECKUP     = 2;
    uint8 public constant TASK_IMMUNIZATION    = 3;
    uint8 public constant TASK_DELIVERY_ESCORT = 4;
    uint8 public constant TASK_NEONATAL_VISIT  = 5;

    event HospitalAuthorized(address indexed hospital, bool authorized);
    event RateSet(uint8 indexed taskType, uint256 amount);
    event VisitSubmitted(bytes32 indexed visitKey, address indexed worker, uint8 taskType, uint64 at);
    event StipendPaid(bytes32 indexed visitKey, address indexed worker, uint256 amount, address attestedBy);
    event VaultFunded(address indexed by, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "StipendVault: admin only");
        _;
    }

    modifier onlyHospital() {
        require(hospitals[msg.sender], "StipendVault: not authorized hospital");
        _;
    }

    constructor(address registryAddress, address tokenAddress) {
        admin   = msg.sender;
        reg     = IReg(registryAddress);
        token   = IERC20(tokenAddress);
    }

    // ─── Admin configuration ────────────────────────────────────────────────

    /// @notice Authorize or de-authorize a hospital (BridgeKey address from web app).
    function setHospital(address hospital, bool authorized) external onlyAdmin {
        hospitals[hospital] = authorized;
        emit HospitalAuthorized(hospital, authorized);
    }

    /// @notice Set CARE payout per task type (in token wei, e.g. 10 ether = 10 CARE).
    function setRate(uint8 taskType, uint256 amount) external onlyAdmin {
        rate[taskType] = amount;
        emit RateSet(taskType, amount);
    }

    /// @notice Transfer admin to new address.
    function transferAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    /// @notice Returns vault's current CARE balance.
    function vaultBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // ─── Worker flow ─────────────────────────────────────────────────────────

    /// @notice Worker submits a visit for pending hospital attestation.
    /// @param visitKey keccak256(beneficiaryCommitment + taskType + period)
    ///                 period = "YYYY-MM" string — prevents same-month replay
    /// @param taskType One of the TASK_* constants above
    function submitVisit(bytes32 visitKey, uint8 taskType) external {
        require(reg.isActive(msg.sender),         "StipendVault: worker not active");
        require(visits[visitKey].worker == address(0), "StipendVault: duplicate visit");
        require(rate[taskType] > 0,               "StipendVault: unknown task type");

        visits[visitKey] = Visit({
            worker:      msg.sender,
            taskType:    taskType,
            paid:        false,
            submittedAt: uint64(block.timestamp)
        });

        emit VisitSubmitted(visitKey, msg.sender, taskType, uint64(block.timestamp));
    }

    modifier onlyAuthorized() {
        require(msg.sender == admin || hospitals[msg.sender], "StipendVault: not authorized");
        _;
    }

    // ─── Attestation & Payout flow ──────────────────────────────────────────

    /// @notice Attests a single visit and triggers CareCoin payment.
    /// @param visitKey Must match a previously submitted visit key.
    function attestAndPay(bytes32 visitKey) public onlyAuthorized {
        Visit storage v = visits[visitKey];
        require(v.worker != address(0), "StipendVault: visit not found");
        require(!v.paid,                "StipendVault: already paid");

        v.paid = true;
        uint256 payout = rate[v.taskType];

        require(
            token.transfer(v.worker, payout),
            "StipendVault: CARE transfer failed"
        );

        emit StipendPaid(visitKey, v.worker, payout, msg.sender);
    }

    /// @notice Batch attests multiple visits in a single transaction (monthly claim payout).
    /// @dev Allows Admin / Verifier to approve an ASHA worker's monthly survey batch with 1 signature.
    /// @param visitKeys Array of visit keys to attest and pay.
    function batchAttest(bytes32[] calldata visitKeys) external onlyAuthorized {
        require(visitKeys.length > 0, "StipendVault: empty batch");
        for (uint256 i = 0; i < visitKeys.length; i++) {
            attestAndPay(visitKeys[i]);
        }
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    function getVisit(bytes32 visitKey) external view returns (Visit memory) {
        return visits[visitKey];
    }
}
