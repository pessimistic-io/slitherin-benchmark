//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";
import "./Base64Upgradeable.sol";
import "./IDonkeBoardMetadata.sol";
import "./DonkeBoardMetadataState.sol";

contract DonkeBoardMetadata is
    Initializable,
    DonkeBoardMetadataState,
    IDonkeBoardMetadata
{
    using StringsUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function initialize() external initializer {
        DonkeBoardMetadataState.__DonkeBoardMetadataState_init();
    }

    function setBaseURI(
        string calldata _baseURI
    ) external override onlyAdminOrOwner {
        baseURI = _baseURI;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, _tokenId.toString(), ".json"));
    }
}

