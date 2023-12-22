// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.17;

import "./Address.sol";

contract Proxy {
    using Address for address;

    address public immutable implementation;

    constructor(address impl) {
        require(
            impl.isContract(),
            "P: implementation must be an existing contract address"
        );

        implementation = impl;
    }

    fallback() external payable {
        _delegateCall(implementation);
    }

    receive() external payable {
        _delegateCall(implementation);
    }

    function _delegateCall(address impl) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

