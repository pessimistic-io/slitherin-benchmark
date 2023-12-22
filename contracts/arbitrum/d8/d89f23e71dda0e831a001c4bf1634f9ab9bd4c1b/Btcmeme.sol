// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./ERC20Burnable.sol";

contract BTCMEME is ERC20Burnable, Ownable {
    mapping(address => bool) public blackList;
    mapping(address => bool) public receiverList;

    uint24 public numberRemaining = 2000;

    event ReceiveAward(address account, uint256 award, uint256 timestamp);
    event AddToBlackList(address account, uint256 timestamp);
    event RemoveFromBlackList(address account, uint256 timestamp);

    constructor() ERC20("BTCMEME", "BTCMEME") {
        super._mint(msg.sender, 210_000_000_000e18);
        transfer(address(this), 10_500_000_000e18);
        approveFromThis(msg.sender,10_500_000_000e18);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approveFromThis(address spender, uint256 amount)
        internal onlyOwner
        returns (bool)
    {
        _approve(address(this), spender, amount);
        return true;
    }

    /**
     * Add wallet address to the black list
     *
     * Returns the result of addToBlackList processing, true for success.
     *
     * Requirements:
     *
     * - `walletAddress` cannot be the zero address.
     */
    function addToBlackList(address walletAddress)
        public
        onlyOwner
        returns (bool)
    {
        require(walletAddress != address(0), "Invalid wallet address");
        require(!blackList[walletAddress], "Already add to black list");
        blackList[walletAddress] = true;
        emit AddToBlackList(walletAddress, block.timestamp);
        return true;
    }

    /**
     * Send rewards to users
     *
     * Requirements:
     *
     * - `accountAddress` cannot be the zero address.
     */
    function receiveAward(address accountAddress) public onlyOwner {
        require(accountAddress != address(0), "Invalid account address");
        require(!receiverList[accountAddress], "Already received");
        require(!blackList[accountAddress], "You've been blacklisted");
        numberRemaining = numberRemaining - 1;
        require(numberRemaining >= 0, "The award is over");
        require(
            balanceOf(address(this)) >= 5_250_000e18,
            "Insufficient balance"
        );
        receiverList[accountAddress] = true;
        transferFrom(address(this), accountAddress, 5_250_000e18);
        emit ReceiveAward(accountAddress, 5_250_000e18, block.timestamp);
    }

    /**
     * Remove wallet address from the black list
     *
     * Returns the result of removeFromBlackList processing, true for success.
     *
     * Requirements:
     *
     * - `walletAddress` cannot be the zero address.
     */
    function removeFromBlackList(address walletAddress)
        public
        onlyOwner
        returns (bool)
    {
        require(walletAddress != address(0), "Invalid wallet address");
        require(blackList[walletAddress], "Not in black list");
        blackList[walletAddress] = false;
        emit RemoveFromBlackList(walletAddress, block.timestamp);
        return true;
    }
}

