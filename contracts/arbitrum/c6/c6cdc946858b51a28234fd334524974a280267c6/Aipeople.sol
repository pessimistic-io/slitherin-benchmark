// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IAntiBot.sol";
import "./ERC20Pausable.sol";
import "./Ownable.sol";
import "./ERC20.sol";

//secure smart contracts have been tested several times
contract Aipeople is  ERC20Pausable, Ownable {
     IAntiBot private _antiBot;
    bool public antiBotEnabled;

    event SetAntiBot(address antiBot_);
    event EnableAntibot(bool enabled_);

    
        constructor() ERC20("ARB PEOPLE AI", "AIPEOPLE"){
        _mint(msg.sender, 250000000000000000000000000000000000);
    }
    

function pause() external onlyOwner {
        _pause();
    }

    function unPause() external onlyOwner {
        _unpause();
    }

    function setAntiBot(IAntiBot antiBot_) external onlyOwner {
        _antiBot = antiBot_;
        emit SetAntiBot(address(_antiBot));
    }

    function enabledAntiBot(bool _enabled) external onlyOwner {
        antiBotEnabled = _enabled;
        emit EnableAntibot(antiBotEnabled);
    }

    function _beforeTokenTransfer(
        address sender,
        address receiver,
        uint256 amount
    ) internal override (ERC20Pausable) {
        if(antiBotEnabled){
           _antiBot.protect(sender, receiver, amount);
        }
        super._beforeTokenTransfer(sender, receiver, amount);
    } 
}
