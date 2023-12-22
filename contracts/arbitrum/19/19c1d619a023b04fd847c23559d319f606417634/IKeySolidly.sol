// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IKeySolidly {
    function depositForStrategy(address _gauge, uint256 _amount) external;
    function withdrawForStrategy(address _gauge, uint256 _amount) external;
    function balanceOfStrategy(address _gauge) external view returns (uint);
    function getRewardsForStrategy(address _gauge, address[] calldata tokens) external view returns (uint);
    function earnedOfStrategy(address _gauge, address output) external view returns (uint);
    function withdrawAllForStrategy(address _gauge) external;
    function getRewardsForStrategySimple() external;
}
