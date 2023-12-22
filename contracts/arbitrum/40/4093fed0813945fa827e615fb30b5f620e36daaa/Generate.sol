// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IVault} from "./IVault.sol";
import {BytesCheck} from "./BytesCheck.sol";
import {Clones} from "./Clones.sol";
import {IOperator} from "./IOperator.sol";

library Generate {

    /// @notice deploys a new clone of `StvAccount`
    /// @param commands command to make sure the type of financial instrument
    /// @param data encoded params to create the stv
    /// @param manager address of the manager
    /// @param operator address of the operator
    /// @param maxFundraisingPeriod max fundraising period for an stv
    function generate(
        uint256 commands,
        bytes calldata data,
        address manager,
        address operator,
        uint40 maxFundraisingPeriod
    ) external returns (IVault.StvInfo memory stv, bytes32 metadataHash) {
        address stvAccountImplementation = IOperator(operator).getAddress("STVACCOUNT");
        address contractAddress;

        // generates new contract for perpetual protocols
        if (BytesCheck.checkFirstDigit0x0(uint8(commands))) {
            address defaultStableCoin = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
            (address tradeToken, uint32 leverage, bool tradeDirection, uint96 capacityOfStv, bytes32 _metadataHash) =
                abi.decode(data, (address, uint32, bool, uint96, bytes32));

            stv.manager = manager;
            stv.tradeToken = tradeToken;
            stv.depositToken = defaultStableCoin;
            stv.leverage = leverage;
            stv.tradeDirection = tradeDirection;
            stv.endTime = uint40(block.timestamp) + maxFundraisingPeriod;
            stv.capacityOfStv = capacityOfStv;

            bytes32 salt = keccak256(
                abi.encodePacked(
                    manager,
                    tradeToken,
                    defaultStableCoin,
                    leverage,
                    tradeDirection,
                    capacityOfStv,
                    block.timestamp,
                    block.chainid
                )
            );
            contractAddress = Clones.cloneDeterministic(stvAccountImplementation, salt);
            stv.stvId = contractAddress;
            metadataHash = _metadataHash;
        } // generates new salt for spot protocols
        else if (BytesCheck.checkFirstDigit0x1(uint8(commands))) {
            (address tradeToken, address depositToken, uint96 capacityOfStv, bytes32 _metadataHash) =
                abi.decode(data, (address, address, uint96, bytes32));

            stv.manager = manager;
            stv.tradeToken = tradeToken;
            stv.depositToken = depositToken;
            stv.leverage = 1;
            stv.tradeDirection = false;
            stv.endTime = uint40(block.timestamp) + maxFundraisingPeriod;
            stv.capacityOfStv = capacityOfStv;

            bytes32 salt = keccak256(
                abi.encodePacked(manager, tradeToken, depositToken, capacityOfStv, block.timestamp, block.chainid)
            );
            contractAddress = Clones.cloneDeterministic(stvAccountImplementation, salt);
            stv.stvId = contractAddress;
            metadataHash = _metadataHash;
        }
    }
}

