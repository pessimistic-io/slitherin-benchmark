// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDopexFeeStrategy {
 function getFeeBps(
        uint256 _feeType,
        address _user,
        bool _useDiscount
    ) external view returns (uint256 _feeBps);
}
