// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface yVault {
    function deposit(uint256) external;

    function depositAll() external;

    function withdraw(uint256) external;

    function withdrawAll() external;

    function pricePerShare() external view returns (uint256);
}