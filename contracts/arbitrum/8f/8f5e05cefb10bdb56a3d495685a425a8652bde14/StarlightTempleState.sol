//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./IStarlightTemple.sol";
import "./AdminableUpgradeable.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasure.sol";
import "./ILegion.sol";
import "./ITreasury.sol";
import "./IConsumable.sol";

abstract contract StarlightTempleState is Initializable, IStarlightTemple, ERC1155HolderUpgradeable, AdminableUpgradeable {

    IRandomizer public randomizer;
    ILegionMetadataStore public legionMetadataStore;
    IConsumable public consumable;
    ILegion public legion;
    ITreasury public treasury;

    uint8 public maxConstellationRank;
    uint256[] public currentRankToNeededStarlight;
    uint256 public starlightConsumableId;

    uint256[] public currentRankToPrismAmount;
    uint256[] public currentRankToPrismId;

    bool public isIncreasingRankPaused;

    function __StarlightTempleState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        maxConstellationRank = 7;

        currentRankToNeededStarlight.push(25);
        currentRankToNeededStarlight.push(38);
        currentRankToNeededStarlight.push(56);
        currentRankToNeededStarlight.push(84);
        currentRankToNeededStarlight.push(127);
        currentRankToNeededStarlight.push(190);
        currentRankToNeededStarlight.push(285);

        currentRankToPrismAmount.push(0);
        currentRankToPrismAmount.push(1);
        currentRankToPrismAmount.push(2);
        currentRankToPrismAmount.push(3);
        currentRankToPrismAmount.push(1);
        currentRankToPrismAmount.push(2);
        currentRankToPrismAmount.push(1);

        currentRankToPrismId.push(0);
        currentRankToPrismId.push(1);
        currentRankToPrismId.push(1);
        currentRankToPrismId.push(1);
        currentRankToPrismId.push(2);
        currentRankToPrismId.push(2);
        currentRankToPrismId.push(3);
    }
}
