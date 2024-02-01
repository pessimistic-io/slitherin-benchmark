// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.14; 


import "./ERC1967Proxy.sol";
import "./ReentrancyGuard.sol";


/**
 * @notice ProxyFactory's proxy 
 */
contract ozERC1967Proxy is ReentrancyGuard, ERC1967Proxy {
    constructor(address logic_, bytes memory data_) ERC1967Proxy(logic_, data_) {}

    function getImplementation() external view returns(address) {
        return _implementation();
    }
}
