pragma solidity ^0.6.6;

    /**
     * LUCKY SHIBA INU TOKEN
     * EVERY LUSHIBA TRANSACTION IS A LOTTERY. HODL AND GET LUCKY!
     * JOIN US & BECOME A PART OF CRYPTO'S NEWEST, LUCKIEST AND STRONGEST COMMUNITY
     *
     *
     * Visit Our Website:    lushibatoken.com
     * Follow Us on Twitter: twitter.com/LuckyShibaInu2
     * Join Our Discord:     discord.com/invite/KHn3CxvBUF
     * 
     *
     *
     *** LUSHIBA TOKEN FEATURES ***
     *  - Transaction Lottery
     *  - Anti-Whale Mechanics
     *  - Locked & Auto Liquidity
     *  - Deflationary LUSHIBA Token
     * ====
     */

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}
