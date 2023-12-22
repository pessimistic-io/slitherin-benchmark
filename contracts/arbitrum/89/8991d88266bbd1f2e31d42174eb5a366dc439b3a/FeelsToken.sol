// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract FeelsToken is ERC20, ERC20Burnable, Ownable {
      constructor(
        string memory _name,
        string memory _symbol
    )
        ERC20(
            _name,
            _symbol
        )
    {
        _mint(msg.sender, 4000000000004 * 10 ** decimals());
    }
}
