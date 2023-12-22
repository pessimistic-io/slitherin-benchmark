// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IDopexFeeStrategy {
 function getFeeBps(
        uint256 feeType,
        address user,
        bool useDiscount
    ) external view returns (uint256 _feeBps);
}
