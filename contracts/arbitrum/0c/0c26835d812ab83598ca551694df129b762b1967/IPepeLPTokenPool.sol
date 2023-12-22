//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeLPTokenPool {
    function approveContract(address contract_) external;

    function revokeContract(address contract_) external;

    function fundContractOperation(address contract_, uint256 amount) external;

    function withdraw(uint256 amount) external;

    function retrieve(address _token) external;
}

