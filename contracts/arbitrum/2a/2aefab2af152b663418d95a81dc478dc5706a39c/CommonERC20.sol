pragma solidity ^0.8.0;

import {ERC20Burnable} from "./ERC20Burnable.sol";
import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

contract CommonERC20 is ERC20Burnable, Ownable {
    constructor(string memory _name, string memory _symbol) public ERC20(_name, _symbol) {
        _mint(msg.sender, 1 * 10**8 * 10**18);
    }

    function burn(uint256 amount) public override onlyOwner {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount)
    public
    override
    onlyOwner
    {
        super.burnFrom(account, amount);
    }
}

