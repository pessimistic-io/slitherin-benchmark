// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ProxyOFT.sol";

contract Proxy is ProxyOFT {
    constructor(
        string memory _name,
        address _lzEndpoint,
        address _token
    ) ProxyOFT(_lzEndpoint, _token) {}
}

