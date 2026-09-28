// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IReg.sol";

/// @title ConsentRegistry — Patient data access consent management
/// @dev Consent is granted by the worker on behalf of the patient.
///      Patient is represented as a keccak256 commitment (never raw Aadhaar/phone).
///      Consent auto-expires at `expiry` timestamp.
///      Category bitmask: bit 0 = maternal, bit 1 = general, bit 2 = emergency, etc.
contract ConsentRegistry {
    IReg public immutable reg;

    struct Consent {
        bytes32 patient;    // keccak256(beneficiaryId + familySalt) — no PII
        address provider;   // hospital authorized to access
        uint16 categories;  // bitmask: 1=maternal 2=general 4=emergency
        uint64 expiry;      // unix timestamp — access ends automatically
        bool revoked;       // worker-initiated early revocation
        address grantedBy;  // which worker granted this
    }

    Consent[] public consents;

    // Category constants — use in UI and relay
    uint16 public constant CAT_MATERNAL  = 1;
    uint16 public constant CAT_GENERAL   = 2;
    uint16 public constant CAT_EMERGENCY = 4;

    event Granted(
        uint256 indexed id,
        bytes32 indexed patient,
        address indexed provider,
        uint16 categories,
        uint64 expiry,
        address grantedBy
    );
    event ConsentRevoked(uint256 indexed id, address revokedBy);
    event Accessed(uint256 indexed id, address indexed by, uint16 category, uint256 at);

    modifier onlyActiveWorker() {
        require(reg.isActive(msg.sender), "ConsentRegistry: worker not active");
        _;
    }

    constructor(address registryAddress) {
        reg = IReg(registryAddress);
    }

    /// @notice Worker grants consent for a patient to a provider for specific categories and duration.
    /// @param patient   keccak256(beneficiaryId + familySalt) — computed on-device, never raw ID
    /// @param provider  Hospital address (set via BridgeKey in the web app)
    /// @param categories Bitmask of data categories allowed
    /// @param expiry    Unix timestamp when access ends automatically
    /// @return id The consent record index
    function grant(
        bytes32 patient,
        address provider,
        uint16 categories,
        uint64 expiry
    ) external onlyActiveWorker returns (uint256 id) {
        require(provider != address(0), "ConsentRegistry: zero provider");
        require(categories > 0, "ConsentRegistry: no categories");
        require(expiry > block.timestamp, "ConsentRegistry: expiry in past");

        consents.push(Consent({
            patient: patient,
            provider: provider,
            categories: categories,
            expiry: expiry,
            revoked: false,
            grantedBy: msg.sender
        }));

        id = consents.length - 1;
        emit Granted(id, patient, provider, categories, expiry, msg.sender);
    }

    /// @notice Worker revokes consent early.
    function revoke(uint256 id) external onlyActiveWorker {
        require(id < consents.length, "ConsentRegistry: invalid id");
        consents[id].revoked = true;
        emit ConsentRevoked(id, msg.sender);
    }

    /// @notice Check if a provider is currently authorized for a specific category.
    function isAllowed(uint256 id, address who, uint16 category) public view returns (bool) {
        if (id >= consents.length) return false;
        Consent storage c = consents[id];
        return (
            !c.revoked &&
            c.provider == who &&
            block.timestamp < c.expiry &&
            (c.categories & category) != 0
        );
    }

    /// @notice Hospital logs an access event (on-chain audit trail).
    function logAccess(uint256 id, uint16 category) external {
        require(isAllowed(id, msg.sender, category), "ConsentRegistry: not allowed");
        emit Accessed(id, msg.sender, category, block.timestamp);
    }

    /// @notice Get full consent details (for web verifier).
    function getConsent(uint256 id) external view returns (Consent memory) {
        require(id < consents.length, "ConsentRegistry: invalid id");
        return consents[id];
    }

    /// @notice Total number of consent records ever issued.
    function totalConsents() external view returns (uint256) {
        return consents.length;
    }
}
