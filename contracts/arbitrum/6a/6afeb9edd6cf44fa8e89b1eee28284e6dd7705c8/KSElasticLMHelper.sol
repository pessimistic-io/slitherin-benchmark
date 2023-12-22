// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {MathConstants as C} from "./MathConstants.sol";
import {FullMath} from "./FullMath.sol";
import {LMMath} from "./LMMath.sol";
import {ReinvestmentMath} from "./ReinvestmentMath.sol";

import {IKSElasticLMHelper} from "./IKSElasticLMHelper.sol";
import {IBasePositionManager} from "./IBasePositionManager.sol";
import {IPoolStorage} from "./IPoolStorage.sol";
import {IKSElasticLMV2 as IELMV2} from "./IKSElasticLMV2.sol";

import {KSAdmin} from "./KSAdmin.sol";

contract KSElasticLMHelper is IKSElasticLMHelper, KSAdmin {
  error PositionNotEligible();

  using SafeERC20 for IERC20;

  event RescueFund(address token, uint256 amount);

  function rescueFund(IERC20 token, uint256 amount) external isAdmin {
    if (address(token) == address(0)) {
      (bool success, ) = payable(msg.sender).call{value: amount}('');
      require(success, 'rescueFund: failed to collect native');
    } else {
      token.safeTransfer(msg.sender, amount);
    }
    emit RescueFund(address(token), amount);
  }

  function checkPool(
    address pAddress,
    address nftContract,
    uint256 nftId
  ) external view override returns (bool) {
    IBasePositionManager.Position memory pData = _getPositionFromNFT(nftContract, nftId);
    return IBasePositionManager(nftContract).addressToPoolId(pAddress) == pData.poolId;
  }

  /// @dev use virtual to be overrided to mock data for fuzz tests
  function getActiveTime(
    address pAddr,
    address nftContract,
    uint256 nftId
  ) external view override returns (uint128) {
    IBasePositionManager.Position memory pData = _getPositionFromNFT(nftContract, nftId);
    return IPoolStorage(pAddr).getSecondsPerLiquidityInside(pData.tickLower, pData.tickUpper);
  }

  function getSignedFee(
    address nftContract,
    uint256 nftId
  ) external view override returns (int256) {
    uint256 feeGrowthInsideLast = _getFee(nftContract, nftId);
    return int256(feeGrowthInsideLast);
  }

  function getSignedFeePool(
    address poolAddress,
    address nftContract,
    uint256 nftId
  ) external view override returns (int256) {
    uint256 feeGrowthInside = _getFeePool(poolAddress, nftContract, nftId);
    return int256(feeGrowthInside);
  }

  function getLiq(address nftContract, uint256 nftId) external view override returns (uint128) {
    IBasePositionManager.Position memory pData = _getPositionFromNFT(nftContract, nftId);
    return pData.liquidity;
  }

  function getPair(
    address nftContract,
    uint256 nftId
  ) external view override returns (address, address) {
    (, IBasePositionManager.PoolInfo memory poolInfo) = IBasePositionManager(nftContract)
      .positions(nftId);

    return (poolInfo.token0, poolInfo.token1);
  }

  // ======== read from farm ============
  function getCurrentUnclaimedReward(
    IELMV2 farm,
    uint256 nftId
  ) public view override returns (uint256[] memory currentUnclaimedRewards) {
    (
      ,
      uint256 fId,
      ,
      uint256 sLiq,
      uint256[] memory sLastSumRewardPerLiquidity,
      uint256[] memory sRewardUnclaimeds
    ) = farm.getStake(nftId);

    (
      ,
      ,
      IELMV2.PhaseInfo memory phase,
      uint256 fLiq,
      ,
      uint256[] memory sumRewardPerLiquidity,
      uint32 lastTouchedTime
    ) = farm.getFarm(fId);

    currentUnclaimedRewards = new uint256[](phase.rewards.length);

    for (uint256 i; i < phase.rewards.length; i++) {
      uint256 tempSumRewardPerLiquidity = _updateRwPLiq(
        phase.rewards[i].rewardAmount,
        phase.startTime,
        phase.endTime,
        lastTouchedTime,
        fLiq,
        phase.isSettled,
        sumRewardPerLiquidity[i]
      );

      currentUnclaimedRewards[i] =
        sRewardUnclaimeds[i] +
        FullMath.mulDivFloor(
          tempSumRewardPerLiquidity - sLastSumRewardPerLiquidity[i],
          sLiq,
          C.TWO_POW_96
        );
    }
  }

  function getEligibleRanges(
    IELMV2 farm,
    uint256 fId,
    uint256 nftId
  ) external view returns (uint256[] memory indexesValid) {
    address nftAddr = address(farm.getNft());
    (address poolAddr, IELMV2.RangeInfo[] memory rangesInfo, , , , , ) = farm.getFarm(fId);
    if (!_checkPool(poolAddr, nftAddr, nftId)) revert PositionNotEligible();

    (, int24 tickLower, int24 tickUpper, ) = getPositionInfo(nftAddr, nftId);

    uint256 length = rangesInfo.length;
    uint256 count;
    for (uint256 i; i < length; ++i) {
      if (
        tickLower <= rangesInfo[i].tickLower &&
        tickUpper >= rangesInfo[i].tickUpper &&
        !rangesInfo[i].isRemoved
      ) ++count;
    }

    indexesValid = new uint256[](count);
    for (uint256 j = length - 1; j > 0; --j) {
      if (
        tickLower <= rangesInfo[j].tickLower &&
        tickUpper >= rangesInfo[j].tickUpper &&
        !rangesInfo[j].isRemoved
      ) {
        indexesValid[count - 1] = j;
        --count;
      }
    }
  }

  function getUserInfo(
    IELMV2 farm,
    address user
  ) external view returns (UserInfo[] memory result) {
    uint256[] memory listNFTs = farm.getDepositedNFTs(user);
    result = new UserInfo[](listNFTs.length);
    for (uint256 i = 0; i < listNFTs.length; ++i) {
      (, uint256 fId, uint256 rId, uint256 sLiq, , ) = farm.getStake(listNFTs[i]);
      result[i].nftId = listNFTs[i];
      result[i].fId = fId;
      result[i].rangeId = rId;
      result[i].liquidity = sLiq;
      result[i].currentUnclaimedRewards = getCurrentUnclaimedReward(farm, listNFTs[i]);
    }
  }

  // ======== read from posManager ============
  function getPositionInfo(
    address nftContract,
    uint256 nftId
  ) public view override returns (uint256, int24, int24, uint128) {
    IBasePositionManager.Position memory pData = _getPositionFromNFT(nftContract, nftId);
    return (pData.poolId, pData.tickLower, pData.tickUpper, pData.liquidity);
  }

  function checkPosition(
    address pAddress,
    address nftContract,
    int24 tickLower,
    int24 tickUpper,
    uint256[] memory nftIds
  ) external view override returns (bool isInvalid, uint128[] memory liquidities) {
    uint256 length = nftIds.length;
    liquidities = new uint128[](length);
    uint256 poolId = IBasePositionManager(nftContract).addressToPoolId(pAddress);

    for (uint256 i; i < length; ) {
      (
        uint256 nftPoolId,
        int24 nftTickLower,
        int24 nftTickUpper,
        uint128 liquidity
      ) = getPositionInfo(nftContract, nftIds[i]);

      if (
        poolId != nftPoolId ||
        tickLower < nftTickLower ||
        nftTickUpper < tickUpper ||
        liquidity == 0
      ) {
        isInvalid = true;
        break;
      }

      liquidities[i] = liquidity;

      unchecked {
        ++i;
      }
    }
  }

  function _updateRwPLiq(
    uint256 rwAmount,
    uint32 startTime,
    uint32 endTime,
    uint32 lastTouchedTime,
    uint256 totalLiquidity,
    bool isSettled,
    uint256 curSumRewardPerLiquidity
  ) internal view returns (uint256) {
    if (block.timestamp > lastTouchedTime && !isSettled) {
      uint256 deltaSumRewardPerLiquidity = LMMath.calcSumRewardPerLiquidity(
        rwAmount,
        startTime,
        endTime,
        uint32(block.timestamp),
        lastTouchedTime,
        totalLiquidity
      );

      curSumRewardPerLiquidity += deltaSumRewardPerLiquidity;
    }

    return curSumRewardPerLiquidity;
  }

  function _checkPool(
    address pAddress,
    address nftContract,
    uint256 nftId
  ) internal view returns (bool) {
    IBasePositionManager.Position memory pData = _getPositionFromNFT(nftContract, nftId);
    return IBasePositionManager(nftContract).addressToPoolId(pAddress) == pData.poolId;
  }

  function _getPositionFromNFT(
    address nftContract,
    uint256 nftId
  ) internal view returns (IBasePositionManager.Position memory) {
    (IBasePositionManager.Position memory pData, ) = IBasePositionManager(nftContract).positions(
      nftId
    );
    return pData;
  }

  function _getFee(address nftContract, uint256 nftId) internal view virtual returns (uint256) {
    IBasePositionManager.Position memory pData = _getPositionFromNFT(nftContract, nftId);
    return pData.feeGrowthInsideLast;
  }

  function _getFeePool(
    address poolAddress,
    address nftContract,
    uint256 nftId
  ) internal view virtual returns (uint256 feeGrowthInside) {
    IBasePositionManager.Position memory position = _getPositionFromNFT(nftContract, nftId);
    (, , uint256 lowerValue, ) = IPoolStorage(poolAddress).ticks(position.tickLower);
    (, , uint256 upperValue, ) = IPoolStorage(poolAddress).ticks(position.tickUpper);
    (, int24 currentTick, , ) = IPoolStorage(poolAddress).getPoolState();
    uint256 feeGrowthGlobal = IPoolStorage(poolAddress).getFeeGrowthGlobal();

    {
      (uint128 baseL, uint128 reinvestL, uint128 reinvestLLast) = IPoolStorage(poolAddress)
        .getLiquidityState();
      uint256 rTotalSupply = IERC20(poolAddress).totalSupply();
      // logic ported from Pool._syncFeeGrowth()
      uint256 rMintQty = ReinvestmentMath.calcrMintQty(
        uint256(reinvestL),
        uint256(reinvestLLast),
        baseL,
        rTotalSupply
      );

      if (rMintQty != 0) {
        // fetch governmentFeeUnits
        (, uint24 governmentFeeUnits) = IPoolStorage(poolAddress).factory().feeConfiguration();
        unchecked {
          if (governmentFeeUnits != 0) {
            uint256 rGovtQty = (rMintQty * governmentFeeUnits) / C.FEE_UNITS;
            rMintQty -= rGovtQty;
          }
          feeGrowthGlobal += FullMath.mulDivFloor(rMintQty, C.TWO_POW_96, baseL);
        }
      }
    }
    unchecked {
      if (currentTick < position.tickLower) {
        feeGrowthInside = lowerValue - upperValue;
      } else if (currentTick >= position.tickUpper) {
        feeGrowthInside = upperValue - lowerValue;
      } else {
        feeGrowthInside = feeGrowthGlobal - (lowerValue + upperValue);
      }
    }
  }
}

