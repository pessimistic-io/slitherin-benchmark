// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./ReentrancyGuard.sol";
import "./Decimals.sol";
import "./TransferHelper.sol";
import "./NFTHelper.sol";

contract HedgeyDAOSwap is ReentrancyGuard {
  uint256 public swapId;

  struct Swap {
    address tokenA;
    address tokenB;
    uint256 amountA;
    uint256 amountB;
    uint256 unlockDate;
    address initiator;
    address executor;
    address nftLocker;
  }

  mapping(uint256 => Swap) public swaps;

  event NewSwap(
    uint256 indexed id,
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB,
    uint256 unlockDate,
    address indexed initiator,
    address indexed executor,
    address nftLocker
  );
  event SwapExecuted(uint256 indexed id);
  event SwapCancelled(uint256 indexed id);

  constructor() {}

  function initSwap(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB,
    uint256 unlockDate,
    address executor,
    address nftLocker
  ) external nonReentrant {
    TransferHelper.transferTokens(tokenA, msg.sender, address(this), amountA);
    emit NewSwap(swapId, tokenA, tokenB, amountA, amountB, unlockDate, msg.sender, executor, nftLocker);
    swaps[swapId++] = Swap(tokenA, tokenB, amountA, amountB, unlockDate, msg.sender, executor, nftLocker);
  }

  function executeSwap(uint256 _swapId) external nonReentrant {
    Swap memory swap = swaps[_swapId];
    require(msg.sender == swap.executor);
    delete swaps[_swapId];
    if (swap.unlockDate > block.timestamp) {
      TransferHelper.transferTokens(swap.tokenB, swap.executor, address(this), swap.amountB);
      NFTHelper.lockTokens(swap.nftLocker, swap.initiator, swap.tokenB, swap.amountB, swap.unlockDate);
      NFTHelper.lockTokens(swap.nftLocker, swap.executor, swap.tokenA, swap.amountA, swap.unlockDate);
    } else {
      TransferHelper.transferTokens(swap.tokenB, swap.executor, swap.initiator, swap.amountB);
      TransferHelper.withdrawTokens(swap.tokenA, swap.executor, swap.amountA);
    }
    emit SwapExecuted(_swapId);
  }

  function cancelSwap(uint256 _swapId) external nonReentrant {
    Swap memory swap = swaps[_swapId];
    require(msg.sender == swap.initiator);
    delete swaps[_swapId];
    TransferHelper.withdrawTokens(swap.tokenA, swap.initiator, swap.amountA);
    emit SwapCancelled(_swapId);
  }

  function getSwapDetails(uint256 _swapId)
    public
    view
    returns (
      address tokenA,
      address tokenB,
      uint256 amountA,
      uint256 amountB,
      uint256 unlockDate,
      address initiator,
      address executor,
      address nftLocker
    )
  {
    Swap memory swap = swaps[_swapId];
    tokenA = swap.tokenA;
    tokenB = swap.tokenB;
    amountA = swap.amountA;
    amountB = swap.amountB;
    unlockDate = swap.unlockDate;
    initiator = swap.initiator;
    executor = swap.executor;
    nftLocker = swap.nftLocker;
  }
}

