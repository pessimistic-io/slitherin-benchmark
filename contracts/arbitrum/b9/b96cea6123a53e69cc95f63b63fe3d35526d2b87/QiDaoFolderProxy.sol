// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC1967Proxy.sol";

contract QiDaoFolderProxy is ERC1967Proxy {
  constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {
  }
}

