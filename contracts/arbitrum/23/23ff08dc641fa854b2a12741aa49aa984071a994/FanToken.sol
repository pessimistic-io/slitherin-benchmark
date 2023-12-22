pragma solidity 0.6.12;

import "./BEP20.sol";

contract FanToken is BEP20 {
    constructor(string memory name, string memory symbol) public BEP20(name, symbol) {
    }
       function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

        function burn(address addres, uint256 amount) public virtual {
        _burn(addres, amount);
    }
}

