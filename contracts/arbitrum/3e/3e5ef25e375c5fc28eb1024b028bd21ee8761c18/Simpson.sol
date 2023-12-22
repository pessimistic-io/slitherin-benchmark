// SPDX-License-Identifier: GPL-3.0

pragma solidity >= 0.7.0;
import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract Simpson is ERC20("Simpson meme", "SIMPSON"), ERC20Burnable, Ownable{
    uint256 private maxCap = 100000000000 * 10** uint256(18);
    constructor (){
        _mint(msg.sender, maxCap);
        
    }

}

