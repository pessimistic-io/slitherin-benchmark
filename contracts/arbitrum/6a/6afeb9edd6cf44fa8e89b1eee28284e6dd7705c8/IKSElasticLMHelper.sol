// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBasePositionManager} from "./IBasePositionManager.sol";
import {IKSElasticLMV2 as IELMV2} from "./IKSElasticLMV2.sol";
import {IKyberSwapFarmingToken} from "./IKyberSwapFarmingToken.sol";

interface IKSElasticLMHelper {
  struct UserInfo {
    uint256 nftId;
    uint256 fId;
    uint256 rangeId;
    uint256 liquidity;
    uint256[] currentUnclaimedRewards;
  }

  //use by both LMv1 and LMv2
  function checkPool(
    address pAddress,
    address nftContract,
    uint256 nftId
  ) external view returns (bool);

  function getLiq(address nftContract, uint256 nftId) external view returns (uint128);

  function getPair(address nftContract, uint256 nftId) external view returns (address, address);

  //use by LMv1
  function getActiveTime(
    address pAddr,
    address nftContract,
    uint256 nftId
  ) external view returns (uint128);

  function getSignedFee(address nftContract, uint256 nftId) external view returns (int256);

  function getSignedFeePool(
    address poolAddress,
    address nftContract,
    uint256 nftId
  ) external view returns (int256);

  //use by LMv2
  function getCurrentUnclaimedReward(
    IELMV2 farm,
    uint256 nftId
  ) external view returns (uint256[] memory currentUnclaimedRewards);

  function getUserInfo(IELMV2 farm, address user) external view returns (UserInfo[] memory);

  function getEligibleRanges(
    IELMV2 farm,
    uint256 fId,
    uint256 nftId
  ) external view returns (uint256[] memory indexesValid);

  function checkPosition(
    address pAddress,
    address nftContract,
    int24 tickLower,
    int24 tickUpper,
    uint256[] memory nftIds
  ) external view returns (bool isInvalid, uint128[] memory liquidities);

  function getPositionInfo(
    address nftContract,
    uint256 nftId
  ) external view returns (uint256, int24, int24, uint128);
}

