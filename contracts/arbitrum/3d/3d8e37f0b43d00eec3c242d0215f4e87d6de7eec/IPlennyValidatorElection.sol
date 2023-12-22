// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyValidatorElection {

    function validators(uint256 electionBlock, address addr) external view returns (bool);

    function latestElectionBlock() external view returns (uint256);

    function getElectedValidatorsCount(uint256 electionBlock) external view returns (uint256);

    function reserveReward(address validator, uint256 amount) external;

}
