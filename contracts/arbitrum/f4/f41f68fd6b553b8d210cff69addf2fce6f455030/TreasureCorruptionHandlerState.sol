//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./ITreasureCorruptionHandler.sol";
import "./AdminableUpgradeable.sol";
import "./ITreasure.sol";
import "./ITreasureMetadataStore.sol";
import "./ICorruptionRemoval.sol";
import "./ICustomRemovalHandler.sol";
import "./IConsumable.sol";

abstract contract TreasureCorruptionHandlerState is Initializable, ICustomRemovalHandler, ITreasureCorruptionHandler, AdminableUpgradeable, ERC1155HolderUpgradeable {

    event TreasureStaked(address _user, uint256 _requestId, uint256[] treausureIds, uint256[] treasureAmounts);
    event TreasureUnstaked(address _user, uint256 _requestId, uint256[] brokenTreasureIds, uint256[] brokenTreasureAmounts);

    ICorruptionRemoval public corruptionRemoval;
    ITreasure public treasure;
    ITreasureMetadataStore public treasureMetadataStore;
    IConsumable public consumable;
    address public treasuryAddress;

    mapping(uint256 => TreasureRequestInfo) requestIdToInfo;

    function __TreasureCorruptionHandlerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();
    }
}

struct TreasureRequestInfo {
    uint256[] treasureIds;
    uint256[] treasureAmounts;
}
