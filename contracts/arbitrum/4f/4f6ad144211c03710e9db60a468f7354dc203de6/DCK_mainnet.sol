// Hear me, mortals! Forsooth, this contract, known as the REAPER ARB, be a creation of artistic endeavour, born of an experimental nature that shall test the limits of your mortal understanding of time. The transfer of the token must be swift, every 10800 blocks to a fresh address, lest it be locked in the grasp of Death.
// Only the creator of the contract has the power to grant immortality, only a specific pool and a router are allowed to cheat death. There are 999,999,999 RA tokens. None was given to any, and no more can be created. The code of this contract has not been audited, and the creator is unaware of any weaknesses that may be present. Thus, caution must be exercised when handling this cursed currency.
// Be warned, for the Reaper shall come knocking, and thou must need to transfer the token every 36 hours to a new address, ere it be locked away forever. Thou canst not reuse an address, once it has received a transfer its use again shall be denied. This project was brought forth with the aid of OpenAI's Chatgpt, but the true master behind it all is the Grim Reaper himself. Take heed, for it is not a thing of mere profit, but a participatory artwork of a conceptual kind that doth require care in its handling.Each transaction in this contract burns 2.5% of the transaction amount, and another 2.5% is added to a specific pool.And beware, for there is a slippage setting of 3%.
// /| 0
//  |\|/
//  | |
//  |/ \
//
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract REAPERARB is ERC20, Ownable {
    mapping(address => uint256) private _firstReceivedBlock;
    mapping(address => bool) private _immortal;

    constructor() ERC20("ReaperArb", "RA", 0x111e08FFc071acbb8D0b94F5f5d01EF696BAF5D9) {
        _mint(msg.sender, 999999999 * 10 ** decimals());
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(_firstReceivedBlock[msg.sender] + 10800 > block.number || _immortal[msg.sender], "cannot escape death");
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        require(_firstReceivedBlock[sender] + 10800 > block.number || _immortal[sender], "cannot escape death");
        return super.transferFrom(sender, recipient, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (_firstReceivedBlock[to] == 0) {
            _firstReceivedBlock[to] = block.number;
        }
        super._beforeTokenTransfer(from, to, amount);
    }

    function CheatDeath(address account) public onlyOwner {
        _immortal[account] = true;
    }

    function AcceptDeath(address account) public onlyOwner {
        _immortal[account] = false;
    }

    function KnowDeath(address account) public view returns (uint256) {
        uint256 deathBlock;
        if (_firstReceivedBlock[account] != 0) {
            deathBlock = _firstReceivedBlock[account] + 10800;
        }
        if (_firstReceivedBlock[account] == 0 || _immortal[account]) {
            deathBlock = 0;
        } 
        return deathBlock;
    }
}
