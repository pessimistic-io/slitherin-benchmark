// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract Deposit is Ownable {
    address public centralizeWallet;

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    function setCentralizeWallet(address _centralizeWallet) public onlyOwner {
        centralizeWallet = _centralizeWallet;
    }

    function sweepToken(address _tokenContract) public onlyOwner {
        IERC20 tokenContract = IERC20(_tokenContract);
        uint256 amount = tokenContract.balanceOf(address(this));

        require(amount > 0, "No token to sweep");

        tokenContract.transfer(centralizeWallet, amount);
    }

    function sweepNativeToken() public payable onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0.1 ether, "Balance should more than 0.1");
        uint availableSend = SafeMath.sub(balance, 0.1 * 10 ** 18);
        (bool sent, ) = centralizeWallet.call{value: availableSend}("");
        require(sent, "Failed to send Ether");
    }
}

