pragma solidity ^0.7.6;

import "./Ownable.sol";
import "./ERC20.sol";

contract MintableToken is Ownable, ERC20 {
    constructor() public ERC20("ACCT", "ACCT") { }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}
