//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { USDCMilestone, PLSMilestone, User } from "./Structs.sol";

interface ITGE {
    function getUsdcMilestones(uint8 milestone) external view returns (USDCMilestone memory);

    function getPlsMilestones(uint8 milestone) external view returns (PLSMilestone memory);

    function totalUserPegAllocation(address _user) external view returns (uint256);

    function hasStarted() external view returns (bool);

    function isDonationPaused() external view returns (bool);

    function currentUSDCMilestone() external view returns (uint8);

    function currentPLSMilestone() external view returns (uint8);

    function updateUSDCRaised(uint8 milestone, uint256 _amount) external;

    function updatePLSRaised(uint8 milestone, uint256 _amount, uint256 _plsAmount) external;

    function updateUserUSDCdonations(uint8 milestone, address _user, uint256 _amount) external;

    function updateUserPLSdonations(uint8 milestone, address _user, uint256 _amount) external;

    function updateUserUSDCpegAllocation(uint8 milestone, address _user, uint256 userpegAllocationAmount) external;

    function updateUserPLSpegAllocation(uint8 milestone, address _user, uint256 userpegAllocationAmount) external;

    function setUpVaults(address _plsVault, address _usdcVault) external;

    function allowPegClaim() external;

    function updateMilestone() external;

    function checkMilestoneCleared() external returns (bool);

    function getAllUsersPerMilestone(uint8 milestone) external returns (User[] memory);
}

