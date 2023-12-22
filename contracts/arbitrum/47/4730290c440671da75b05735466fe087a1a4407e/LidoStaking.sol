// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./BaseDelegator.sol";

import "./ICurvePool.sol";
import "./ICurveRegistry.sol";
import "./ICurveAddressProvider.sol";

contract LidoStaking is BaseDelegator {
  /* solhint-disable no-empty-blocks */

  address public immutable weth;
  address public immutable wstEth;

  constructor(
    address asset,
    address addressProviderContract,
    address wsteth_
  ) BaseDelegator(asset, addressProviderContract) {
    weth = asset;
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
    SafeERC20.safeTransferFrom(
      IERC20(asset()),
      linkedVault(),
      address(this),
      amount
    );

    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address pool = ICurveRegistry(registry).find_pool_for_coins(
      weth,
      wstEth,
      0
    );

    (int128 wethIndex, int128 wstEthIndex, ) = ICurveRegistry(registry)
      .get_coin_indices(pool, weth, wstEth);

    uint256 minDy = ICurvePool(underlyingContract()).get_dy(
      wethIndex,
      wstEthIndex,
      amount
    );

    ICurvePool(underlyingContract()).exchange(
      wethIndex,
      wstEthIndex,
      amount,
      minDy
    );

    emit Deposit(amount);
  }

  function withdraw(uint256 amount) external virtual override onlyLinkedVault {
    // Address provider
    address registry = ICurveAddressProvider(underlyingContract())
      .get_registry();

    address pool = ICurveRegistry(registry).find_pool_for_coins(
      wstEth,
      weth,
      0
    );

    (int128 wstEthIndex, int128 wethIndex, ) = ICurveRegistry(registry)
      .get_coin_indices(pool, weth, wstEth);

    uint256 minDy = ICurvePool(underlyingContract()).get_dy(
      wstEthIndex,
      wethIndex,
      amount
    );

    ICurvePool(underlyingContract()).exchange(
      wstEthIndex,
      wethIndex,
      amount,
      minDy
    );

    SafeERC20.safeTransfer(IERC20(asset()), linkedVault(), amount);

    emit Withdraw(amount);
  }

  function totalAssets() public view virtual override returns (uint256) {
    return IERC20(wstEth).balanceOf(address(this));
  }
}

