// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";

/// @title PriceOracle
/// @notice Maps market ids (e.g. bytes32("BTC")) to Chainlink feeds and serves trusted prices.
contract PriceOracle is Ownable {
    using Math for uint256;

    uint256 public constant PRICE_PRECISION = 1e18;

    struct Market {
        IPriceFeed feed;
        uint8 feedDecimals;
        bool enabled;
    }

    mapping(bytes32 => Market) public markets;
    uint256 public maxPriceAge; // staleness tolerance, in seconds

    event MarketSet(bytes32 indexed market, address feed, bool enabled);
    event MaxPriceAgeSet(uint256 maxPriceAge);

    error MarketDisabled();
    error BadPrice();
    error InvalidParam();

    constructor(address admin, uint256 maxPriceAge_) Ownable(admin) {
        _setMaxPriceAge(maxPriceAge_);
    }

    // ---- admin ----

    function setMarket(bytes32 market, IPriceFeed feed, bool enabled) external onlyOwner {
        markets[market] = Market(feed, feed.decimals(), enabled);
        emit MarketSet(market, address(feed), enabled);
    }

    function setMaxPriceAge(uint256 maxPriceAge_) external onlyOwner {
        _setMaxPriceAge(maxPriceAge_);
    }

    function _setMaxPriceAge(uint256 maxPriceAge_) internal {
        if (maxPriceAge_ == 0) revert InvalidParam();
        maxPriceAge = maxPriceAge_;
        emit MaxPriceAgeSet(maxPriceAge_);
    }

    // ---- read ----

    /// @notice Latest price of `market`, scaled to 1e18, reverting if unusable.
    function getPrice(bytes32 market) external view returns (uint256) {
        Market memory m = markets[market];
        if (!m.enabled) revert MarketDisabled();

        (, int256 answer,, uint256 updatedAt,) = m.feed.latestRoundData();
        if (answer <= 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxPriceAge) {
            revert BadPrice();
        }
        return uint256(answer).mulDiv(PRICE_PRECISION, 10 ** m.feedDecimals);
    }
}