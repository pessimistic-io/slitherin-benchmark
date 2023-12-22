// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {ERC1967Upgrade} from "./ERC1967Upgrade.sol";
import {Context} from "./Context.sol";
import {IWormhole} from "./IWormhole.sol";
import {ICircleBridge} from "./ICircleBridge.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {ITokenMinter} from "./ITokenMinter.sol";

import {CircleIntegrationSetters} from "./CircleIntegrationSetters.sol";

contract CircleIntegrationSetup is CircleIntegrationSetters, ERC1967Upgrade, Context {
    function setup(
        address implementation,
        address wormholeAddress,
        uint8 finality,
        address circleBridgeAddress,
        uint16 governanceChainId,
        bytes32 governanceContract
    ) public {
        require(implementation != address(0), "invalid implementation");
        require(wormholeAddress != address(0), "invalid wormhole address");
        require(circleBridgeAddress != address(0), "invalid circle bridge address");

        setWormhole(wormholeAddress);
        setChainId(IWormhole(wormholeAddress).chainId());
        setWormholeFinality(finality);
        setCircleBridge(circleBridgeAddress);
        setGovernance(governanceChainId, governanceContract);

        // Cache circle bridge
        ICircleBridge circleBridge = ICircleBridge(circleBridgeAddress);

        // Circle message transmitter contract
        IMessageTransmitter messageTransmitter = circleBridge.localMessageTransmitter();
        setCircleTransmitter(address(messageTransmitter));
        setLocalDomain(messageTransmitter.localDomain());

        // Circle token minter contract
        ITokenMinter tokenMinter = circleBridge.localMinter();
        setCircleTokenMinter(address(tokenMinter));

        setEvmChain(block.chainid);

        // set the implementation
        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}

