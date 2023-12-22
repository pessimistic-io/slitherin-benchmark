// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

interface IContractsRepostiory {
    error ContractDoesNotExist();
    error OnlyRepositoryOnwer();

    function getContract(bytes32 contractId) external view returns (address);

    function tryGetContract(bytes32 contractId) external view returns (address);

    function setContract(bytes32 contractId, address contractAddress) external;
}

