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

    function __StarlightTempleState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        maxConstellationRank = 7;

        currentRankToNeededStarlight.push(50);
        currentRankToNeededStarlight.push(70);
        currentRankToNeededStarlight.push(90);
        currentRankToNeededStarlight.push(110);
        currentRankToNeededStarlight.push(140);
        currentRankToNeededStarlight.push(170);
        currentRankToNeededStarlight.push(200);
    }
}
