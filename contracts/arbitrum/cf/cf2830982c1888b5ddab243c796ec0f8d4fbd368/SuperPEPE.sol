// SPDX-License-Identifier: MIT

// SuperPEPE is a memecoin on Arbitrum by SuperARB Project.

// Website: SuperARB.com

pragma solidity ^0.8.0;

import "./ERC20Drop.sol";

contract SuperPEPE is ERC20Drop {
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
