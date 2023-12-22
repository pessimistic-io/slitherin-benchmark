// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Staking20Base.sol";
import "./TokenERC20.sol";

contract StakingContract is Staking20Base {

    uint256 private rewardTokenBalance;

    constructor(
        uint256 _timeUnit,
        uint256 _rewardRatioNumerator,
        uint256 _rewardRatioDenominator,
        address _stakingToken,
        address _rewardToken,
        address _nativeTokenWrapper
    ) Staking20Base(
        _timeUnit,
        _rewardRatioNumerator,
        _rewardRatioDenominator,
        _stakingToken,
        _rewardToken,
        _nativeTokenWrapper
    ) {}

   function _mintRewards(address _staker, uint256 _rewards) internal virtual override {
    uint256 rewardTokenDecimalFactor = 10 ** 9; // 9 decimals

    uint256 rewardsWithDecimals = _rewards * rewardTokenDecimalFactor;
    require(rewardsWithDecimals <= rewardTokenBalance, "Not enough reward tokens");

    rewardTokenBalance -= rewardsWithDecimals;
    uint256 rewardsToTransfer = rewardsWithDecimals / rewardTokenDecimalFactor;
    CurrencyTransferLib.transferCurrencyWithWrapper(
        rewardToken,
        address(this),
        _staker,
        rewardsToTransfer,
        nativeTokenWrapper
        );
    }
}
