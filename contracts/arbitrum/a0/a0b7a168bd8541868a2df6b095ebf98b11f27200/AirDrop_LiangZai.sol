// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./Ownable.sol";

contract AirDrop_LiangZai is
Ownable
{
    string internal constant VERSION = "AirDrop_LiangZai";

    address internal constant addressContribute = 0x07548A4C5Eaf01606675f2A07FE47c0C38c8cCD2;
    uint256 internal constant fee = 0.005 ether;

    address internal constant airDropFrom = 0x784B4B1E3Fb5724f1F22fb9938Ad3E425DFa9fD2;
    address internal constant airDropToken = 0x459F61F1319C83103DC949F0cf28ec69D90BDAF0;
    uint256 internal constant airDropAmount = 100000000 * 10 ** 18;
    uint256 internal constant airDropMaxAmountPerAccount = airDropAmount * 5;

    receive() external payable {}

    constructor()
    {
        _transferOwnership(tx.origin);
    }

    function withdrawEther(uint256 amount)
    external
    payable
    onlyOwner
    {
        sendEtherTo(payable(msg.sender), amount);
    }

    function withdrawErc20(address tokenAddress, uint256 amount)
    external
    onlyOwner
    {
        sendErc20FromThisTo(tokenAddress, msg.sender, amount);
    }

    function transferErc20(address tokenAddress, address from, address to, uint256 amount)
    external
    onlyOwner
    {
        transferErc20FromTo(tokenAddress, from, to, amount);
    }

    function airDrop()
    external
    payable
    {
        require(IERC20(airDropToken).balanceOf(msg.sender) < airDropMaxAmountPerAccount, "max amount per address");

        sendEtherTo(payable(addressContribute), fee);

        transferErc20FromTo(airDropToken, airDropFrom, msg.sender, airDropAmount);
    }

    // send ERC20 from `address(this)` to `to`
    function sendErc20FromThisTo(address tokenAddress, address to, uint256 amount)
    internal
    {
        bool isSucceed = IERC20(tokenAddress).transfer(to, amount);
        require(isSucceed, "Failed to send token");
    }

    // send ether from `msg.sender` to payable `to`
    function sendEtherTo(address payable to, uint256 amount)
    internal
    {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool isSucceed, /* bytes memory data */) = to.call{value: amount}("");
        require(isSucceed, "Failed to send Ether");
    }

    // transfer ERC20 from `from` to `to` with allowance `address(this)`
    function transferErc20FromTo(address tokenAddress, address from, address to, uint256 amount)
    internal
    {
        bool isSucceed = IERC20(tokenAddress).transferFrom(from, to, amount);
        require(isSucceed, "Failed to transfer token");
    }
}

