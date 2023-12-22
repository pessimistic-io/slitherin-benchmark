// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";


contract Arweave is Ownable, ReentrancyGuard {

    address payable ArweaveFeeAddress;

    constructor(address arweaveAddress) {
        ArweaveFeeAddress = payable (arweaveAddress);
    }
    

    function payUploadFee(uint256 _amount) external payable nonReentrant {

        require(msg.value >= _amount, "Insufficient message value");
        uint256 contractBalance = address(this).balance;

        if(contractBalance > 0) {
            ArweaveFeeAddress.transfer(contractBalance);
        }
    }


    function updateUploadAddress(address _newFeeAddress) external onlyOwner {

        ArweaveFeeAddress = payable(_newFeeAddress);
    }

}

