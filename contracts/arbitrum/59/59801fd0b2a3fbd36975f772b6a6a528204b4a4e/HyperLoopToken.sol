// SPDX-License-Identifier: MIT

/***
 *      ______             _______   __                                             
 *     /      \           |       \ |  \                                            
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______  
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \ 
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *                                                                                  
 *                                                                                  
 *                                                                                  
 */
 
pragma solidity 0.6.12;

import "./ERC20.sol";
import "./Ownable.sol";

/**
 * @dev Hyper Loop Tokens or "loopTokens" are layer-2 tokens that represent a deposit in the L1Loop
 * contract. Each Hyper Loop Token is a regular ERC20 that can be minted and burned by the L2Loop
 * that owns it.
 */

interface IBlacklistable{
    function isBlacklisted(address _account) external view returns (bool);
} 
    
contract HyperLoopToken is ERC20, Ownable {

    IBlacklistable public immutable blacklist;

    //  ToDo -> Set IBlacklistable

    constructor (
        string memory name,
        string memory symbol,
        uint8 decimals,
        IBlacklistable _blacklist
    )
        public
        ERC20(name, symbol)
    {
        blacklist = _blacklist;
        _setupDecimals(decimals);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return blacklist.isBlacklisted(account);
    }

    /**
     * @dev Mint new loopToken for the account
     * @param account The account being minted for
     * @param amount The amount being minted
     */
    function mint(address account, uint256 amount) external onlyOwner {
        require(!isBlacklisted(account), "This address is blacklisted");
        _mint(account, amount);
    }

    /**
     * @dev Burn loopToken from the account
     * @param account The account being burned from
     * @param amount The amount being burned
     */
    function burn(address account, uint256 amount) external onlyOwner {
        require(!isBlacklisted(account), "This address is blacklisted");
        _burn(account, amount);
    }
}
