// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./IWrappedERC20.sol";

interface IWrappedGLP is IWrappedERC20 {
    function claimRewards() external;
    function getPrice() external view returns (uint256);
}
