// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAdvancedQuesting {
    function emergencyEndQuesting(
        EmergencyEndQuestingParams[] calldata _endParams)
    external;
}

struct EmergencyEndQuestingParams {
    uint256 legionId;
    address owner;
    string zone;
    uint256[] treasureIds;
    uint256[] treasureAmounts;
}
