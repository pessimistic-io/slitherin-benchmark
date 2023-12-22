//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ITGE } from "./ITGE.sol";
import { Milestone, User } from "./Structs.sol";

interface ITGE2 is ITGE {
    function currentMilestone() external view returns (uint8);

    function milestones(uint8 milestone) external view returns (Milestone memory);

    function donatedInMilestone(address user, uint8 milestone) external view returns (bool);

    function userIndex(address user, uint8 milestone) external view returns (uint256);

    function users(uint8 milestone) external view returns (User[] memory);
}

