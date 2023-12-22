// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IKyberSwapElasticLMEvents} from "./IKyberSwapElasticLMEvents.sol";
import {IERC721} from "./IERC721.sol";

interface IKyberSwapElasticLM is IKyberSwapElasticLMEvents {
  struct RewardData {
    address rewardToken;
    uint256 rewardUnclaimed;
  }

  struct LMPoolInfo {
    address poolAddress;
    uint32 startTime;
    uint32 endTime;
    uint256 totalSecondsClaimed; // scaled by (1 << 96)
    RewardData[] rewards;
    uint256 feeTarget;
    uint256 numStakes;
  }

  struct PositionInfo {
    address owner;
    uint256 liquidity;
  }

  struct StakeInfo {
    uint128 secondsPerLiquidityLast;
    uint256[] rewardLast;
    uint256[] rewardPending;
    uint256[] rewardHarvested;
    int256 feeFirst;
    uint256 liquidity;
  }

  // input data in harvestMultiplePools function
  struct HarvestData {
    uint256[] pIds;
  }

  // avoid stack too deep error
  struct RewardCalculationData {
    uint128 secondsPerLiquidityNow;
    int256 feeNow;
    uint256 vestingVolume;
    uint256 totalSecondsUnclaimed;
    uint256 secondsPerLiquidity;
    uint256 secondsClaim; // scaled by (1 << 96)
  }

  /**
   * @dev Add new pool to LM
   * @param poolAddr pool address
   * @param startTime start time of liquidity mining
   * @param endTime end time of liquidity mining
   * @param rewardTokens reward token list for pool
   * @param rewardAmounts reward amount of list token
   * @param feeTarget fee target for pool
   *
   */
  function addPool(
    address poolAddr,
    uint32 startTime,
    uint32 endTime,
    address[] calldata rewardTokens,
    uint256[] calldata rewardAmounts,
    uint256 feeTarget
  ) external;

  /**
   * @dev Renew a pool to start another LM program
   * @param pId pool id to update
   * @param startTime start time of liquidity mining
   * @param endTime end time of liquidity mining
   * @param rewardAmounts reward amount of list token
   * @param feeTarget fee target for pool
   *
   */
  function renewPool(
    uint256 pId,
    uint32 startTime,
    uint32 endTime,
    uint256[] calldata rewardAmounts,
    uint256 feeTarget
  ) external;

  /**
   * @dev Deposit NFT
   * @param nftIds list nft id
   *
   */
  function deposit(uint256[] calldata nftIds) external;

  /**
   * @dev Withdraw NFT, must exit all pool before call.
   * @param nftIds list nft id
   *
   */
  function withdraw(uint256[] calldata nftIds) external;

  /**
   * @dev Join pools
   * @param pId pool id to join
   * @param nftIds nfts to join
   * @param liqs list liquidity value to join each nft
   *
   */
  function join(uint256 pId, uint256[] calldata nftIds, uint256[] calldata liqs) external;

  /**
   * @dev Exit from pools
   * @param pId pool ids to exit
   * @param nftIds list nfts id
   * @param liqs list liquidity value to exit from each nft
   *
   */
  function exit(uint256 pId, uint256[] calldata nftIds, uint256[] calldata liqs) external;

  /**
   * @dev remove liquidity from elastic for a list of nft position, also update on farm
   * @param nftId to remove
   * @param liquidity liquidity amount to remove from nft
   * @param amount0Min expected min amount of token0 should receive
   * @param amount1Min expected min amount of token1 should receive
   * @param deadline deadline of this tx
   * @param claimFeeAndRewards also claim LP Fee and farm rewards
   */
  function removeLiquidity(
    uint256 nftId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 deadline,
    bool[2] calldata claimFeeAndRewards
  ) external;

  /**
   * @dev Claim fee from elastic for a list of nft positions
   * @param nftIds List of NFT ids to claim
   * @param amount0Min expected min amount of token0 should receive
   * @param amount1Min expected min amount of token1 should receive
   * @param poolAddress address of Elastic pool of those nfts
   * @param deadline deadline of this tx
   */
  function claimFee(
    uint256[] calldata nftIds,
    uint256 amount0Min,
    uint256 amount1Min,
    address poolAddress,
    uint256 deadline
  ) external;

  /**
   * @dev Operator only. Call to withdraw all reward from list pools.
   * @param rewards list reward address erc20 token
   * @param amounts amount to withdraw
   *
   */
  function emergencyWithdrawForOwner(
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external;

  /**
   * @dev Withdraw NFT, can call any time, reward will be reset. Must enable this func by operator
   * @param pIds list pool to withdraw
   *
   */
  function emergencyWithdraw(uint256[] calldata pIds) external;

  function nft() external view returns (IERC721);

  function poolLength() external view returns (uint256);

  function getUserInfo(
    uint256 nftId,
    uint256 pId
  )
    external
    view
    returns (uint256 liquidity, uint256[] memory rewardPending, uint256[] memory rewardLast);

  function getPoolInfo(
    uint256 pId
  )
    external
    view
    returns (
      address poolAddress,
      uint32 startTime,
      uint32 endTime,
      uint256 totalSecondsClaimed,
      uint256 feeTarget,
      uint256 numStakes,
      //index reward => reward data
      address[] memory rewardTokens,
      uint256[] memory rewardUnclaimeds
    );

  function getDepositedNFTs(address user) external view returns (uint256[] memory listNFTs);

  function getRewardCalculationData(
    uint256 nftId,
    uint256 pId
  ) external view returns (RewardCalculationData memory data);
}

