// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CareCoin — ERC-20 stipend token for ASHA workers
/// @dev 1,000,000 CARE minted to deployer on construction.
///      Deployer transfers supply to StipendVault after deploy.
///      CareCoin is test money representing a settlement rail toward DBT.
contract CareCoin is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether; // 1M CARE tokens

    constructor() ERC20("CareCoin", "CARE") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /// @notice Mint additional tokens if needed (admin only, for demo top-ups).
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
