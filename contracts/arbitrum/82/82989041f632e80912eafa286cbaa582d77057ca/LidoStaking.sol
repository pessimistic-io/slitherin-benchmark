// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./BaseDelegator.sol";

import "./WadRayMath.sol";

import "./IWeth.sol";

import "./ICurvePool.sol";
import "./ICurveRegistry.sol";
import "./ICurveAddressProvider.sol";

/// @title Lido Staking Delegator
/// @author Christopher Enytc <wagmi@munchies.money>
/// @dev All functions are derived from the base delegator
/// @custom:security-contact security@munchies.money
contract LidoStaking is BaseDelegator {
  using Math for uint256;
  using WadRayMath for uint256;

  address public immutable eth;
  address public immutable wsteth;

  /**
   * @dev Set the underlying asset contract. This must be an ERC20 contract.
   */
  constructor(
    IERC20 asset_,
    address addressProviderContract_,
    address eth_,
    address wsteth_
  ) BaseDelegator(asset_, addressProviderContract_) {
    require(eth_ != address(0), "LidoStaking: eth_ cannot be address 0");

    require(wsteth_ != address(0), "LidoStaking: wsteth_ cannot be address 0");

    eth = eth_;
    wsteth = wsteth_;
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
  function totalAssets() public view virtual override returns (uint256) {
    return IERC20(wsteth).balanceOf(address(this));
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
  function _integrationFee(uint256 amount) internal view returns (uint256) {
    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address pool = ICurveRegistry(registry).find_pool_for_coins(eth, wsteth, 0);

    uint256 fee = ICurvePool(pool).fee();

    uint256 feeInAsset = (amount * fee) / 10 ** 10;

    uint256 multiplier = 10_000;

    return multiplier.mulDiv(feeInAsset, amount);
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
  ) external virtual override onlyLinkedVault nonReentrant {
    require(
      depositsAvailable(amount),
      "LidoStaking: Deposits in the delegator are not available right now"
    );

    uint256 fee = integrationFeeForDeposits(amount);

    SafeERC20.safeTransferFrom(
      IERC20(asset()),
      msg.sender,
      address(this),
      amount
    );

    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address pool = ICurveRegistry(registry).find_pool_for_coins(eth, wsteth, 0);

    // slither-disable-start unused-return
    (int128 ethIndex, int128 wstEthIndex, ) = ICurveRegistry(registry)
      .get_coin_indices(pool, eth, wsteth);
    // slither-disable-end unused-return

    uint256 minDy = ICurvePool(pool).get_dy(ethIndex, wstEthIndex, amount);

    IWeth(asset()).withdraw(amount);

    uint256 receivedAmount = ICurvePool(pool).exchange{value: amount}(
      ethIndex,
      wstEthIndex,
      amount,
      minDy.wadMul(9.9e17)
    );

    emit Fee(fee);

    emit RequestedDeposit(amount);

    emit Deposited(receivedAmount);
  }

  /// @inheritdoc BaseDelegator
  function withdraw(
    uint256 amount
  ) public virtual override onlyLinkedVault nonReentrant {
    require(
      depositsAvailable(amount),
      "LidoStaking: Withdraws from delegator are not available right now"
    );

    uint256 fee = integrationFeeForWithdraws(amount);

    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address pool = ICurveRegistry(registry).find_pool_for_coins(eth, wsteth, 0);

    // slither-disable-start unused-return
    (int128 ethIndex, int128 wstEthIndex, ) = ICurveRegistry(registry)
      .get_coin_indices(pool, eth, wsteth);
    // slither-disable-end unused-return

    uint256 minDy = ICurvePool(pool).get_dy(wstEthIndex, ethIndex, amount);

    SafeERC20.safeIncreaseAllowance(IERC20(wsteth), pool, amount);

    uint256 receivedAmount = ICurvePool(pool).exchange(
      wstEthIndex,
      ethIndex,
      amount,
      minDy.wadMul(9.9e17)
    );

    IWeth(asset()).deposit{value: receivedAmount}();

    SafeERC20.safeTransfer(IERC20(asset()), linkedVault(), receivedAmount);

    emit Fee(fee);

    emit RequestedWithdraw(amount);

    emit Withdrawn(receivedAmount);
  }

  /* solhint-disable no-empty-blocks */
  receive() external payable {}

  /* solhint-disable no-empty-blocks */
  fallback() external payable {}
}

