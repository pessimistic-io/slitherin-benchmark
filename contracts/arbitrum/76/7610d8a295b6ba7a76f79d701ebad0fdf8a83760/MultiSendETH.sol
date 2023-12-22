// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";


contract Sender is Ownable {
    constructor () {
    }
    receive() external payable {}

    function ETHSender(address[] calldata _account, uint256[] calldata _quantity) external payable onlyOwner {
        require(address(this).balance != 0 && _quantity.length != 0 && _account.length != 0);
        require(_quantity.length == _account.length);

        for (uint256 i = 0; i < _account.length; ) {
            payable(_account[i]).transfer(_quantity[i]);
            unchecked {
                i++;
            }
        }
        if (address(this).balance != 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }
}

