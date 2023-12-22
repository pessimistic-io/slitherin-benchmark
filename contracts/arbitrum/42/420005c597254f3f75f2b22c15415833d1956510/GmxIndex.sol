// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./BaseDelegator.sol";

import "./GlpPriceFeed.sol";

import "./IGlpVault.sol";
import "./IGlpManager.sol";
import "./IGlpRewardRouter.sol";
import "./IGlpRewardReader.sol";

/// @title Gmx Index Delegator
/// @author Christopher Enytc <wagmi@munchies.money>
/// @dev All functions are derived from the base delegator
/// @custom:security-contact security@munchies.money
contract GmxIndex is BaseDelegator {
  using Math for uint256;

  address public immutable rewardReader;

  GlpPriceFeed public immutable glpPriceFeed;

  address public immutable weth;

  /**
   * @dev Set the underlying asset contract. This must be an ERC20 contract.
   */
  constructor(
    IERC20 asset_,
    address indexContract_,
    address rewardReader_,
    address glpPriceFeed_,
    address weth_
  ) BaseDelegator(asset_, indexContract_) {
    require(
      rewardReader_ != address(0),
      "GmxIndex: rewardReader_ cannot be address 0"
    );

    require(
      glpPriceFeed_ != address(0),
      "GmxIndex: glpPriceFeed_ cannot be address 0"
    );

    require(weth_ != address(0), "GmxIndex: weth_ cannot be address 0");

    rewardReader = rewardReader_;

    glpPriceFeed = GlpPriceFeed(glpPriceFeed_);

    weth = weth_;
  }

  /// @inheritdoc BaseDelegator
  function delegatorName()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "gmx";
  }

  /// @inheritdoc BaseDelegator
  function delegatorType()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "Index";
  }

  /// @inheritdoc BaseDelegator
  function totalAssets() public view virtual override returns (uint256) {
    address[] memory depositTokens = new address[](1);

    depositTokens[0] = IGlpRewardRouter(underlyingContract()).glp();

    address[] memory rewardTrackers = new address[](1);

    rewardTrackers[0] = IGlpRewardRouter(underlyingContract()).feeGlpTracker();

    uint256[] memory amounts = IGlpRewardReader(rewardReader)
      .getDepositBalances(address(this), depositTokens, rewardTrackers);

    uint256 convertedAmount = glpPriceFeed.convertToUSD(amounts[0]);

    uint8 assetDecimals = IERC20Metadata(asset()).decimals();

    uint256 amountInAsset = convertedAmount / (10 ** (30 - assetDecimals));

    return amountInAsset;
  }

  /// @inheritdoc BaseDelegator
  function rewards() public view virtual override returns (uint256) {
    address[] memory rewardTrackers = new address[](2);

    rewardTrackers[0] = IGlpRewardRouter(underlyingContract())
      .stakedGlpTracker();
    rewardTrackers[1] = IGlpRewardRouter(underlyingContract()).feeGlpTracker();

    uint256[] memory stakingInfo = IGlpRewardReader(rewardReader)
      .getStakingInfo(address(this), rewardTrackers);

    return stakingInfo[0];
  }

  /// @inheritdoc BaseDelegator
  function integrationFeeForDeposits(
    uint256 amount
  ) public view virtual override returns (uint256) {
    return _integrationFee(amount, true);
  }

  /// @inheritdoc BaseDelegator
  function integrationFeeForWithdraws(
    uint256 amount
  ) public view virtual override returns (uint256) {
    return _integrationFee(amount, false);
  }

  /// @dev Get integration fee from protocol integration
  function _integrationFee(
    uint256 amount,
    bool increment
  ) internal view returns (uint256) {
    address vault = IGlpManager(
      IGlpRewardRouter(underlyingContract()).glpManager()
    ).vault();

    uint256 price = IGlpVault(vault).getMinPrice(asset());

    uint256 usdgAmount = amount.mulDiv(
      price,
      IGlpVault(vault).PRICE_PRECISION()
    );

    usdgAmount = IGlpVault(vault).adjustForDecimals(
      usdgAmount,
      asset(),
      IGlpVault(vault).usdg()
    );

    uint256 feeBasisPoints = IGlpVault(vault).getFeeBasisPoints(
      asset(),
      usdgAmount,
      IGlpVault(vault).mintBurnFeeBasisPoints(),
      IGlpVault(vault).taxBasisPoints(),
      increment
    );

    return feeBasisPoints;
  }

  /// @inheritdoc BaseDelegator
  function depositsAvailable(
    uint256
  ) public view virtual override returns (bool) {
    return true;
  }

  /// @inheritdoc BaseDelegator
  function withdrawsAvailable(
    uint256
  ) public view virtual override returns (bool) {
    return true;
  }

  /// @inheritdoc BaseDelegator
  function deposit(
    uint256 amount
  ) external virtual override onlyLinkedVault nonReentrant returns (uint256) {
    require(
      depositsAvailable(amount),
      "GmxIndex: Deposits in the delegator are not available right now"
    );

    uint256 fee = integrationFeeForDeposits(amount);

    claim();

    SafeERC20.safeTransferFrom(
      IERC20(asset()),
      msg.sender,
      address(this),
      amount
    );

    address glpManager = IGlpRewardRouter(underlyingContract()).glpManager();

    // Approve integration to spend balance from delegator
    SafeERC20.safeIncreaseAllowance(IERC20(asset()), glpManager, amount);

    uint256 minGlpAmount = glpPriceFeed.getMinPrice(amount);

    uint256 receivedAmount = IGlpRewardRouter(underlyingContract())
      .mintAndStakeGlp(asset(), amount, 0, minGlpAmount);

    emit Fee(fee);

    emit RequestedDeposit(amount);

    emit Deposited(receivedAmount);

    return receivedAmount;
  }

  /// @inheritdoc BaseDelegator
  function withdraw(
    uint256 amount
  ) public virtual override onlyLinkedVault nonReentrant returns (uint256) {
    require(
      withdrawsAvailable(amount),
      "GmxIndex: Withdraws in the delegator are not available right now"
    );

    uint256 fee = integrationFeeForWithdraws(amount);

    claim();

    uint256 minTokenOut = glpPriceFeed.getMinPrice(amount);

    uint256 receivedAmount = IGlpRewardRouter(underlyingContract())
      .unstakeAndRedeemGlp(asset(), amount, minTokenOut, linkedVault());

    emit Fee(fee);

    emit RequestedWithdraw(amount);

    emit Withdrawn(receivedAmount);

    return receivedAmount;
  }

  /// @inheritdoc BaseDelegator
  function claim() public virtual override {
    if (rewards() < claimableThreshold()) {
      return;
    }

    IGlpRewardRouter(underlyingContract()).compound();

    uint256 claimedRewards = address(this).balance;

    uint256 minGlpAmount = glpPriceFeed.getMinPrice(claimedRewards);

    // slither-disable-start unused-return
    IGlpRewardRouter(underlyingContract()).mintAndStakeGlpETH{
      value: claimedRewards
    }(0, minGlpAmount);
    // slither-disable-end unused-return
  }
}

