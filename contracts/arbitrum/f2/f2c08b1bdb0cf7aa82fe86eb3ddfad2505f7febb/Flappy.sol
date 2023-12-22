pragma solidity ^0.8.9;

import "./ERC20.sol";

contract Flappy is ERC20 {
    uint256 private _cap = 696969696969e18;

    constructor() ERC20("Flappy", "FLAPPY") {
        _mint(msg.sender, _cap);
    }
}
