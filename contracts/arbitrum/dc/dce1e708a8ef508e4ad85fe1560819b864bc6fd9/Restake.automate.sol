// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.6;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Automate.sol";
import "./IStorage.sol";
import "./INonfungiblePositionManager.sol";
import "./ISwapRouter.sol";
import "./IFactory.sol";
import "./StopLoss.sol";
import "./Rebalance.sol";

contract Restake is Automate {
  using SafeERC20 for IERC20;
  using StopLoss for StopLoss.Order;
  using Rebalance for Rebalance.Interval;

  address public positionManager;

  address public liquidityRouter;

  address public pool;

  uint256 public tokenId;

  uint16 public deadline;

  StopLoss.Order public stopLoss;

  event Deposit(uint256 tokenId);

  event Refund(uint256 tokenId);

  // solhint-disable-next-line no-empty-blocks
  constructor(address _info) Automate(_info) {}

  modifier tokenDeposited() {
    require(tokenId != 0, "Restake::tokenDeposited: token not deposited");
    require(
      INonfungiblePositionManager(positionManager).ownerOf(tokenId) == address(this),
      "Restake::tokenDeposited: token refunded"
    );
    _;
  }

  function init(
    address _positionManager,
    address _liquidityRouter,
    address _pool,
    uint16 _deadline
  ) external initializer {
    require(
      !_initialized || positionManager == _positionManager,
      "Restake::init: reinitialize position manager address forbidden"
    );
    positionManager = _positionManager;
    require(
      !_initialized || liquidityRouter == _liquidityRouter,
      "Restake::init: reinitialize liquidity router address forbidden"
    );
    liquidityRouter = _liquidityRouter;
    require(!_initialized || pool == _pool, "Restake::init: reinitialize pool address forbidden");
    pool = _pool;
    deadline = _deadline;
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
    return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
  }

  function deposit(uint256 _tokenId) external onlyOwner {
    require(tokenId == 0, "Restake::deposit: token already deposited");
    tokenId = _tokenId;
    INonfungiblePositionManager pm = INonfungiblePositionManager(positionManager);
    (, , address token0, address token1, uint24 fee, , , , , , , ) = pm.positions(tokenId);
    require(token0 != address(0), "Restake::deposit: invalid token0 address");
    require(token1 != address(0), "Restake::deposit: invalid token1 address");
    address tokenPool = IFactory(pm.factory()).getPool(token0, token1, fee);
    require(tokenPool == pool, "Restake::deposit: invalid pool address");
    pm.safeTransferFrom(msg.sender, address(this), tokenId);
    pm.approve(msg.sender, tokenId);

    emit Deposit(_tokenId);
  }

  function refund() external onlyOwner {
    uint256 _tokenId = tokenId;
    require(_tokenId > 0, "Restake::refund: token already refunded");
    address _owner = owner();

    INonfungiblePositionManager pm = INonfungiblePositionManager(positionManager);
    pm.safeTransferFrom(address(this), _owner, _tokenId);

    (, , address token0, address token1, , , , , , , , ) = pm.positions(_tokenId);
    require(token0 != address(0), "Restake::refund: invalid token0 address");
    require(token1 != address(0), "Restake::refund: invalid token1 address");
    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));
    if (balance0 > 0) {
      IERC20(token0).safeTransfer(_owner, balance0);
    }
    if (balance1 > 0) {
      IERC20(token1).safeTransfer(_owner, balance1);
    }
    tokenId = 0;

    emit Refund(_tokenId);
  }

  function run(uint256 gasFee, uint256 _deadline) external tokenDeposited bill(gasFee, "UniswapV3Restake") {
    uint256 _tokenId = tokenId;
    INonfungiblePositionManager pm = INonfungiblePositionManager(positionManager);
    (, , address token0, address token1, , , , , , , , ) = pm.positions(_tokenId);

    pm.collect(
      INonfungiblePositionManager.CollectParams({
        tokenId: _tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    uint256 amount0 = IERC20(token0).balanceOf(address(this));
    uint256 amount1 = IERC20(token1).balanceOf(address(this));
    require(amount0 > 0 || amount1 > 0, "Restake::run: no earned");
    IERC20(token0).safeApprove(address(pm), amount0);
    IERC20(token1).safeApprove(address(pm), amount1);
    pm.increaseLiquidity(
      INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: _tokenId,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: _deadline
      })
    );
    IERC20(token0).safeApprove(address(pm), 0);
    IERC20(token1).safeApprove(address(pm), 0);
  }

  function setStopLoss(address[] memory path, uint24 fee, uint256 amountOut, uint256 amountOutMin) external onlyOwner {
    stopLoss = StopLoss.Order({path: path, fee: fee, amountOut: amountOut, amountOutMin: amountOutMin});
  }

  function _runStopLoss(uint256 _deadline) internal returns (uint256 amountOut) {
    uint256 _tokenId = tokenId;
    INonfungiblePositionManager pm = INonfungiblePositionManager(positionManager);
    (, , address token0, address token1, , , , uint128 liquidity, , , , ) = pm.positions(_tokenId);
    require(liquidity > 0, "Restake::_runStopLoss: token already closed");

    pm.decreaseLiquidity(
      INonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: _tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: _deadline
      })
    );
    pm.collect(
      INonfungiblePositionManager.CollectParams({
        tokenId: _tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );

    address[] memory inTokens = new address[](2);
    inTokens[0] = token0;
    inTokens[1] = token1;
    amountOut = stopLoss.run(liquidityRouter, inTokens);
    IERC20 exitToken = IERC20(stopLoss.path[stopLoss.path.length - 1]);
    address _owner = owner();
    exitToken.safeTransfer(_owner, exitToken.balanceOf(address(this)));
    pm.safeTransferFrom(address(this), _owner, _tokenId);
  }

  function runStopLoss(
    uint256 gasFee,
    uint256 _deadline
  ) external tokenDeposited bill(gasFee, "UniswapV3RestakeStopLoss") {
    require(_runStopLoss(_deadline) <= stopLoss.amountOut, "Restake::runStopLoss: invalid output amount");
  }

  function emergencyWithdraw(uint256 _deadline) external onlyOwner tokenDeposited {
    _runStopLoss(_deadline);
  }

  function rebalance(
    uint256 gasFee,
    int24 tickLower,
    int24 tickUpper,
    uint256 _deadline
  ) external bill(gasFee, "UniswapV3RestakeRebalance") {
    uint256 _tokenId = tokenId;
    require(_tokenId != 0, "Restake::rebalance: token already refunded");
    Rebalance.Interval memory interval = Rebalance.Interval({
      tickLower: tickLower,
      tickUpper: tickUpper,
      positionManager: positionManager,
      liquidityRouter: liquidityRouter,
      tokenId: _tokenId
    });
    uint256 newTokenId = interval.run(_deadline);
    INonfungiblePositionManager(positionManager).safeTransferFrom(address(this), owner(), _tokenId);
    tokenId = newTokenId;
  }
}

