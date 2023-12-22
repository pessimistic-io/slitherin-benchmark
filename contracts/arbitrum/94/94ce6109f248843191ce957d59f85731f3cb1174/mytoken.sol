// SPDX-License-Identifier: MIT

// DO NOT INTERACT! THIS IS A TEST CONTRACT.

pragma solidity ^0.8.0;

import "./ERC20Drop.sol";

contract MyToken is ERC20Drop {
      constructor(
        string memory _name,
        string memory _symbol,
        address _primarySaleRecipient
    )
        ERC20Drop(
            _name,
            _symbol,
            _primarySaleRecipient
        )
    {}
}
