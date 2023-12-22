//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./console.sol";
import "./Ownable.sol";

contract PaymentProxy is Ownable {
    event Paid(
        address indexed _from,
        string indexed _collectionID,
        uint256 _value
    );

    address payable public wallet;
    // map of projectid and fee paid
    mapping(string => uint256) public feePaid;

    constructor(address payable _wallet) {
        wallet = _wallet;
    }

    function updateWallet(address payable _newWallet) public onlyOwner {
        wallet = _newWallet;
    }

    function payForStorage(string memory _collectionID) public payable {
        feePaid[_collectionID] = feePaid[_collectionID] + msg.value;
        wallet.transfer(address(this).balance);
        emit Paid(msg.sender, _collectionID, msg.value);
    }
}

