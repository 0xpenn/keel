// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IKeelVault} from "./interfaces/IKeelVault.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/// @title KeelEngine
/// @notice Trader side of Keel: holds collateral and positions.
///         Step 7: open and increase positions. No fees, no PnL.
/// @dev `size` and `collateral` are in asset units (1 unit = 1 USD).
contract KeelEngine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Position {
        address owner;
        bytes32 market;
        bool isLong;
        uint256 size; // notional in USD (asset units)
        uint256 collateral; // asset units
        uint256 entryPrice; // 1e18-scaled
    }

    IERC20 public immutable asset;
    IKeelVault public immutable vault;
    IPriceOracle public immutable oracle;

    uint256 public maxLeverage; // max size / collateral
    uint256 public nextPositionId = 1;
    mapping(uint256 => Position) public positions;

    event MaxLeverageSet(uint256 maxLeverage);
    event PositionOpened(
        uint256 indexed id,
        address indexed owner,
        bytes32 indexed market,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice
    );
    event PositionIncreased(uint256 indexed id, uint256 sizeDelta, uint256 collateralDelta, uint256 newEntryPrice);

    error ZeroAmount();
    error InvalidParam();
    error LeverageTooHigh();
    error NotPositionOwner();

    constructor(IKeelVault vault_, IPriceOracle oracle_, address admin, uint256 maxLev) Ownable(admin) {
        vault = vault_;
        oracle = oracle_;
        asset = IERC20(vault_.asset()); // same token as the vault, by construction
        _setMaxLeverage(maxLev);
    }

    // ---- admin ----

    function setMaxLeverage(uint256 maxLev) external onlyOwner {
        _setMaxLeverage(maxLev);
    }

    function _setMaxLeverage(uint256 maxLev) internal {
        if (maxLev == 0) revert InvalidParam();
        maxLeverage = maxLev;
        emit MaxLeverageSet(maxLev);
    }

    // ---- traders ----

    /// @notice Open a position of `size` USD notional backed by `collateral`.
    function openPosition(bytes32 market, bool isLong, uint256 size, uint256 collateral)
        external
        nonReentrant
        returns (uint256 id)
    {
        if (size == 0 || collateral == 0) revert ZeroAmount();
        if (size > collateral * maxLeverage) revert LeverageTooHigh();

        uint256 price = oracle.getPrice(market); // reverts if disabled, bad or stale

        id = nextPositionId++;
        positions[id] = Position(msg.sender, market, isLong, size, collateral, price);

        asset.safeTransferFrom(msg.sender, address(this), collateral);
        vault.reserve(size); // reverts if it would breach the utilization cap

        emit PositionOpened(id, msg.sender, market, isLong, size, collateral, price);
    }

    /// @notice Grow a position, optionally topping up collateral. Entry price becomes size-weighted.
    function increasePosition(uint256 id, uint256 sizeDelta, uint256 collateralDelta) external nonReentrant {
        Position storage p = positions[id];
        if (p.owner != msg.sender) revert NotPositionOwner();
        if (sizeDelta == 0) revert ZeroAmount();

        uint256 newSize = p.size + sizeDelta;
        uint256 newCollateral = p.collateral + collateralDelta;
        if (newSize > newCollateral * maxLeverage) revert LeverageTooHigh();

        uint256 price = oracle.getPrice(p.market);
        p.entryPrice = (p.size * p.entryPrice + sizeDelta * price) / newSize;
        p.size = newSize;
        p.collateral = newCollateral;

        if (collateralDelta > 0) asset.safeTransferFrom(msg.sender, address(this), collateralDelta);
        vault.reserve(sizeDelta);

        emit PositionIncreased(id, sizeDelta, collateralDelta, p.entryPrice);
    }
}
