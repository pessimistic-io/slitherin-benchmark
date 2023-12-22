// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;

import "./ERC1967Proxy.sol";

contract LsdogeProxy is ERC1967Proxy {
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data){
    }
}
