// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Minimal Chainlink AggregatorV3 interface: only what we read.
interface IPriceFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80);
}

/// @title KeelVault
/// @notice LP vault for the Keel perpetual protocol. Step 3: LP side + price oracle.
contract KeelVault is ERC4626 {
    using Math for uint256;

    uint256 public constant PRICE_PRECISION = 1e18;

    struct Market {
        IPriceFeed feed;
        uint8 feedDecimals;
        bool enabled;
    }

    mapping(bytes32 => Market) public markets; // e.g. bytes32("BTC") => its Chainlink feed
    uint256 public maxPriceAge; // oracle staleness tolerance, in seconds

    error MarketDisabled();
    error BadPrice();

    constructor(IERC20 asset_) ERC20("Keel LP Share", "kLP") ERC4626(asset_) {}

    /// @dev Virtual-share offset: blunts the first-depositor inflation attack.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice Latest price of `market`, scaled to 1e18, reverting if unusable.
    function getPrice(bytes32 market) public view returns (uint256) {
        Market memory m = markets[market];
        if (!m.enabled) revert MarketDisabled();

        (, int256 answer,, uint256 updatedAt,) = m.feed.latestRoundData();
        if (answer <= 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxPriceAge) {
            revert BadPrice();
        }
        return uint256(answer).mulDiv(PRICE_PRECISION, 10 ** m.feedDecimals);
    }
}