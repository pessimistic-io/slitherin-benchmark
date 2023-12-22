// SPDX-License-Identifier: MIT
pragma solidity =0.8.12;

import { MultiFeeDistribution } from "./MultiFeeDistribution.sol";
import { IMultiFeeDistributionFactory } from "./IMultiFeeDistributionFactory.sol";
import { IOwnable } from "./IOwnable.sol";
import { IICHIVault } from "./IICHIVault.sol";
import { Ownable } from "./Ownable.sol";

contract MultiFeeDistributionFactory is IMultiFeeDistributionFactory, Ownable {
    bytes32 public override constant bytecodeHash =
        keccak256(type(MultiFeeDistribution).creationCode);

    // This called in the MultiFeeDistribution constructor
    bytes public override cachedDeployData;

    mapping(address => address) public override vaultToStaker;

    address public immutable ichiFactory;

    constructor(address _ichiFactory) {
        ichiFactory = _ichiFactory;
    }

    function deployStaker(address ichiVault) external override returns (address staker) {

        require(vaultToStaker[ichiVault] == address(0), "ALREADY_DEPLOYED");

        // NOTE: this doesn't ensure tight coupling, and serves more of a sanity check
        // it's not easily possible to check if an ichiVault is registered with v1 of the ICHIVaultFactory
        require(IICHIVault(ichiVault).ichiVaultFactory() == ichiFactory, "INVALID_VF");

        bytes memory _deployData = abi.encode(ichiVault);
        cachedDeployData = _deployData;

        bytes32 salt = keccak256(_deployData);
        staker = address(new MultiFeeDistribution{salt: salt}());

        delete cachedDeployData;

        vaultToStaker[ichiVault] = staker;

        IOwnable(staker).transferOwnership(owner());

        emit StakerCreated(msg.sender, staker);
    }

}

