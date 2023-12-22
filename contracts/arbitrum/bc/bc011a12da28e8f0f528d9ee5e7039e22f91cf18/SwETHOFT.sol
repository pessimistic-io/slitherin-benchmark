// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./OFT.sol";

contract SwETHOFT is OFT {
    constructor(address _layerZeroEndpoint) OFT("swETH", "swETH", _layerZeroEndpoint) {}
}

