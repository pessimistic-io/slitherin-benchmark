// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./Ownable.sol";
import "./IERC20.sol";

contract Trusteeship2 is Ownable {
    function Withdraw(address _contract) external onlyOwner {
        require(_contract != address(0), "contract is the zero address");
        IERC20 Token = IERC20(_contract);
        Token.transfer(msg.sender, Token.balanceOf(address(this)));
    }
}

