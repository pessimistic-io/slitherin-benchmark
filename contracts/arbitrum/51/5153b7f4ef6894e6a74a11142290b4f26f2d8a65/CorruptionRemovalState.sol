//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./ICorruptionRemoval.sol";
import "./AdminableUpgradeable.sol";
import "./ICorruption.sol";
import "./IConsumable.sol";
import "./IBalancerCrystal.sol";

abstract contract CorruptionRemovalState is Initializable, ICorruptionRemoval, AdminableUpgradeable, ERC1155HolderUpgradeable {

    event CorruptionRemovalRecipeCreated(
        uint256 _recipeId,
        uint256 _corruptionRemoved,
        RecipeItemEvent[] _items,
        MalevolentPrismStepEvent[] _malevolentPrismSteps
    );
    event CorruptionRemovalRecipeAdded(
        address _buildingAddress,
        uint256 _recipeId
    );
    event CorruptionRemovalRecipeRemoved(
        address _buildingAddress,
        uint256 _recipeId
    );

    event CorruptionRemovalStarted(
        address _user,
        address _buildingAddress,
        uint256 _recipeId,
        uint256 _requestId
    );
    event CorruptionRemovalEnded(
        address _user,
        address _buildingAddress,
        uint256 _requestId,
        uint256 _recipeId,
        uint256 _corruptionRemoved,
        uint256 _prismMinted,
        bool[] _effectHit
    );

    address constant DEAD_ADDRESS = address(0xdead);
    uint256 constant MALEVOLENT_PRISM_ID = 15;

    IRandomizer public randomizer;
    ICorruption public corruption;
    IConsumable public consumable;
    address public treasuryAddress;
    IBalancerCrystal public balancerCrystal;

    uint256 public recipeIdCur;

    mapping(address => BuildingInfo) internal buildingAddressToInfo;
    mapping(uint256 => RecipeInfo) internal recipeIdToInfo;
    mapping(address => UserInfo) internal userToInfo;

    function __CorruptionRemovalState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        recipeIdCur = 1;
    }
}

struct RecipeItemEvent {
    address itemAddress;
    ItemType itemType;
    ItemEffect itemEffect;
    uint32 effectChance;
    uint64 itemId;
    uint128 amount;
    address customHandler;
    bytes customRequirementData;
}

struct MalevolentPrismStepEvent {
    uint128 maxCorruptionAmount;
    uint32 chanceOfDropping;
    uint32 amount;
}

struct BuildingInfo {
    // Slot 1
    // All the valid recipes for this building
    EnumerableSetUpgradeable.UintSet recipeIds;
}

struct RecipeInfo {
    // Slot 1
    // The amount of corruption removed when the recipe is used
    uint256 corruptionRemoved;

    // Slot 2
    // The items needed for this recipe
    RecipeItem[] items;

    // Slot 3
    MalevolentPrismStep[] prismSteps;
}

// Do not add extra storage to this struct, besides that which was reserved.
struct RecipeItem {
    // Slot 1 (208/256)
    // The address of the item
    address itemAddress;
    ItemType itemType;
    ItemEffect itemEffect;
    // The chance of itemEffect occuring. If Custom, this is not used.
    uint32 effectChance;
    uint48 emptySpace1;

    // Slot 2 (192/256)
    // The amount of the item needed.
    uint64 itemId;
    uint128 amount;
    uint128 emptySpace2;

    // Slot 3 (160/256)
    address customHandler;
    uint96 emptySpace3;

    // Slot 4
    // Any data that will be transmitted to the custom handler as a requirement for this
    // item.
    bytes customRequirementData;

    // Slot 5 (0/256)
    uint256 emptySpace4;

    // Slot 6 (0/256)
    uint256 emptySpace5;
}

struct UserInfo {
    mapping(uint256 => CorruptionRemovalInstance) requestIdToRemoval;
}

struct CorruptionRemovalInstance {
    // Slot 1 (240/256)
    // Indicates that this user and request id combo is valid and is in progress.
    bool hasStarted;
    // Indicates if the instance has finished already.
    bool hasFinished;
    // The recipe id being used.
    uint64 recipeId;
    address buildingAddress;
}

struct MalevolentPrismStep {
    // Slot 1 (192/256)
    uint128 maxCorruptionAmount;
    uint32 chanceOfDropping;
    uint32 amount;
    uint64 emptySpace1;
}

enum ItemType {
    ERC20,
    ERC1155
}

enum ItemEffect {
    BURN,
    MOVE_TO_TREASURY,
    CUSTOM
}
