// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "./Ownable.sol";

contract PYESwapContractFactory is Ownable {

    event DeployedContract(address addr);
    event CallResponse(bool success, bytes data);

    function deployContract(
        uint _salt, 
        bytes memory bytecode
    ) external payable onlyOwner {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        emit DeployedContract(addr);
    }

    function callContract(address addr, bytes memory _call) external payable onlyOwner {
        (bool success, bytes memory data) = addr.call{value: msg.value}(_call);
        emit CallResponse(success, data);
    }
}
