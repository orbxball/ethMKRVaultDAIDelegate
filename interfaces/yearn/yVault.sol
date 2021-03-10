// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface yVault {
    function deposit() external;

    function deposit(uint256) external;

    function withdraw() external;

    function withdraw(uint256) external;

    function pricePerShare() external view returns (uint256);
}
