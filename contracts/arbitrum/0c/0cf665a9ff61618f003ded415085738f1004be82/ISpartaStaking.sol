//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

interface ISpartaStaking {
    error RewardBalanceTooSmall();
    error BeforeStakingStart();
    error AfterStakingFinish();
    error TokensAlreadyClaimed();
    error RoundDoesNotExist();
    error BeforeReleaseTime();
    error NotValidUnlockTimestamp();
    error ToEarlyToWithdrawReward();
    error StartNotValid();
    error MinimalUnstakingPeriod();
    error CannotUnstake();
    error CurrentImplementation();

    struct TokensToClaim {
        bool taken;
        uint256 release;
        uint256 value;
    }

    event Staked(address indexed wallet, uint256 value);
    event Unstaked(
        address indexed wallet,
        uint256 tokensAmount,
        uint256 tokensToClaim,
        uint256 duration
    );
    event TokensClaimed(
        address indexed wallet,
        uint256 indexed roundId,
        uint256 tokensToClaimid
    );
    event RewardTaken(address indexed wallet, uint256 amount);

    event Initialized(
        uint256 start,
        uint256 duration,
        uint256 reward,
        uint256 unlockTokensTimestamp
    );

    event MovedToNextImplementation(
        address indexed by,
        uint256 balance,
        uint256 reward
    );

    function finishAt() external view returns (uint256);

    function stake(uint256 amount) external;

    function stakeAs(address wallet, uint256 amount) external;

    function unlockTokens(address to, uint256 amount) external;

    function unlockTokensTimestamp() external view returns (uint256);
}

