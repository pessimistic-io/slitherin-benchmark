// SPDX-License-Identifier: MIT

/*

If you missed xAi, then here's your second chance.

Buy $xAi2, first 100 holders get something very special.

https://t.me/xai2coin
https://twitter.com/xai2coin

___   ___      ___       __   ___   
\  \ /  /     /   \     |  | |__ \  
 \  V  /     /  ^  \    |  |    ) | 
  >   <     /  /_\  \   |  |   / /  
 /  .  \   /  _____  \  |  |  / /_  
/__/ \__\ /__/     \__\ |__| |____| 

*/

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Snapshot.sol";
import "./Ownable.sol";

/// @custom:security-contact xai2coin@gmail.com
contract XAi2 is ERC20, ERC20Snapshot, Ownable {
    constructor() ERC20("xAi 2", "xAi2") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function snapshot() public onlyOwner {
        _snapshot();
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}

