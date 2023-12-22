// SPDX-License-Identifier: Unlicensed

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.19;

import "./ERC20.sol";

contract WebVRToken is ERC20 {
    constructor() ERC20("WebVR Token", "WTest") {
        _mint(0x019Ed608dD806b80193942F2A960e7AC8aBb2EE3, 1000000 * 10 ** decimals());
    }
}
