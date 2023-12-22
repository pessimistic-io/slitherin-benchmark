// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./PercentageMath.sol";

import "./BaseDelegator.sol";

import "./IErrors.sol";
import "./IPriceOracle.sol";
import "./IVaultDelegatorErrors.sol";

import "./IBalancerPool.sol";
import "./IBalancerVault.sol";

/// @title Lido Staking Delegator
/// @author Christopher Enytc <wagmi@munchies.money>
/// @dev All functions are derived from the base delegator
/// @custom:security-contact security@munchies.money
contract LidoStaking is BaseDelegator {
  using Math for uint256;
  using PercentageMath for uint256;

  bytes32 public immutable poolId;

  address public immutable wsteth;

  IPriceOracle public immutable priceFeed;

  /**
   * @dev Set the underlying asset contract. This must be an ERC20 contract.
   */
  constructor(
    IERC20 asset_,
    address vaultContract_,
    bytes32 poolId_,
    address wsteth_,
    address priceFeed_
  ) BaseDelegator(asset_, vaultContract_) {
    if (wsteth_ == address(0)) {
      revert ZeroAddressCannotBeUsed();
    }

    if (priceFeed_ == address(0)) {
      revert ZeroAddressCannotBeUsed();
    }

    poolId = poolId_;

    wsteth = wsteth_;

    priceFeed = IPriceOracle(priceFeed_);
  }

  /// @inheritdoc BaseDelegator
  function delegatorName()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "lido";
  }

  /// @inheritdoc BaseDelegator
  function delegatorType()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "Staking";
  }

  /// @inheritdoc BaseDelegator
  function estimatedTotalAssets()
    public
    view
    virtual
    override
    returns (uint256)
  {
    uint256 totalAssets = IERC20(wsteth).balanceOf(address(this));

    return priceFeed.convert(totalAssets, wsteth, asset());
  }

  /// @inheritdoc BaseDelegator
  function rewards() public view virtual override returns (uint256) {
    return 0;
  }

  /// @inheritdoc BaseDelegator
  function integrationFeeForDeposits(
    uint256 amount
  ) public view virtual override returns (uint256) {
    return _integrationFee(amount);
  }

  /// @inheritdoc BaseDelegator
  function integrationFeeForWithdraws(
    uint256 amount
  ) public view virtual override returns (uint256) {
    return _integrationFee(amount);
  }

  /// @dev Get integration fee from protocol integration
  function _integrationFee(uint256) internal view returns (uint256) {
    return 4;
  }

  /// @inheritdoc BaseDelegator
  function deposit(
    uint256 amount,
    address user
  ) external virtual override onlyLinkedVault nonReentrant returns (uint256) {
    uint256 fee = integrationFeeForDeposits(amount);

    SafeERC20.safeTransferFrom(
      IERC20(asset()),
      msg.sender,
      address(this),
      amount
    );

    // Approve integration to spend balance from delegator
    SafeERC20.safeIncreaseAllowance(
      IERC20(asset()),
      underlyingContract(),
      amount
    );

    IBalancerVault.SingleSwap memory swapParams = IBalancerVault.SingleSwap({
      poolId: poolId,
      kind: IBalancerVault.SwapKind.GIVEN_IN,
      assetIn: IAsset(asset()),
      assetOut: IAsset(wsteth),
      amount: amount,
      userData: ""
    });

    IBalancerVault.FundManagement memory fundParams = IBalancerVault
      .FundManagement({
        sender: address(this),
        fromInternalBalance: false,
        recipient: payable(address(this)),
        toInternalBalance: false
      });

    uint256 estimatedPrice = priceFeed.convert(amount, asset(), wsteth);

    uint256 slippage = estimatedPrice.percentMul(slippageConfiguration());

    uint256 limit = estimatedPrice - slippage;

    // solhint-disable-next-line not-rely-on-time
    uint256 deadline = block.timestamp + 5 minutes;

    uint256 receivedAmount = IBalancerVault(underlyingContract()).swap(
      swapParams,
      fundParams,
      limit,
      deadline
    );

    emit Fee(fee);

    emit RequestedDeposit(amount);

    emit Deposited(receivedAmount);

    emit RequestedByAddress(user);

    return receivedAmount;
  }

  /// @inheritdoc BaseDelegator
  function withdraw(
    uint256 amount,
    address user
  ) public virtual override onlyLinkedVault nonReentrant returns (uint256) {
    uint256 convertedAmount = priceFeed.convert(amount, asset(), wsteth);

    uint256 fee = integrationFeeForWithdraws(convertedAmount);

    // Approve integration to spend balance from delegator
    SafeERC20.safeIncreaseAllowance(
      IERC20(wsteth),
      underlyingContract(),
      convertedAmount
    );

    IBalancerVault.SingleSwap memory swapParams = IBalancerVault.SingleSwap({
      poolId: poolId,
      kind: IBalancerVault.SwapKind.GIVEN_IN,
      assetIn: IAsset(wsteth),
      assetOut: IAsset(asset()),
      amount: convertedAmount,
      userData: ""
    });

    IBalancerVault.FundManagement memory fundParams = IBalancerVault
      .FundManagement({
        sender: address(this),
        fromInternalBalance: false,
        recipient: payable(address(this)),
        toInternalBalance: false
      });

    uint256 estimatedPrice = priceFeed.convert(
      convertedAmount,
      wsteth,
      asset()
    );

    uint256 slippage = estimatedPrice.percentMul(slippageConfiguration());

    uint256 limit = estimatedPrice - slippage;

    // solhint-disable-next-line not-rely-on-time
    uint256 deadline = block.timestamp + 5 minutes;

    uint256 receivedAmount = IBalancerVault(underlyingContract()).swap(
      swapParams,
      fundParams,
      limit,
      deadline
    );

    SafeERC20.safeTransfer(IERC20(asset()), msg.sender, receivedAmount);

    emit Fee(fee);

    emit RequestedWithdraw(amount);

    emit Withdrawn(receivedAmount);

    emit RequestedByAddress(user);

    return receivedAmount;
  }
}

