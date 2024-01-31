// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED

// Unicrypt by SDDTech reserves all rights on this code. You may NOT copy these contracts.

pragma solidity 0.8.17;

import "./Storage.sol";
import "./BuyBackWallet.sol";
import "./LPWallet.sol";


import "./IBuyBackWallet.sol";
import "./ILPWallet.sol";

import "./Ownable.sol";

contract WalletsFacet is Storage, Ownable {


    function createBuyBackWallet(address _factory, address _token, uint256 _newThreshold) external returns (address) {
        BuyBackWallet newBuyBackWallet = new BuyBackWallet(_factory, _token,_newThreshold);
        emit CreatedBuyBackWallet(address(newBuyBackWallet));
        return address(newBuyBackWallet);
    }

    function createLPWallet(address _factory, address _token, uint256 _newThreshold) external returns (address) {
        LPWallet newLPWallet = new LPWallet(_factory, _token, _newThreshold);
        emit CreatedLPWallet(address(newLPWallet));
        return address(newLPWallet);
    }

    function updateBuyBackWalletThreshold(uint256 _newThreshold) public onlyOwner {
        IBuyBackWallet(buyBackWallet).updateThreshold(_newThreshold);
        emit UpdatedBuyBackWalletThreshold(_newThreshold);
    }

    function updateLPWalletThreshold(uint256 _newThreshold) public onlyOwner {
        ILPWallet(lpWallet).updateThreshold(_newThreshold);
        emit UpdatedLPWalletThreshold(_newThreshold);
    }

}
