// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract GalaxyFounder is ERC20,Ownable {
    bool transferable;

    constructor() ERC20("GF", "Galaxy Founder") {
        transferable = false; 
    }

    function mint(uint amount, address to) public onlyOwner{
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function _transfer(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20)
    {
        require(transferable, "Error: Galaxy Founder is soulbound token");
    }
}
