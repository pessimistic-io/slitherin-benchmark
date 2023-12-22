pragma solidity ^0.8.14;

import "./ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TT") {
        mintTokens();
    }

    function mintTokens() public {
        _mint(msg.sender, 100000000000000000000000);
    }

    function mintTokensTo(address beneficiary) public {
        _mint(beneficiary, 100000000000000000000000);
    }
}

