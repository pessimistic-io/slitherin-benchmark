pragma solidity >0.8.0;

interface IArkenOptionRewarder {
    error NoPosition();
    error PositionRewarded(uint256 positionTokenId);
    error InvalidExerciseAmountMinLength(
        uint256 length,
        uint256 expectedLength
    );
    error InsufficientRemainingArken();
    error InsufficientExerciseAmount(uint256 amount, uint256 amountMin);
    error InsufficientLockTime(uint256 lockTime, uint256 minimumLockTime);
    error NotSupportedPair(address pair);

    event SetConfiguration(
        address indexed pair,
        address sender,
        RewardConfiguration[] configs
    );
    event DeleteConfiguration(address indexed pair, address sender);
    event SetRemainingArken(uint256 remainingArken, address sender);
    event RewardOptionNFT(
        uint256 tokenId,
        address pair,
        uint256 unlockedAt,
        uint256 expiredAt,
        uint256 unlockPrice,
        uint256 exercisePrice,
        uint256 exerciseAmount
    );

    function arken() external view returns (address);

    function optionNFT() external view returns (address);

    function remainingArken() external view returns (uint256);

    function setRemainingArken(uint256) external;

    struct RewardConfiguration {
        uint256 lockTime;
        uint256 expiredTime;
        uint256 unlockPrice;
        uint256 exercisePrice;
        uint256 exerciseAmountFactor;
    }

    function setConfiguration(
        address pair,
        RewardConfiguration[] memory configs
    ) external;

    function deleteConfiguration(address pair) external;

    function configurations(
        address pair
    ) external view returns (RewardConfiguration[] memory);

    function configuration(
        address pair,
        uint256 idx
    ) external view returns (RewardConfiguration memory);

    struct RewardLongTermData {
        uint256[] exerciseAmountMins;
    }

    function rewardLongTerm(
        address to,
        address pair,
        uint256 positionTokenId,
        bytes calldata data
    ) external returns (uint256[] memory tokenIds);
}

