pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract FaceToken is Ownable, ERC20 {
    uint constant _initial_supply = 100000000 * (10**18);
    constructor() ERC20("FACE3", "FACE3") {
        _mint(msg.sender, _initial_supply);
    }
}
