// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { Ownable } from "./Ownable.sol";

contract CoinBookContractFactory is Ownable {
    event DeployedLogic(address addr);
    event DeployedProxy(address addr);
    event DeployedContract(address addr);
    event CallResponse(bool success, bytes data);

    address[] public deployedAddresses;
    mapping(address => bytes) deployedBytecode;

    function deployBundle(
        bytes memory bytecodeLogic, 
        bytes memory createcodeProxy, 
        address _admin, 
        uint version, 
        bytes memory _call
    ) external payable onlyOwner {
        address _logic = deployLogic(1313131313 * version, bytecodeLogic);
        address _proxy = deployProxy(7979797979 * version, createcodeProxy, _logic, _admin);
        if (_call.length > 0) {
            (bool success, bytes memory data) = _proxy.call{value: msg.value}(_call);
            emit CallResponse(success, data);
        }
    }

    function deployContract(uint _salt, bytes memory bytecode) external onlyOwner {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        deployedAddresses.push(addr);
        deployedBytecode[addr] = bytecode;
        emit DeployedContract(addr);
    }

    function deployLogic(uint _salt, bytes memory bytecode) internal returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        deployedAddresses.push(addr);
        deployedBytecode[addr] = bytecode;
        emit DeployedLogic(addr);
    }

    function deployProxy(
        uint _salt, 
        bytes memory createcode, 
        address _logic, 
        address _admin
    ) internal returns (address addr) {
        bytes memory bytecode = abi.encodePacked(createcode, abi.encode(_logic, _admin));
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        deployedAddresses.push(addr);
        deployedBytecode[addr] = createcode;
        emit DeployedProxy(addr);
    }
}
