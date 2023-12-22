//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGambitReferralsV1 {
    function registerPotentialReferrer(
        address trader,
        address referral
    ) external;

    function distributePotentialReward(
        address trader,
        uint volumeUsdc,
        uint pairOpenFeeP,
        uint tokenPriceUsdc
    ) external returns (uint referrerRewardValueUsdc, bool enabledUsdcReward);

    function getPercentOfOpenFeeP(address trader) external view returns (uint);

    function getTraderReferrer(
        address trader
    ) external view returns (address referrer);
}

