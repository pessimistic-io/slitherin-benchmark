// SPDX-License-Identifier: MIT

//// _____.___.__       .__       ._____      __      .__   _____  ////
//// \__  |   |__| ____ |  |    __| _/  \    /  \____ |  |_/ ____\ ////
////  /   |   |  |/ __ \|  |   / __ |\   \/\/   /  _ \|  |\   __\  ////
////  \____   |  \  ___/|  |__/ /_/ | \        (  <_> )  |_|  |    ////
////  / ______|__|\___  >____/\____ |  \__/\  / \____/|____/__|    ////
////  \/              \/           \/       \/                     ////

pragma solidity 0.8.9;

import "./IERC20.sol";

interface IVault is IERC20 {
    function earn(address _bountyHunter) external returns (uint256);

    function deposit(address _user, uint256 _depositAmount) external;

    function withdraw(address _user, uint256 _withdrawAmount) external;

    function stakeToken() external view returns (address);

    function totalStakeTokens() external view returns (uint256);

    function yieldWolf() external view returns (address);
}

