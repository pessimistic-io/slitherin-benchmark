//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TLDContracts.sol";

abstract contract TLDMintable is Initializable, TLDContracts {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function __TLDMintable_init() internal initializer {
        TLDContracts.__TLDContracts_init();
    }

    function mint(address _to, uint256 _amount)
        external
        whenNotPaused
        onlyMinter
    {
        require(
            maxSupply >= totalSupply() + _amount,
            "TLD: Max supply reached"
        );
        for (uint256 i = 0; i < _amount; ++i) {
            uint256 _tokenId = tokenIdCounter.current();
            tokenIdCounter.increment();
            _safeMint(_to, _tokenId);
        }
    }

    function addMinter(address _minter) external onlyAdminOrOwner {
        minters.add(_minter);
    }

    function removeMinter(address _minter) external onlyAdminOrOwner {
        minters.remove(_minter);
    }

    function isMinter(address _minter) external view returns (bool) {
        return minters.contains(_minter);
    }

    modifier onlyMinter() {
        require(minters.contains(msg.sender), "Not a minter");
        _;
    }

    function totalSupply() public view returns (uint256) {
        return tokenIdCounter.current() - amountBurned;
    }
}

