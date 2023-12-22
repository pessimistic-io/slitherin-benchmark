// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OmniseaERC721Proxy {
    fallback() external payable {
        _delegate(address(0x838537beaB4a1dB61f4c1D24541A3c81D0C9FCE5));
    }

    receive() external payable {
        _delegate(address(0x838537beaB4a1dB61f4c1D24541A3c81D0C9FCE5));
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

