//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";

import "./RandomlyAssignedUpgradeable.sol";
import "./DonkeBoardContracts.sol";

abstract contract DonkeBoardMintable is
    Initializable,
    DonkeBoardContracts,
    RandomlyAssignedUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function __DonkeBoardMintable_init() internal initializer {
        DonkeBoardContracts.__DonkeBoardContracts_init();
        RandomlyAssignedUpgradeable.initialize(maxSupply, 1);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external override whenNotPaused onlyMinter {
        require(
            maxSupply >= tokenCount() + _amount,
            "DonkeBoardMintable: Max supply reached"
        );
        for (uint256 i = 0; i < _amount; i++) {
            uint256 _tokenId = nextToken();
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
}

