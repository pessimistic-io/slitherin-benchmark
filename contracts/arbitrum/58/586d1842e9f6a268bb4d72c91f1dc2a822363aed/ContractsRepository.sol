// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IContractsRepostiory} from "./IContractsRepostiory.sol";

contract ContractsRepository is IContractsRepostiory, IAccessControlHolder {
    bytes32 public constant REPOSITORY_OWNER = keccak256("REPOSITORY_OWNER");

    IAccessControl public override acl;
    mapping(bytes32 => address) internal repository;

    modifier onlyRepositoryOwner() {
        if (!acl.hasRole(REPOSITORY_OWNER, msg.sender)) {
            revert OnlyRepositoryOnwer();
        }
        _;
    }

    constructor(IAccessControl acl_) {
        acl = acl_;
    }

    function getContract(
        bytes32 contractId
    ) external view override returns (address) {
        address addr = repository[contractId];
        if (addr == address(0)) {
            revert ContractDoesNotExist();
        }

        return addr;
    }

    function tryGetContract(
        bytes32 contractId
    ) external view returns (address) {
        return repository[contractId];
    }

    function setContract(
        bytes32 contractId,
        address contractAddress
    ) external override onlyRepositoryOwner {
        repository[contractId] = contractAddress;
    }
}

