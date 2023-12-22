// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

interface ReadONREADVoucher {
    function safeMint(
        address to,
        uint256 tokenId,
        uint256 amount
    ) external;
}

contract AirdropReadVoucher is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    function dropMint(
        address tokenAddr,
        address[] memory _recipients,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) public onlyOwner returns (bool) {
        require(_recipients.length == _amounts.length, "ERC:length mismatch");
        for (uint16 i = 0; i < _recipients.length; i++) {
            //require(_recipients[i] != address(0));
            ReadONREADVoucher(tokenAddr).safeMint(_recipients[i],_tokenIds[i], _amounts[i]);
        }

        return true;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}

