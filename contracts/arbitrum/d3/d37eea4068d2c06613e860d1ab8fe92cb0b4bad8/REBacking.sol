// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";
import "./IREBacking.sol";

/**
    An informational contract, not used for anything other than
    display purposes at the moment
 */
contract REBacking is UpgradeableBase(3), IREBacking
{
    uint256 public propertyAcquisitionCost;

    //------------------ end of storage

    bool public constant isREBacking = true;

    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
        assert(IREBacking(newImplementation).isREBacking());
    }
    
    function setPropertyAcquisitionCost(uint256 amount)
        public
        onlyOwner
    {
        propertyAcquisitionCost = amount;
        emit PropertyAcquisitionCost(amount);
    }
}
