// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

/// @custom:security-contact info@veniceswap.com
contract AInovaToken is ERC20 {
    constructor() ERC20("AInova Token", "AINOVA") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }
}

