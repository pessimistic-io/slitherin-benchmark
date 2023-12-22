//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeEsPegRewardPoolV2 {
    function approveContract(address contract_) external;

    function revokeContract(address contract_) external;

    function updateStakingContract(address _staking) external;

    ///@notice backward compatibility with esPeg staking/vesting contract V1
    function allocatePegStaking(uint256 _amount) external;

    function fundContractOperation(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function retrieve(address _token) external;
}

