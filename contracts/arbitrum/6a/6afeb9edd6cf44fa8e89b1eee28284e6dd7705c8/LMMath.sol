// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {MathConstants as C} from "./MathConstants.sol";

library LMMath {
  function calcSumRewardPerLiquidity(
    uint256 rewardAmount,
    uint32 startTime,
    uint32 endTime,
    uint32 curTime,
    uint32 lastTouchedTime,
    uint256 totalLiquidity
  ) internal pure returns (uint256 deltaSumRewardPerLiquidity) {
    uint256 joinedDuration;
    uint256 duration;

    unchecked {
      joinedDuration = (curTime < endTime ? curTime : endTime) - lastTouchedTime;
      duration = endTime - startTime;
      deltaSumRewardPerLiquidity =
        (rewardAmount * joinedDuration * C.TWO_POW_96) /
        (duration * totalLiquidity);
    }
  }

  function calcRewardAmount(
    uint256 curSumRewardPerLiquidity,
    uint256 lastSumRewardPerLiquidity,
    uint256 liquidity
  ) internal pure returns (uint256 rewardAmount) {
    uint256 deltaSumRewardPerLiquidity;

    unchecked {
      deltaSumRewardPerLiquidity = curSumRewardPerLiquidity - lastSumRewardPerLiquidity;
      rewardAmount = (deltaSumRewardPerLiquidity * liquidity) / C.TWO_POW_96;
    }
  }

  function calcRewardUntilNow(
    uint256 rewardAmount,
    uint32 startTime,
    uint32 endTime,
    uint32 curTime
  ) internal pure returns (uint256 rewardAmountNow) {
    uint256 joinedDuration;
    uint256 duration;

    unchecked {
      joinedDuration = curTime - startTime;
      duration = endTime - startTime;
      rewardAmountNow = (rewardAmount * joinedDuration) / duration;
    }
  }
}

