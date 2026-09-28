// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReg — Minimal interface for WorkerRegistry lookups
/// @dev Implemented by WorkerRegistry; consumed by ConsentRegistry, RecordAnchor, StipendVault
interface IReg {
    function isActive(address worker) external view returns (bool);
}
