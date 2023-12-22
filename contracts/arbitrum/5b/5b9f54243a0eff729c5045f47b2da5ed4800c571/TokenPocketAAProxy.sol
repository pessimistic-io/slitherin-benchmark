// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "./ERC1967Proxy.sol";

contract TokenPocketAAProxy is ERC1967Proxy {

    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {

    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

}
