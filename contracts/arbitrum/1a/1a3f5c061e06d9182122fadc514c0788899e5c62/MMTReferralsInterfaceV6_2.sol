// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface MMTReferralsInterfaceV6_2 {
    function registerPotentialReferrer(address trader, address referral)
        external;

    function distributePotentialReward(
        address trader,
        uint256 volumeDai,
        uint256 pairOpenFeeP,
        uint256 tokenPriceDai
    ) external returns (uint256);

    function getPercentOfOpenFeeP(address trader)
        external
        view
        returns (uint256);

    function getTraderReferrer(address trader)
        external
        view
        returns (address referrer);
}

