// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IVault.sol";

interface IStrategy {
    event Invested(uint256 amount);
    event Withdrawn(uint256 amount);

    function underlying() external view returns (IERC20);

    function vault() external view returns (IVault);

    function totalAssets() external view returns (uint256);

    function invest() external;

    function withdraw(uint256 amount)
        external
        returns (uint256 actualWithdrawn);

    function withdrawAll() external returns (uint256 actualWithdrawn);
}

