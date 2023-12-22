// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./BaseDelegator.sol";

import "./GlpPriceFeed.sol";

import "./IGlpRewardRouter.sol";
import "./IGlpRewardReader.sol";
import "./IGlpRewardTracker.sol";

contract GmxIndex is BaseDelegator {
  /* solhint-disable no-empty-blocks */

  address public immutable rewardReader;

  GlpPriceFeed public immutable priceFeed;

  constructor(
    address asset,
    address indexContract,
    address rewardReader_,
    address priceFeed_
  ) BaseDelegator(asset, indexContract) {
    rewardReader = rewardReader_;

    priceFeed = GlpPriceFeed(priceFeed_);
  }

  function delegatorName()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "gmx";
  }

  function delegatorType()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "Index";
  }

  function deposit(uint256 amount) external virtual override onlyLinkedVault {
    claim();

    // Approve integration to spend balance from delegator
    SafeERC20.safeIncreaseAllowance(
      IERC20(asset()),
      underlyingContract(),
      amount
    );

    uint256 minGlpAmount = priceFeed.getMinPrice(amount);

    IGlpRewardRouter(underlyingContract()).mintAndStakeGlp(
      asset(),
      amount,
      0,
      minGlpAmount
    );

    emit Deposit(amount);
  }

  function withdraw(uint256 amount) external virtual override onlyLinkedVault {
    claim();

    uint256 minTokenOut = priceFeed.getMinPrice(amount);

    IGlpRewardRouter(underlyingContract()).unstakeAndRedeemGlp(
      asset(),
      amount,
      minTokenOut,
      linkedVault()
    );

    emit Withdraw(amount);
  }

  function totalAssets() public view virtual override returns (uint256) {
    address[] memory depositTokens = new address[](1);

    depositTokens[0] = asset();

    address[] memory rewardTrackers = new address[](2);

    rewardTrackers[0] = IGlpRewardRouter(underlyingContract()).feeGlpTracker();
    rewardTrackers[1] = IGlpRewardRouter(underlyingContract())
      .stakedGlpTracker();

    uint256[] memory amounts = IGlpRewardReader(rewardReader)
      .getDepositBalances(address(this), depositTokens, rewardTrackers);

    return amounts[0];
  }

  function rewards() public view virtual override returns (uint256) {
    uint256 glpFeeRewards = IGlpRewardTracker(
      IGlpRewardRouter(underlyingContract()).feeGlpTracker()
    ).claimable(address(this));

    uint256 glpRewards = IGlpRewardTracker(
      IGlpRewardRouter(underlyingContract()).stakedGlpTracker()
    ).claimable(address(this));

    return glpFeeRewards + glpRewards;
  }

  function claim() public virtual override {
    IGlpRewardRouter(underlyingContract()).compound();

    uint256 claimedRewards = address(this).balance;

    if (claimedRewards < claimableThreshold()) {
      return;
    }

    uint256 minGlpAmount = priceFeed.getMinPrice(claimedRewards);

    IGlpRewardRouter(underlyingContract()).mintAndStakeGlpETH{
      value: claimedRewards
    }(0, minGlpAmount);
  }
}

