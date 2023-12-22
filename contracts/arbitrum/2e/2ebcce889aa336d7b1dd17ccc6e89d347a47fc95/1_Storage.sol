pragma solidity ^0.6.0;

import "./ERC20.sol";

contract ART is ERC20 {
    constructor() ERC20("ART", "ART") public {
        _mint(msg.sender, 1000000000000000000000000000);
    }
}
