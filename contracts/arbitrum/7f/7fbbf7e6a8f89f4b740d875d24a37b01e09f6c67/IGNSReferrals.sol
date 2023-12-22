// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @custom:version 6.2
 */
interface IGNSReferrals {
    struct AllyDetails {
        address[] referrersReferred;
        uint256 volumeReferredDai; // 1e18
        uint256 pendingRewardsToken; // 1e18
        uint256 totalRewardsToken; // 1e18
        uint256 totalRewardsValueDai; // 1e18
        bool active;
    }

    struct ReferrerDetails {
        address ally;
        address[] tradersReferred;
        uint256 volumeReferredDai; // 1e18
        uint256 pendingRewardsToken; // 1e18
        uint256 totalRewardsToken; // 1e18
        uint256 totalRewardsValueDai; // 1e18
        bool active;
    }

    function registerPotentialReferrer(address trader, address referral) external;

    function distributePotentialReward(
        address trader,
        uint256 volumeDai,
        uint256 pairOpenFeeP,
        uint256 tokenPriceDai
    ) external returns (uint256);

    function getPercentOfOpenFeeP(address trader) external view returns (uint256);

    function getTraderReferrer(address trader) external view returns (address referrer);

    event UpdatedAllyFeeP(uint256 value);
    event UpdatedStartReferrerFeeP(uint256 value);
    event UpdatedOpenFeeP(uint256 value);
    event UpdatedTargetVolumeDai(uint256 value);

    event AllyWhitelisted(address indexed ally);
    event AllyUnwhitelisted(address indexed ally);

    event ReferrerWhitelisted(address indexed referrer, address indexed ally);
    event ReferrerUnwhitelisted(address indexed referrer);
    event ReferrerRegistered(address indexed trader, address indexed referrer);

    event AllyRewardDistributed(
        address indexed ally,
        address indexed trader,
        uint256 volumeDai,
        uint256 amountToken,
        uint256 amountValueDai
    );
    event ReferrerRewardDistributed(
        address indexed referrer,
        address indexed trader,
        uint256 volumeDai,
        uint256 amountToken,
        uint256 amountValueDai
    );

    event AllyRewardsClaimed(address indexed ally, uint256 amountToken);
    event ReferrerRewardsClaimed(address indexed referrer, uint256 amountToken);
}

