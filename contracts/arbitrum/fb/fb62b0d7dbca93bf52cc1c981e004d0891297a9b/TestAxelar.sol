// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IAxelarGateway} from "./IAxelarGateway.sol";
import {IERC20} from "./IERC20.sol";
import {IAxelarGasService} from "./IAxelarGasService.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract TestAxelar {
    IAxelarGasService public immutable gasService;
    IAxelarGateway public immutable gateway;

    constructor(
        address gateway_,
        address gasService_
    ) {
        gateway = IAxelarGateway(gateway_);
        gasService = IAxelarGasService(gasService_);
    }

    // Call this function to update the value of this contract along with all its siblings'.
    function testCallContract(
        string calldata destinationChain,
        string calldata destinationAddress,
        string calldata randomData
    ) external payable {
        bytes memory payloadWithVersion = abi.encodePacked(
            bytes4(uint32(0)), // version number
            abi.encode(randomData)
        );
        // optional pay gas service
        if (msg.value > 0) {
            gasService.payNativeGasForContractCall{value: msg.value}(
                address(this),
                destinationChain,
                destinationAddress,
                payloadWithVersion,
                msg.sender
            );
        }
        gateway.callContract(destinationChain, destinationAddress, payloadWithVersion);
    }

    function testCallContractWithToken(
        string memory destinationChain,
        string memory destinationAddress,
        string calldata randomData,
        string memory symbol,
        uint256 amount
    ) external payable {
        address tokenAddress = gateway.tokenAddresses(symbol);
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        IERC20(tokenAddress).approve(address(gateway), amount);

        bytes memory payloadWithVersion = abi.encodePacked(
            bytes4(uint32(0)), // version number
            abi.encode(randomData)
        );

        // optional pay gas service
        if (msg.value > 0) {
            gasService.payNativeGasForContractCallWithToken{value: msg.value}(
                address(this),
                destinationChain,
                destinationAddress,
                payloadWithVersion,
                symbol,
                amount,
                msg.sender
            );
        }

        gateway.callContractWithToken(
            destinationChain,
            destinationAddress,
            payloadWithVersion,
            symbol,
            amount
        );
    }
}

