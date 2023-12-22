// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OmniseaERC721Proxy {
    fallback() external payable {
        _delegate(address(0xD7Ef8B253dbe20D667E19b5a559e79d42EbCF0F0));
    }

    receive() external payable {
        _delegate(address(0xD7Ef8B253dbe20D667E19b5a559e79d42EbCF0F0));
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

