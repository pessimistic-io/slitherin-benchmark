// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IReferralSystemV2 {
    //Referrer, discount, rebate
    function getDiscountable(address _account) external view returns(address, uint256, uint256, uint256);

    function getDiscountableInternal(address _account, uint256 _fee) external returns(address, uint256, uint256, uint256);

    function increaseCodeStat(address _account, uint256 _discountshareAmount, uint256 _rebateAmount, uint256 _esRebateAmount) external;
}
