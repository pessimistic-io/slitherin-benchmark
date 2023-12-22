pragma solidity ^0.6.12;

contract TestProxyActionsWithdrawFunds {
    function withdraw(uint256 amount) public {
        msg.sender.transfer(amount);
    }

    function withdrawTo(address dst, uint256 amount) public {
        payable(address(dst)).transfer(amount);
    }
}