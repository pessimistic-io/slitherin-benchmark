// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IERC20.sol";

interface ITortleVault is IERC20 {
    function getPricePerFullShare() external view returns (uint256);

    function deposit(address user, uint256 amount) external returns (uint256);

    function withdraw(address user, uint256 shares) external returns (uint256, uint256);

    function token() external pure returns (address);
}

