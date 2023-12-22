// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";



contract Beans is ERC20 {
      constructor(
        string memory _name,
        string memory _symbol
    )
        ERC20(
            _name,
            _symbol
        )
    {}

    
}
