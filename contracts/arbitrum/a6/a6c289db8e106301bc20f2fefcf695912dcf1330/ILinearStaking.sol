// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./IERC20.sol";

interface ILinearStaking {
    error BeforeStakingStart();
    error AfterStakingFinish();
    error AmountZero();
    error RewardBalanceTooSmall();
    error NotValidUnlockTimestamp();
    error ToEarlyToWithdrawReward();
    error TooSmallAmount();
    error StartNotValid();

    event Staked(address indexed wallet, uint256 amount);
    event Unstaked(address indexed wallet, uint256 amount);
    event RewardTaken(address indexed wallet, uint256 amount);
    event Initialized(
        uint256 start,
        uint256 duration,
        uint256 reward,
        uint256 unlockTokensTimestamp
    );

    function stake(uint256) external;

    function unlockTokens(IERC20 token, address _to, uint256 _amount) external;

    function withdraw(uint256) external payable;

    function earned(address _account) external view returns (uint256);

    function start() external view returns (uint256);

    function finishAt() external view returns (uint256);

    function stakingToken() external view returns (IERC20);

    function rewardToken() external view returns (IERC20);

    function totalSupply() external view returns (uint256);

    function duration() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function unlockTokensTimestamp() external view returns (uint256);
}

