// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./BoringFactory.sol";
import "./BoringBatchable.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

contract SimpleFactory is BoringFactory, BoringBatchable {
    event Deployed(address indexed addr);

    function transferOwnership(address owned, address newOwner) external {
        IOwnable(owned).transferOwnership(newOwner);
    }

    function exec(address target, bytes calldata data) external {
        target.call(data);
    }

    /// @dev if using constructor args, use abi.encodePacked(arg); to append your args to the bytecode
    function deployWithByteCode(bytes memory bytecode, bool useCreate2) external returns (address addr){
        if (useCreate2) {
            bytes32 salt = keccak256(bytecode);
            assembly {
                addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
                if iszero(extcodesize(addr)) {
                    revert(0, 0)
                }
            }
        } else {
            assembly {
                addr := create(0, add(bytecode, 0x20), mload(bytecode))
                if iszero(extcodesize(addr)) {
                    revert(0, 0)
                }
            }
        }

        emit Deployed(addr);
    }
}
