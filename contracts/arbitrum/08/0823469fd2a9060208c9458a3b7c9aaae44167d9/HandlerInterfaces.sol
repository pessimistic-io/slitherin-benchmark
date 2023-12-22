//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;

interface RouterInterface {
    function withdrawRewards(address[] memory lTokens) external;
}

interface VotingInterface {
    enum OperationType {
        SUPPLY,
        BORROW
    }

    function getResults() external view returns (string[] memory, OperationType[] memory, uint256[] memory);

    function paused() external view returns (bool);
}

interface ComptrollerInterface {
    function _setCompSpeeds(address[] memory cTokens, uint[] memory supplySpeeds, uint[] memory borrowSpeeds) external;
}

interface StakingRewardsInterface {
    function paused() external view returns (bool);
}

