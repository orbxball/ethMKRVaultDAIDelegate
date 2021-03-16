// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface EACAggregatorProxy {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);
}
