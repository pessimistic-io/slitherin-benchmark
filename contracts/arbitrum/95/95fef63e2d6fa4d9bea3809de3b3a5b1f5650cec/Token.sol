/*

###########################################
## Token generated with ❤️ on 20lab.app ##
##########################################

*/

// SPDX-License-Identifier: No License

pragma solidity 0.8.7;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./Pausable.sol";

contract ARB_WOLf_AI is ERC20, ERC20Burnable, Ownable, Pausable {
    
    mapping (address => bool) public blacklisted;
 
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
 
    constructor()
        ERC20(unicode"ARB WOLf AI", unicode"AIWOLF") 
    {
        address supplyRecipient = 0x4396170db4d1a61fb0500b3b18C671ED801FE9bc;
        
        _mint(supplyRecipient, 9000000000000000 * (10 ** decimals()));
        _transferOwnership(0x4396170db4d1a61fb0500b3b18C671ED801FE9bc);
    }

    receive() external payable {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function blacklist(address account, bool isBlacklisted) external onlyOwner {
        blacklisted[account] = isBlacklisted;

        emit BlacklistUpdated(account, isBlacklisted);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        require(!blacklisted[from] && !blacklisted[to], "Blacklist: Sender or recipient is blacklisted");

        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        super._afterTokenTransfer(from, to, amount);
    }
}

