// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.9;

import "./IERC165.sol";

interface ITokenizedVault is IERC165 {
    function deposit(uint256 depositAmount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amounts);
}
