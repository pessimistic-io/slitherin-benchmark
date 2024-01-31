// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC721Receiver.sol";
import "./IJBFundingCycleDataSource.sol";
import "./DeployBluntDelegateDeployerData.sol";
import "./DeployBluntDelegateData.sol";
import "./RoundInfo.sol";

interface IBluntDelegate is
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate,
  IERC721Receiver
{
  function getRoundInfo() external view returns (RoundInfo memory roundInfo);

  function closeRound() external;

  function setDeadline(uint256 deadline_) external;

  function isTargetReached() external view returns (bool);
}

