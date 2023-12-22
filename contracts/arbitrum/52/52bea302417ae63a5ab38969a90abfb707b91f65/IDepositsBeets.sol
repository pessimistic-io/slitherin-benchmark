// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IDepositsBeets {

    function getBptAddress(bytes32 poolId_) external view returns(address bptAddress);
    function joinPool(bytes32 poolId_, address[] memory tokens_, uint256[] memory amountsIn_) external returns(address bptAddress, uint256 bptAmount_);
    function exitPool(bytes32 poolId_, address bptToken_, address[] memory tokens_, uint256[] memory minAmountsOut_, uint256 bptAmount_) external returns(uint256 amountTokenDesired);
}
