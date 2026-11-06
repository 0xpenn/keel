// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title KeelVault
/// @notice LP vault for the Keel perpetual protocol.
///         Step 4: LP side + liquidity reservation with a utilization cap.
contract KeelVault is ERC4626, Ownable {
    using Math for uint256;

    uint256 public constant BPS = 10_000;

    address public engine; // the only contract allowed to reserve/release
    uint256 public reservedLiquidity; // sum of open position sizes
    uint256 public maxUtilizationBps; // cap on reserved / totalAssets

    event EngineSet(address engine);
    event MaxUtilizationSet(uint256 maxUtilizationBps);
    event Reserved(uint256 amount, uint256 totalReserved);
    event Released(uint256 amount, uint256 totalReserved);

    error NotEngine();
    error EngineAlreadySet();
    error InvalidParam();
    error UtilizationExceeded();

    constructor(IERC20 asset_, address admin, uint256 maxUtilBps)
        ERC20("Keel LP Share", "kLP")
        ERC4626(asset_)
        Ownable(admin)
    {
        _setMaxUtilization(maxUtilBps);
    }

    modifier onlyEngine() {
        if (msg.sender != engine) revert NotEngine();
        _;
    }

    // ---- admin ----

    /// @notice One-time wiring of the engine. Cannot be changed afterwards.
    function setEngine(address engine_) external onlyOwner {
        if (engine != address(0)) revert EngineAlreadySet();
        if (engine_ == address(0)) revert InvalidParam();
        engine = engine_;
        emit EngineSet(engine_);
    }

    function setMaxUtilization(uint256 maxUtilBps) external onlyOwner {
        _setMaxUtilization(maxUtilBps);
    }

    function _setMaxUtilization(uint256 maxUtilBps) internal {
        if (maxUtilBps == 0 || maxUtilBps > BPS) revert InvalidParam();
        maxUtilizationBps = maxUtilBps;
        emit MaxUtilizationSet(maxUtilBps);
    }

    // ---- engine hooks ----

    /// @notice Lock `amount` of LP liquidity for a position, within the utilization cap.
    function reserve(uint256 amount) external onlyEngine {
        uint256 newReserved = reservedLiquidity + amount;
        if (newReserved > totalAssets().mulDiv(maxUtilizationBps, BPS)) revert UtilizationExceeded();
        reservedLiquidity = newReserved;
        emit Reserved(amount, newReserved);
    }

    /// @notice Unlock `amount` when a position shrinks or closes.
    function release(uint256 amount) external onlyEngine {
        reservedLiquidity -= amount;
        emit Released(amount, reservedLiquidity);
    }

    /// @dev Virtual-share offset: blunts the first-depositor inflation attack.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}