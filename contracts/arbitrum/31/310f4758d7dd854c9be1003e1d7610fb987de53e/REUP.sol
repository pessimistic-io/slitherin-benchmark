// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./BridgeRERC20.sol";
import "./UpgradeableBase.sol";
import "./IREUP.sol";

/**
    The mysterious REUP token :)
 */
contract REUP is BridgeRERC20, UpgradeableBase(4), IREUP
{
    bool public constant isREUP = true;
    string public constant url = "https://reup.cash";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(string memory _name, string memory _symbol)
        RERC20(_name, _symbol, 18)
    {    
    }

    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
        assert(IREUP(newImplementation).isREUP());
        BridgeRERC20.checkUpgrade(newImplementation);
    }

    function getMinterOwner() internal override view returns (address) { return owner(); }

    function mint(address to, uint256 amount)
        public
        onlyMinter
    {
        mintCore(to, amount);
    }
}
