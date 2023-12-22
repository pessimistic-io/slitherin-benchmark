// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface GNSReferralsInterfaceV6_2{
    function registerPotentialReferrer(address trader, address referral) external;
   	function distributePotentialReward(
        address trader,
        uint volumeDai,
        uint pairOpenFeeP,
        uint tokenPriceDai
    ) external returns(uint);
    function getPercentOfOpenFeeP(address trader) external view returns(uint);
    function getTraderReferrer(address trader) external view returns(address referrer);
}
