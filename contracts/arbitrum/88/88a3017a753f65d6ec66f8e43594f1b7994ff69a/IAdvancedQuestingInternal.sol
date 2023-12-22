// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAdvancedQuestingInternal {
    function unstakeTreasures(
        uint256 _legionId,
        bool _usingOldSchema,
        bool _isRestarting,
        address _owner)
    external
    returns(uint256[] memory, uint256[] memory);
}
