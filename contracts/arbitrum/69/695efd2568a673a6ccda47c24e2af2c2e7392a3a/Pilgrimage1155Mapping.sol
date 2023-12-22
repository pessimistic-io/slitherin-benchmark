//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC1155ReceiverUpgradeable.sol";

import "./PilgrimageContracts.sol";

abstract contract Pilgrimage1155Mapping is Initializable, ERC1155ReceiverUpgradeable, PilgrimageContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __Pilgrimage1155Mapping_init() internal initializer {
        PilgrimageContracts.__PilgrimageContracts_init();
        ERC1155ReceiverUpgradeable.__ERC1155Receiver_init();
    }

    function setPilgrimageLength(uint256 _pilgrimageLength) external onlyAdminOrOwner {
        pilgrimageLength = _pilgrimageLength;
    }

    function setMetadataForIds(
        uint256[] calldata _ids,
        LegionRarity[] calldata _rarities,
        LegionClass[] calldata _classes,
        uint256[] calldata _constellationOdds,
        uint8[] calldata _constellationNumber)
    external
    onlyAdminOrOwner
    nonZeroLength(_ids)
    {
        require(_ids.length == _rarities.length
            && _rarities.length == _classes.length
            && _classes.length == _constellationOdds.length
            && _constellationOdds.length == _constellationNumber.length, "Bad lengths");

        for(uint256 i = 0; i < _ids.length; i++) {
            if(!legion1155Ids.contains(_ids[i])) {
                legion1155Ids.add(_ids[i]);
            }

            legionIdToRarity[_ids[i]] = _rarities[i];
            legionIdToClass[_ids[i]] = _classes[i];
            legionIdToChanceConstellationUnlocked[_ids[i]] = _constellationOdds[i];
            legionIdToNumberConstellationUnlocked[_ids[i]] = _constellationNumber[i];
        }
    }

    function removeMetadataForIds(uint256[] calldata _ids) external override onlyAdminOrOwner {
        for(uint256 i = 0; i < _ids.length; i++) {
            if(legion1155Ids.contains(_ids[i])) {
                legion1155Ids.remove(_ids[i]);
            }

            delete legionIdToRarity[_ids[i]];
            delete legionIdToClass[_ids[i]];
            delete legionIdToChanceConstellationUnlocked[_ids[i]];
            delete legionIdToNumberConstellationUnlocked[_ids[i]];
        }
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
