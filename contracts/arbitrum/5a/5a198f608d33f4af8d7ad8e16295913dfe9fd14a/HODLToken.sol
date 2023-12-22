pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract HODLToken is Ownable, ERC20 {
    uint constant _initial_supply = 69420000 * (10**18);
    constructor() ERC20("HODL", "HODL") {
        _mint(msg.sender, _initial_supply);
    }
}
