//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzContracts.sol";

abstract contract ToadzMintable is Initializable, ToadzContracts {

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function __ToadzMintable_init() internal initializer {
        ToadzContracts.__ToadzContracts_init();
    }

    function mint(address _to, ToadTraits calldata _traits) external whenNotPaused onlyMinter {
        require(maxSupply > totalSupply(), "Toadz: Max supply reached");

        uint256 _tokenId = tokenIdCounter.current();
        tokenIdCounter.increment();

        _safeMint(_to, _tokenId);

        toadzMetadata.setMetadataForToad(_tokenId, _traits);
    }

    function addMinter(address _minter) external onlyAdminOrOwner {
        minters.add(_minter);
    }

    function removeMinter(address _minter) external onlyAdminOrOwner {
        minters.remove(_minter);
    }

    function isMinter(address _minter) external view returns(bool) {
        return minters.contains(_minter);
    }

    modifier onlyMinter() {
        require(minters.contains(msg.sender), "Not a minter");

        _;
    }

    function totalSupply() public view returns(uint256) {
        return tokenIdCounter.current() - 1 - amountBurned;
    }
}
