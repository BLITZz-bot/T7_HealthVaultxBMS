// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IReg.sol";

/// @title RecordAnchor — Immutable integrity proof for clinical visit records and AI outputs
/// @dev Workers anchor the keccak256 Merkle root of a visit's canonical vitals JSON.
///      If the AI model (sepsis/NEWS2) flags a high-risk result, an aiDigest is also anchored:
///        aiDigest = keccak256(abi.encodePacked(modelVersion, inputHash, outputLabel))
///      The hospital verifier re-computes the hash client-side and compares to the anchored value.
///      Editing even one vital makes the comparison fail visibly (tamper detection).
contract RecordAnchor {
    IReg public immutable reg;

    struct Anchor {
        address anchoredBy;   // which worker anchored this
        uint64  anchoredAt;   // block.timestamp at anchor time
        bytes32 aiDigest;     // optional: keccak256(modelVersion+inputHash+outputLabel), or bytes32(0)
        bool    exists;       // guard flag
    }

    /// @notice root → Anchor. Root is keccak256 of canonical JSON of all vitals in the visit.
    mapping(bytes32 => Anchor) public anchors;

    event Anchored(
        bytes32 indexed root,
        address indexed anchoredBy,
        bytes32 aiDigest,
        uint64 anchoredAt
    );
    event TamperAlarm(bytes32 indexed root, address indexed checkedBy);

    modifier onlyActiveWorker() {
        require(reg.isActive(msg.sender), "RecordAnchor: worker not active");
        _;
    }

    constructor(address registryAddress) {
        reg = IReg(registryAddress);
    }

    /// @notice Anchor a visit record's integrity proof.
    /// @param root      keccak256 of canonical JSON vitals (computed in Dart + Python + JS identically)
    /// @param aiDigest  keccak256(modelVersion + inputHash + outputLabel), or bytes32(0) if no AI flag
    function anchor(bytes32 root, bytes32 aiDigest) external onlyActiveWorker {
        require(root != bytes32(0), "RecordAnchor: empty root");
        require(!anchors[root].exists, "RecordAnchor: already anchored");

        anchors[root] = Anchor({
            anchoredBy: msg.sender,
            anchoredAt: uint64(block.timestamp),
            aiDigest: aiDigest,
            exists: true
        });

        emit Anchored(root, msg.sender, aiDigest, uint64(block.timestamp));
    }

    /// @notice Returns true if a root has been anchored (record is real and unaltered since anchoring).
    function exists(bytes32 root) external view returns (bool) {
        return anchors[root].exists;
    }

    /// @notice Full anchor data for the web verifier.
    function getAnchor(bytes32 root) external view returns (Anchor memory) {
        return anchors[root];
    }

    /// @notice Emits a tamper alarm event (called by hospital verifier when hash mismatch detected).
    ///         This is on-chain evidence of a detected tampering attempt.
    /// @param root The claimed root that did NOT match the anchored value.
    function reportTamper(bytes32 root) external {
        emit TamperAlarm(root, msg.sender);
    }
}
