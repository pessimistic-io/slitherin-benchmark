//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ToadTraitConstants.sol";

import "./IToadzMinter.sol";
import "./IToadz.sol";
import "./IBadgez.sol";
import "./IItemz.sol";
import "./AdminableUpgradeable.sol";
import "./IRandomizer.sol";

abstract contract ToadzMinterState is Initializable, IToadzMinter, AdminableUpgradeable {

    event MintingToadzStarted(address indexed _owner, uint256 _batchSize, uint256 _requestId);
    event MintingToadzFinished(address indexed _owner, uint256 _batchSize, uint256 _requestId);

    IToadz public toadz;
    IRandomizer public randomizer;
    IBadgez public badgez;
    IItemz public itemz;

    mapping(address => bool) public addressToHasClaimed;
    mapping(address => EnumerableSetUpgradeable.UintSet) internal addressToRequestIds;
    mapping(uint256 => uint256) public requestIdToBatchSize;

    // Rarities and aliases are used for the Walker's Alias algorithm.
    mapping(string => uint8[]) public traitTypeToRarities;
    mapping(string => uint8[]) public traitTypeToAliases;

    bytes32 public merkleRoot;

    uint8 public maxBatchSize;

    uint256 public whitelistBadgeId;
    uint256 public regularAxeId;
    uint256 public goldenAxeId;

    // Out of 256
    uint256 public chanceGoldenAxePerToad;
    uint8 public axesPerToad;

    function __ToadzMinterState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        whitelistBadgeId = 1;

        maxBatchSize = 20;

        regularAxeId = 1;
        goldenAxeId = 2;

        chanceGoldenAxePerToad = 26;
        axesPerToad = 1;

        traitTypeToRarities[ToadTraitConstants.BACKGROUND] = [247, 239, 183, 165, 147, 15, 139, 7, 131, 255, 189, 189, 189, 189, 75, 113, 113, 0, 0];
        traitTypeToAliases[ToadTraitConstants.BACKGROUND] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 1, 1, 2, 3, 4, 5, 7];

        traitTypeToRarities[ToadTraitConstants.MUSHROOM] = [243, 203, 135, 159, 183, 207, 231, 255, 27, 27, 13, 13, 0, 0];
        traitTypeToAliases[ToadTraitConstants.MUSHROOM] = [1, 2, 3, 4, 5, 6, 7, 0, 0, 0, 1, 1, 2, 2];

        traitTypeToRarities[ToadTraitConstants.SKIN] = [250, 67, 125, 183, 91, 255, 149, 149, 14, 14, 14, 0, 0, 0, 0];
        traitTypeToAliases[ToadTraitConstants.SKIN] = [1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 1, 1, 2, 3, 4];

        traitTypeToRarities[ToadTraitConstants.CLOTHES] = [199, 153, 211, 165, 223, 177, 235, 189, 247, 153, 59, 221, 127, 33, 195, 101, 7, 131, 255, 151, 151, 151, 151, 151, 151, 151, 151, 151, 151, 151, 151, 151, 0, 0, 0, 0, 0, 0];
        traitTypeToAliases[ToadTraitConstants.CLOTHES] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 0, 0, 1, 1, 2, 3, 3, 4, 5, 5, 6, 7, 7, 8, 9, 10, 12, 13, 15, 16];

        traitTypeToRarities[ToadTraitConstants.MOUTH] = [161, 159, 97, 201, 139, 243, 151, 255, 149, 149, 149, 149, 89, 89, 59];
        traitTypeToAliases[ToadTraitConstants.MOUTH] = [1, 2, 3, 4, 5, 6, 7, 0, 0, 0, 0, 1, 2, 4, 6];

        traitTypeToRarities[ToadTraitConstants.EYES] = [217, 175, 133, 215, 173, 255, 241, 241, 241, 241, 241, 131, 131, 131, 131, 131, 131, 131, 131, 131, 131, 131];
        traitTypeToAliases[ToadTraitConstants.EYES] = [1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 4, 4, 5];

        traitTypeToRarities[ToadTraitConstants.ITEM] = [255, 54, 54, 54, 54, 54, 54, 54, 54, 54, 54];
        traitTypeToAliases[ToadTraitConstants.ITEM] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

        traitTypeToRarities[ToadTraitConstants.HEAD] = [223, 159, 159, 159, 63, 63, 159, 191, 223, 159, 159, 63, 159, 159, 159, 31, 159, 159, 159, 63, 95, 127, 159, 191, 223, 0, 31, 63, 95, 255, 0, 0];
        traitTypeToAliases[ToadTraitConstants.HEAD] = [6, 0, 0, 0, 0, 0, 7, 8, 15, 0, 0, 0, 0, 0, 0, 19, 0, 6, 15, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 0, 15, 25];

        traitTypeToRarities[ToadTraitConstants.ACCESSORY] = [255, 59, 11, 11, 11, 11];
        traitTypeToAliases[ToadTraitConstants.ACCESSORY] = [0, 0, 0, 0, 0, 0];
    }
}
