// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ILegionMetadataStore.sol";
import "./IQualifier.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Qualifier contract qualifies the asset to be used for lending
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Qualifier is IQualifier {
    address public legionsMetadataAddress;

    constructor(address _legionsMetadataAddress) {
        legionsMetadataAddress = _legionsMetadataAddress;
    }

    function isAcceptableNFT(uint256 _tokenId) public view returns (bool) {
        (
            LegionGeneration generation,
            LegionRarity rarity
        ) = ILegionMetadataStore(legionsMetadataAddress).genAndRarityForLegion(
                _tokenId
            );

        return
            generation == LegionGeneration.GENESIS &&
            rarity == LegionRarity.COMMON;
    }
}

