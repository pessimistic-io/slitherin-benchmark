// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IJBDirectory.sol";
import "./IJBProjects.sol";
import "./IJBController3_1.sol";
import "./JBProjectMetadata.sol";
import "./JBDeployTiered721DelegateData.sol";
import "./JBLaunchProjectData.sol";
import "./JBLaunchFundingCyclesData.sol";
import "./JBReconfigureFundingCyclesData.sol";
import "./IJBTiered721DelegateDeployer.sol";

interface IJBTiered721DelegateProjectDeployer {
  function directory() external view returns (IJBDirectory);

  function delegateDeployer() external view returns (IJBTiered721DelegateDeployer);

  function launchProjectFor(
    address _owner,
    JBDeployTiered721DelegateData memory _deployTieredNFTRewardDelegateData,
    JBLaunchProjectData memory _launchProjectData,
    IJBController3_1 _controller
  ) external returns (uint256 projectId);

  function launchFundingCyclesFor(
    uint256 _projectId,
    JBDeployTiered721DelegateData memory _deployTieredNFTRewardDelegateData,
    JBLaunchFundingCyclesData memory _launchFundingCyclesData,
    IJBController3_1 _controller
  ) external returns (uint256 configuration);

  function reconfigureFundingCyclesOf(
    uint256 _projectId,
    JBDeployTiered721DelegateData memory _deployTieredNFTRewardDelegateData,
    JBReconfigureFundingCyclesData memory _reconfigureFundingCyclesData,
    IJBController3_1 _controller
  ) external returns (uint256 configuration);
}

