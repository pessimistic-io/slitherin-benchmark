// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

contract KwentaStorage {
    //address public owner;
    address public kwentaFactory;
    address public SUSD;

    function getKwentaFactory() public view returns (address) {
        return kwentaFactory;
    }

    function getSUSD() public view returns (address) {
        return SUSD;
    }
}

