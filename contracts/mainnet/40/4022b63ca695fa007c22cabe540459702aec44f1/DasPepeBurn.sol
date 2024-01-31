//SPDX-License-Identifier: MIT
//IN BILLIONAIRE WE TRUST
import "./Ownable.sol";
import "./Address.sol";

pragma solidity ^0.8.7;

contract DasPepeBurn is Ownable {

    function bless() external payable {

        require(msg.value >= .01 ether);


    }

    function claim() external onlyOwner {

        uint256 balance = address(this).balance;

        Address.sendValue(payable(owner()), balance);

    }

}
