// contracts/behaviors/TaxableToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./console.sol";

contract BehaviorSwapableToken is Ownable {
    mapping(address => bool) internal tradingContractsAddresses;

    constructor() {}

    function setTradingContractAddress(address _address, bool _isTradingContract) public onlyOwner {
        tradingContractsAddresses[_address] = _isTradingContract;
    }
}

