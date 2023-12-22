// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OmniseaERC721Proxy {
    fallback() external payable {
        _delegate(address(0x1000270B3eFe49dc83de59D9259F62DACb28841C));
    }

    receive() external payable {
        _delegate(address(0x1000270B3eFe49dc83de59D9259F62DACb28841C));
    }

    function _delegate(address _proxyTo) internal {
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), _proxyTo, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}

