// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IReg.sol";

/// @title WorkerRegistry — Manages ASHA worker identities on-chain
/// @dev Admin registers/revokes workers. Credential hash (keccak256 of off-chain data) stored.
///      This is the IReg implementation used by all downstream contracts.
contract WorkerRegistry is IReg {
    address public admin;

    /// @notice keccak256 of (workerName + phone + aadhaar) — no PII on-chain
    mapping(address => bytes32) public credential;

    /// @notice Whether a worker is currently active (not revoked)
    mapping(address => bool) public active;

    /// @notice Human-readable label stored off-chain; only an index stored here
    mapping(address => uint256) public workerIndex;
    uint256 public workerCount;

    event Registered(address indexed worker, bytes32 credentialHash, uint256 index);
    event Revoked(address indexed worker);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "WorkerRegistry: admin only");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /// @notice Register a new ASHA worker. Called by admin via BridgeKey or relay.
    /// @param worker   The worker's address (created by relay for custodial flow)
    /// @param credHash keccak256(workerName + phone + aadhaarLast4) — computed off-chain
    function register(address worker, bytes32 credHash) external onlyAdmin {
        require(worker != address(0), "WorkerRegistry: zero address");
        require(credHash != bytes32(0), "WorkerRegistry: empty hash");
        credential[worker] = credHash;
        active[worker] = true;
        workerIndex[worker] = ++workerCount;
        emit Registered(worker, credHash, workerCount);
    }

    /// @notice Revoke a worker (e.g. reassigned, suspended). Does not delete credential.
    function revoke(address worker) external onlyAdmin {
        active[worker] = false;
        emit Revoked(worker);
    }

    /// @notice Re-activate a previously revoked worker.
    function reactivate(address worker) external onlyAdmin {
        require(credential[worker] != bytes32(0), "WorkerRegistry: not registered");
        active[worker] = true;
        emit Registered(worker, credential[worker], workerIndex[worker]);
    }

    /// @notice IReg implementation — used by ConsentRegistry, RecordAnchor, StipendVault
    function isActive(address worker) external view override returns (bool) {
        return active[worker];
    }

    /// @notice Transfer admin role to another address (e.g. multi-sig later)
    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "WorkerRegistry: zero address");
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }
}
