// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { CREATE3 } from "./CREATE3.sol";

import { ICREATE3Factory } from "./ICREATE3Factory.sol";

/// @title  InstadappCREATE3Factory
/// @notice Factory for deploying contracts to deterministic addresses via CREATE3.
/// Resulting deterministic address is independent of constructor args.
contract InstadappCREATE3Factory is ICREATE3Factory {
    /// @inheritdoc	ICREATE3Factory
    function deploy(bytes32 salt, bytes memory creationCode) external payable override returns (address deployed) {
        return CREATE3.deploy(salt, creationCode, msg.value);
    }

    /// @inheritdoc	ICREATE3Factory
    function getDeployed(bytes32 salt) external view override returns (address deployed) {
        return CREATE3.getDeployed(salt);
    }
}

