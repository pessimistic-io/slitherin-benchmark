// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./ISwapRouter.sol";
import "./IUniswapV3Pool.sol";
import "./TransferHelper.sol";

import "./AdapterBase.sol";
import "./IAdapter.sol";
import "./IUniV3Adapter.sol";
import "./IVault.sol";
import "./TickMath.sol";
import "./INonfungiblePositionManager.sol";
import "./FullMath.sol";
import "./LiquidityAmounts.sol";
import "./PoolAddress.sol";
import "./PositionValue.sol";

/// @title Saffron Fixed Income Uniswap V3 Limited Range Adapter
/// @author psykeeper, supafreq, everywherebagel, maze, rx
/// @notice Adapter that connects a Uniswap V3 pool to a UniV3Vault
contract UniV3LimitedRangeAdapter is AdapterBase, IUniV3Adapter {
  using TickMath for int24;

  /// @notice Uniswap V3 position manager
  INonfungiblePositionManager public constant positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

  /// @notice Adapter ID set by the factory
  uint256 public id;

  /// @notice Address of Uniswap V3 pool
  IUniswapV3Pool public pool;

  /// @notice Liquidity position range lower bound tick
  int24 public poolMinTick;

  /// @notice Liquidity position range upper bound tick
  int24 public poolMaxTick;

  /// @notice Contains token0, token1, fee
  PoolAddress.PoolKey public poolKey;

  /// @notice Token ID of Uniswap V3 position NFT
  uint256 public tokenId;

  /// @notice Liquidity of position ("L" value)
  uint128 public liquidity;

  /// @notice Settled token0 earnings
  /// @dev Only set after settleEarnings() is called on the vault
  uint256 public earnings0;

  /// @notice Settled token1 earnings
  /// @dev Only set after settleEarnings() is called on the vault
  uint256 public earnings1;

  /// @dev Inverse tolerance for fixed side deposits in basis points; see depositTolerance()
  uint256 private invDepositTolerance;

  uint256 constant FIXED = 0;
  uint256 constant VARIABLE = 1;

  struct UniV3InitData {
    int24 minTick;
    int24 maxTick;
  }

  /// @notice Emitted when capital is deployed to Uniswap V3
  /// @param vault Address of the vault
  /// @param pool Address of the Uniswap V3 pool
  /// @param tokenId Token ID of the liquidity position
  /// @param mintedAmount0 Amount of token0 used to mint the liquidity position
  /// @param mintedAmount1 Amount of token1 used to mint the liquidity position
  event CapitalDeployed(address vault, address pool, uint256 tokenId, uint256 mintedAmount0, uint256 mintedAmount1);

  /// @notice Emitted when earnings are settled
  /// @param vault Address of the vault
  /// @param pool Address of the Uniswap V3 pool
  /// @param tokenId Token ID of the liquidity position
  /// @param earnings0 Amount of token0 earned from the liquidity position
  /// @param earnings1 Amount of token1 earned from the liquidity position
  event EarningsSettled(address vault, address pool, uint256 tokenId, uint256 earnings0, uint256 earnings1);

  /// @notice Emitted when liquidity is removed from the Uniswap V3 pool
  /// @param vault Address of the vault
  /// @param pool Address of the Uniswap V3 pool
  /// @param tokenId Token ID of the burned liquidity position
  /// @param liquidity The amount of liquidity ("L" value) removed from the burned liquidity position
  /// @param amount0 Amount of token0 received from the burned liquidity position
  /// @param amount1 Amount of token1 received from the burned liquidity position
  event LiquidityRemoved(address vault, address pool, uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);

  /// @inheritdoc IAdapter
  function initialize(
    uint256 _id,
    address _pool,
    uint256 _depositTolerance,
    bytes memory uniV3InitData
  ) public virtual override onlyWithoutVaultAttached onlyFactory {
    require(uniV3InitData.length > 0, "NEI");
    require(_pool != address(0), "NEI");

    // Store adapter configuration
    invDepositTolerance = 10000 - _depositTolerance;
    id = _id;
    IUniswapV3Pool uniswapV3Pool = IUniswapV3Pool(_pool);
    pool = uniswapV3Pool;
    poolKey = PoolAddress.getPoolKey(uniswapV3Pool.token0(), uniswapV3Pool.token1(), uniswapV3Pool.fee());

    // Calculate and store min and max tick for Uniswap V3 position
    UniV3InitData memory params = abi.decode(uniV3InitData, (UniV3InitData));
    int24 ts = uniswapV3Pool.tickSpacing();
    require(params.minTick % ts == 0 && params.maxTick % ts == 0, "BTS");
    require(params.minTick < params.maxTick, "IT");
    poolMinTick = params.minTick;
    poolMaxTick = params.maxTick;
  }

  struct DeployCapitalData {
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  /// @inheritdoc IUniV3Adapter
  function deployCapital(
    address user,
    bytes calldata deployCapitalData
  ) external override onlyVault returns (uint256, uint256) {
    require(deployCapitalData.length > 0, "NEI");
    require(tokenId == 0, "PAE");
    DeployCapitalData memory decoded = abi.decode(deployCapitalData, (DeployCapitalData));
    PoolAddress.PoolKey memory pk = poolKey;

    uint256 cap = IUniV3Vault(vaultAddress).fixedSideCapacity();
    require(cap < type(uint128).max, "CTL");
    uint128 fixedSideCapacity = uint128(cap);

    // Transfer tokens from vault to adapter
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtRatioX96,
      poolMinTick.getSqrtRatioAtTick(),
      poolMaxTick.getSqrtRatioAtTick(),
      fixedSideCapacity
    );

    TransferHelper.safeTransferFrom(pk.token0, user, address(this), amount0);
    TransferHelper.safeTransferFrom(pk.token1, user, address(this), amount1);

    TransferHelper.safeApprove(pk.token0, address(positionManager), amount0);
    TransferHelper.safeApprove(pk.token1, address(positionManager), amount1);

    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
      token0: pk.token0,
      token1: pk.token1,
      fee: pk.fee,
      tickLower: poolMinTick,
      tickUpper: poolMaxTick,
      amount0Desired: amount0,
      amount1Desired: amount1,
      amount0Min: decoded.amount0Min,
      amount1Min: decoded.amount1Min,
      recipient: address(this),
      deadline: decoded.deadline
    });
    (uint256 mintedAmount0, uint256 mintedAmount1) = _mintToken(user, pk, params, fixedSideCapacity);

    emit CapitalDeployed(vaultAddress, address(pool), tokenId, mintedAmount0, mintedAmount1);

    return (mintedAmount0, mintedAmount1);
  }

  function _mintToken(
    address user,
    PoolAddress.PoolKey memory pk,
    INonfungiblePositionManager.MintParams memory params,
    uint128 l
  ) internal returns (uint256, uint256) {
    (uint256 _tokenId, uint128 _liquidity, uint256 deposited0, uint256 deposited1) = positionManager.mint(params);
    require(uint256(l) * invDepositTolerance / 10000 < _liquidity, "L");
    tokenId = _tokenId;
    liquidity = _liquidity;

    // Transfer change back to fixed side depositor
    if (deposited0 < params.amount0Desired) {
      TransferHelper.safeApprove(pk.token0, address(positionManager), 0); // Remove unused approval amount
      TransferHelper.safeTransfer(pk.token0, user, params.amount0Desired - deposited0);
    }
    if (deposited1 < params.amount1Desired) {
      TransferHelper.safeApprove(pk.token1, address(positionManager), 0); // Remove unused approval amount
      TransferHelper.safeTransfer(pk.token1, user, params.amount1Desired - deposited1);
    }

    return (deposited0, deposited1);
  }

  /// @inheritdoc IUniV3Adapter
  function returnCapital(
    address to,
    uint256 amount0,
    uint256 amount1,
    uint256 side
  ) external override onlyVault {
    require(side == FIXED || side == VARIABLE, "IS");
    require(IVault(vaultAddress).earningsSettled(), "ENS");

    PoolAddress.PoolKey memory pk = poolKey;

    TransferHelper.safeTransfer(pk.token0, to, amount0);
    TransferHelper.safeTransfer(pk.token1, to, amount1);
  }

  /// @inheritdoc IUniV3Adapter
  function earlyReturnCapital(
    address to,
    uint256 side,
    bytes calldata removeLiquidityData
  ) external override onlyVault returns (uint256, uint256) {
    require(removeLiquidityData.length > 0, "NEI");
    PoolAddress.PoolKey memory pk = poolKey;
    (uint256 amount0, uint256 amount1) = _removeLiquidity(removeLiquidityData);
    // transfer fees
    TransferHelper.safeTransfer(pk.token0, to, amount0);
    TransferHelper.safeTransfer(pk.token1, to, amount1);

    return (amount0, amount1);
  }

  /// @inheritdoc AdapterBase
  function setVault(address _vaultAddress) public override(AdapterBase, IAdapter) onlyWithoutVaultAttached onlyFactory {
    require(IVault(_vaultAddress).fixedSideCapacity() < type(uint128).max, "CTL");
    super.setVault(_vaultAddress);
  }

  struct RemoveLiquidityData {
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  /// @inheritdoc IUniV3Adapter
  function settleEarnings() external override onlyVault returns (uint256, uint256) {
    require(!IVault(vaultAddress).earningsSettled(), "EAS");
    (earnings0, earnings1) = collect(tokenId);
    emit EarningsSettled(vaultAddress, address(pool), tokenId, earnings0, earnings1);
    return (earnings0, earnings1);
  }

  /// @inheritdoc IUniV3Adapter
  function removeLiquidity(address to, bytes calldata removeLiquidityData) external override onlyVault returns (uint256, uint256) {
    require(IVault(vaultAddress).earningsSettled(), "ENS");
    require(removeLiquidityData.length > 0, "NEI");
    (uint256 amount0, uint256 amount1) = _removeLiquidity(removeLiquidityData);
    return (amount0, amount1);
  }

  function _removeLiquidity(bytes calldata removeLiquidityData) internal returns (uint256 amount0, uint256 amount1) {
    RemoveLiquidityData memory decoded = abi.decode(removeLiquidityData, (RemoveLiquidityData));

    uint256 _tokenId = tokenId;

    INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
      .DecreaseLiquidityParams({
        tokenId: _tokenId,
        liquidity: liquidity,
        amount0Min: decoded.amount0Min,
        amount1Min: decoded.amount1Min,
        deadline: decoded.deadline
      });

    positionManager.decreaseLiquidity(decreaseLiquidityParams);
    (uint256 amount0, uint256 amount1) = collect(_tokenId);
    positionManager.burn(_tokenId);
    emit LiquidityRemoved(vaultAddress, address(pool), tokenId, liquidity, amount0, amount1);
    tokenId = 0;
    return (amount0, amount1);
  }

  function collect(uint256 _tokenId) internal returns (uint256 _earnings0, uint256 _earnings1) {
    INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
      tokenId: _tokenId,
      recipient: address(this),
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });

    (_earnings0, _earnings1) = positionManager.collect(params);
  }

  /// @notice Allow for receiving ERC721 tokens
  function onERC721Received(
    address, // _operator
    address, // _from
    uint256, // _tokenId
    bytes calldata // _data
  ) external returns (bytes4) {
    if (msg.sender == address(positionManager)) {
      return this.onERC721Received.selector;
    }
    // Not Position Manager
    revert("NPM");
  }

  /// @inheritdoc IUniV3Adapter
  function getEarnings() external view override returns (uint256, uint256) {
    return (earnings0, earnings1);
  }

  /// @inheritdoc IUniV3Adapter
  function holdings() external view override returns (uint256, uint256) {
    require(IVault(vaultAddress).earningsSettled(), "ENS");
    PoolAddress.PoolKey memory pk = poolKey;

    uint256 bal0 = IERC20(pk.token0).balanceOf(address(this));
    uint256 bal1 = IERC20(pk.token1).balanceOf(address(this));

    return (bal0, bal1);
  }

  /// @inheritdoc IUniV3Adapter
  function estimatedHoldings() external view override returns (uint256 estimate0, uint256 estimate1) {
    if (IVault(vaultAddress).earningsSettled()) {
      return this.holdings();
    }
    PoolAddress.PoolKey memory pk = poolKey;
    estimate0 = IERC20(pk.token0).balanceOf(address(this));
    estimate1 = IERC20(pk.token1).balanceOf(address(this));
  }

  /// @inheritdoc IUniV3Adapter
  function assetAddresses() external view override returns (address token0, address token1) {
    PoolAddress.PoolKey memory pk = poolKey;
    return (pk.token0, pk.token1);
  }

  /// @inheritdoc AdapterBase
  function hasAccurateHoldings() public view override(AdapterBase, IAdapter) returns (bool) {
    return IVault(vaultAddress).earningsSettled();
  }

  /// @notice Tolerance value for fixed side deposits in basis points
  /// @dev Fixed side depositor's resulting liquidity value may be lower than the required amount according to this tolerance
  function depositTolerance() public view returns (uint256) {
    return 10000 - invDepositTolerance;
  }
}

