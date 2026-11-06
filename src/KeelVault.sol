// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title KeelVault
/// @notice LP vault for the Keel perpetual protocol. Step 2: LP side only.
contract KeelVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Keel LP Share", "kLP") ERC4626(asset_) {}

    /// @dev Virtual-share offset: blunts the first-depositor inflation attack.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
