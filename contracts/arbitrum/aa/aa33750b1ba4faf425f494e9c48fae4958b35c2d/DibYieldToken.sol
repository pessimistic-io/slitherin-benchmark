// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20Votes.sol";

/*

Website https://dibyield.com

__/\\\\\\\\\\\\_____/\\\\\\\\\\\__/\\\\\\\\\\\\\______________/\\\________/\\\_______________________/\\\\\\____________/\\\__        
 _\/\\\////////\\\__\/////\\\///__\/\\\/////////\\\___________\///\\\____/\\\/_______________________\////\\\___________\/\\\__       
  _\/\\\______\//\\\_____\/\\\_____\/\\\_______\/\\\_____________\///\\\/\\\/_____/\\\___________________\/\\\___________\/\\\__      
   _\/\\\_______\/\\\_____\/\\\_____\/\\\\\\\\\\\\\\________________\///\\\/______\///______/\\\\\\\\_____\/\\\___________\/\\\__     
    _\/\\\_______\/\\\_____\/\\\_____\/\\\/////////\\\_________________\/\\\________/\\\___/\\\/////\\\____\/\\\______/\\\\\\\\\__    
     _\/\\\_______\/\\\_____\/\\\_____\/\\\_______\/\\\_________________\/\\\_______\/\\\__/\\\\\\\\\\\_____\/\\\_____/\\\////\\\__   
      _\/\\\_______/\\\______\/\\\_____\/\\\_______\/\\\_________________\/\\\_______\/\\\_\//\\///////______\/\\\____\/\\\__\/\\\__  
       _\/\\\\\\\\\\\\/____/\\\\\\\\\\\_\/\\\\\\\\\\\\\/__________________\/\\\_______\/\\\__\//\\\\\\\\\\__/\\\\\\\\\_\//\\\\\\\/\\_ 
        _\////////////_____\///////////__\/////////////____________________\///________\///____\//////////__\/////////___\///////\//__
*/

contract DibYieldToken is ERC20, Ownable, ERC20Permit, ERC20Votes {
    constructor() ERC20("DibYield", "DIB") ERC20Permit("DibYield") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}

