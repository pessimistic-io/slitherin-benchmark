// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import {ERC20} from "./ERC20.sol";
import {ERC20Permit} from "./draft-ERC20Permit.sol";
import {ERC20Votes} from "./ERC20Votes.sol";
import {Ownable} from "./Ownable.sol";

contract DeSwap is ERC20, ERC20Permit, ERC20Votes, Ownable {

    constructor() ERC20("DAW-GPT", "DAW") ERC20Permit("DAW") {
         _mint(msg.sender, 100000000 * 10**decimals());
    }
    function decimals() 
        public 
        pure 
        override(ERC20)
        returns (uint8) 
    {
        return 18;
    }
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}

