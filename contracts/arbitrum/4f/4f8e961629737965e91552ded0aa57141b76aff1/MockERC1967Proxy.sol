// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { ERC1967Proxy } from "./ERC1967Proxy.sol";

contract MockERC1967Proxy is ERC1967Proxy {
    constructor(address _logic, bytes memory _data) payable ERC1967Proxy(_logic, _data) {}
}

