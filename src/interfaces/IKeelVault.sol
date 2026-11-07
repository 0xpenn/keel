// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IKeelVault {
    function asset() external view returns (address);
    function reserve(uint256 amount) external;
    function release(uint256 amount) external;
}