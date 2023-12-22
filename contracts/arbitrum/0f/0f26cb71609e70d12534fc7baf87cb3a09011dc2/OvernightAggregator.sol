// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./BaseDelegator.sol";

import "./IErrors.sol";
import "./IVaultDelegatorErrors.sol";
import "./IOvernightExchange.sol";

/// @title Overnight Aggregator Delegator
/// @author Christopher Enytc <wagmi@munchies.money>
/// @dev All functions are derived from the base delegator
/// @custom:security-contact security@munchies.money
contract OvernightAggregator is BaseDelegator {
  using Math for uint256;

  /* solhint-disable no-empty-blocks */

  /**
   * @dev Set the underlying asset contract. This must be an ERC20 contract.
   */
  constructor(
    IERC20 asset_,
    address exchangeContract_
  ) BaseDelegator(asset_, exchangeContract_) {}

  /// @inheritdoc BaseDelegator
  function delegatorName()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "overnight";
  }

  /// @inheritdoc BaseDelegator
  function delegatorType()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "Aggregator";
  }

  /// @inheritdoc BaseDelegator
  function estimatedTotalAssets()
    public
    view
    virtual
    override
    returns (uint256)
  {
    return
      IERC20(IOvernightExchange(underlyingContract()).usdPlus()).balanceOf(
        address(this)
      );
  }

  /// @inheritdoc BaseDelegator
  function rewards() public view virtual override returns (uint256) {
    return 0;
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
    bool isBuy
  ) internal view returns (uint256) {
    uint256 fee = isBuy
      ? IOvernightExchange(underlyingContract()).buyFee()
      : IOvernightExchange(underlyingContract()).redeemFee();

    uint256 feeDenominator = isBuy
      ? IOvernightExchange(underlyingContract()).buyFeeDenominator()
      : IOvernightExchange(underlyingContract()).redeemFeeDenominator();

    uint256 multiplier = 10_000;

    return multiplier.mulDiv((amount * fee) / feeDenominator, amount);
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

    MintParams memory params = MintParams({
      asset: asset(),
      amount: amount,
      referral: ""
    });

    uint256 receivedAmount = IOvernightExchange(underlyingContract()).mint(
      params
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
    uint256 fee = integrationFeeForWithdraws(amount);

    uint256 receivedAmount = IOvernightExchange(underlyingContract()).redeem(
      asset(),
      amount
    );

    SafeERC20.safeTransfer(IERC20(asset()), linkedVault(), receivedAmount);

    emit Fee(fee);

    emit RequestedWithdraw(amount);

    emit Withdrawn(receivedAmount);

    emit RequestedByAddress(user);

    return receivedAmount;
  }
}

