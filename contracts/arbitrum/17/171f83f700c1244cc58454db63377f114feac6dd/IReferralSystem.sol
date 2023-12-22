// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IReferralSystem {
    //Referrer, discount, rebate
    function getDiscountable(address _account) external view returns(address, uint256, uint256);
}
