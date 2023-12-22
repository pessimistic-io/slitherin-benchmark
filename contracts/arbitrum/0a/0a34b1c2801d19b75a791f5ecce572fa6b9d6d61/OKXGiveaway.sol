//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Utilities.sol";
import "./ITreasure.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasureMetadataStore.sol";

contract OKXGiveaway is Utilities {

    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;
    ITreasure public treasure;
    ITreasureMetadataStore public treasureMetadataStore;

    constructor(address _legionAddress, address _legionMetadataStoreAddress, address _treasureAddress, address _treasureMetadataStoreAddress) Utilities() {
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        treasure = ITreasure(_treasureAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
    }

    function mintLegions(address[] calldata _toAddresses) external onlyOwner {
        require(_toAddresses.length > 0, "OKXGiveaway: Bad array length");

        uint256 _randomNumber = _getPseudoRandom();

        for(uint256 i = 0; i < _toAddresses.length; i++) {
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            address _to = _toAddresses[i];

            uint256 _tokenId = legion.safeMint(_to);

            legionMetadataStore.setInitialMetadataForLegion(_to, _tokenId, LegionGeneration.AUXILIARY, LegionClass((_randomNumber % 5) + 1), LegionRarity.COMMON, 0);
        }
    }

    function mintTreasure(address[] calldata _toAddresses, uint8 _tier) external onlyOwner {
        require(_toAddresses.length > 0, "OKXGiveaway: Bad array length");
        require(_tier >= 3 && _tier <= 5, "OKXGiveaway: Bad treasure tier");

        uint256 _randomNumber = _getPseudoRandom();

        for(uint256 i = 0; i < _toAddresses.length; i++) {
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            address _to = _toAddresses[i];

            uint256 _treasureId = treasureMetadataStore.getRandomTreasureForTier(_tier, _randomNumber);

            treasure.mint(_to, _treasureId, 1);
        }
    }

    function _getPseudoRandom() private view returns(uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    _msgSender(),
                    block.timestamp,
                    block.difficulty
                )
            )
        );
    }
}
