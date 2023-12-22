// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./BaseDelegator.sol";

import "./IWeth.sol";

import "./ICurvePool.sol";
import "./ICurveRegistry.sol";
import "./ICurveAddressProvider.sol";

contract LidoStaking is BaseDelegator {
  /* solhint-disable no-empty-blocks */

  address public immutable eth;
  address public immutable wstEth;

  constructor(
    address asset,
    address addressProviderContract,
    address eth_,
    address wsteth_
  ) BaseDelegator(asset, addressProviderContract) {
    eth = eth_;
    wstEth = wsteth_;
  }

  function delegatorName()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "lido";
  }

  function delegatorType()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "Staking";
  }

  function deposit(uint256 amount) external virtual override onlyLinkedVault {
    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address exchange = ICurveAddressProvider(underlyingContract()).get_address(
      2
    );

    address pool = ICurveRegistry(registry).find_pool_for_coins(eth, wstEth, 0);

    (int128 ethIndex, int128 wstEthIndex, ) = ICurveRegistry(registry)
      .get_coin_indices(pool, eth, wstEth);

    uint256 minDy = ICurvePool(pool).get_dy(ethIndex, wstEthIndex, amount);

    IWeth(asset()).withdraw(amount);

    uint256 receivedAmount = ICurvePool(exchange).exchange{value: amount}(
      ethIndex,
      wstEthIndex,
      amount,
      minDy
    );

    emit Deposit(receivedAmount);
  }

  function withdraw(uint256 amount) external virtual override onlyLinkedVault {
    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address exchange = ICurveAddressProvider(underlyingContract()).get_address(
      2
    );

    address pool = ICurveRegistry(registry).find_pool_for_coins(wstEth, eth, 0);

    (int128 wstEthIndex, int128 ethIndex, ) = ICurveRegistry(registry)
      .get_coin_indices(pool, eth, wstEth);

    uint256 minDy = ICurvePool(pool).get_dy(wstEthIndex, ethIndex, amount);

    SafeERC20.safeIncreaseAllowance(IERC20(wstEth), exchange, amount);

    uint256 receivedAmount = ICurvePool(exchange).exchange(
      wstEthIndex,
      ethIndex,
      amount,
      minDy
    );

    IWeth(asset()).deposit{value: receivedAmount}();

    SafeERC20.safeTransfer(IERC20(asset()), linkedVault(), receivedAmount);

    emit Withdraw(receivedAmount);
  }

  function totalAssets() public view virtual override returns (uint256) {
    return IERC20(wstEth).balanceOf(address(this));
  }
}

