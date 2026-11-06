// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Minimal Chainlink AggregatorV3 interface: only what we read.
interface IPriceFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80);
}