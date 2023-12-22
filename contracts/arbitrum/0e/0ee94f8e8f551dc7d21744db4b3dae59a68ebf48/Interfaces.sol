// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;
import "./IERC20.sol";
import { IProtocolRewardsHandler } from "./Radiant.sol";

interface IRdntLpStaker {
  function stake(uint256) external;

  function getRewardTokens() external view returns (address[] memory);

  function getRewardTokenCount() external view returns (uint);

  function claimProtocolFees(
    address _to
  ) external returns (IProtocolRewardsHandler.RewardData[] memory _protocolFeeRewards);

  function pendingRewardsLessFee()
    external
    view
    returns (IProtocolRewardsHandler.RewardData[] memory _protocolFeeRewards);
}

interface IFeeClaimer {
  function harvest() external;
}

interface ITokenMinter {
  function mint(address, uint256) external;

  function burn(address, uint256) external;
}

interface IDelegation {
  function setDelegate(bytes32 id, address delegate) external;
}

