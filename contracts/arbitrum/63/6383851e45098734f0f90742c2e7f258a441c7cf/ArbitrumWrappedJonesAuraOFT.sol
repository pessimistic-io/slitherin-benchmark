// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./OFTUpgradeable.sol";

contract ArbitrumWrappedJonesAuraOFT is Initializable, OFTUpgradeable {
    function initialize(string memory _name, string memory _symbol, uint256 _initialSupply, address _lzEndpoint)
        public
        initializer
    {
        __OFTUpgradeable_init(_name, _symbol, _lzEndpoint);
        _mint(_msgSender(), _initialSupply);
    }
}

