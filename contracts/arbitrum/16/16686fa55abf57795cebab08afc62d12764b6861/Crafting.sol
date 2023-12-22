pragma solidity ^0.8.13;

import "./Ownable.sol";

struct State {
    address quester;
    uint256 startTime;
    uint256 currX;
    uint256 currY;
    bool reward;
}

interface IArcane {
    function ownerOf(uint256 tokenId) external returns (address);
}

interface IAdventure {
    function states(uint256 tokenId) external returns (State memory);
}

interface IProfessions {
    function checkSpec(
        uint256 _wizId,
        uint256 _specStructureId
    ) external returns (bool);

    function earnXP(uint256 _wizId, uint256 _points) external;
}

interface IItems {
    function mintItems(
        address _to,
        uint256[] memory _itemIds,
        uint256[] memory _amounts
    ) external;

    function destroy(
        address _from,
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) external;

    function balanceOf(address account, uint256 id) external returns (uint256);
}

contract Crafting is Ownable {
    struct Recipe {
        uint16 id;
        uint256[] inputIds;
        uint256[] inputAmounts;
        uint256[] outputIds;
        uint256[] outputAmounts;
        uint16 cooldown;
        uint16 structure;
        uint16 xp;
    }

    IArcane public ARCANE;
    IProfessions public PROFESSIONS;
    IItems public ITEMS;
    IAdventure public ADVENTURE;

    mapping(uint256 => Recipe) public recipes;
    mapping(uint256 => mapping(uint256 => uint256)) public cooldowns;

    modifier isOwner(uint256 _wizId) {
        require(
            ARCANE.ownerOf(_wizId) == msg.sender ||
                ADVENTURE.states(_wizId).quester == msg.sender,
            "Not owner"
        );
        _;
    }

    function executeRecipe(
        uint256 _wizId,
        uint256 _recipeId
    ) external isOwner(_wizId) {
        Recipe memory recipe = recipes[_recipeId];
        require(recipe.inputAmounts.length > 0, "Empty");
        if (recipe.structure < 1640) {
            require(
                PROFESSIONS.checkSpec(_wizId, recipe.structure),
                "Cannot execute this recipe"
            );
            PROFESSIONS.earnXP(_wizId, recipe.xp);
        } else {
            require(
                ITEMS.balanceOf(msg.sender, recipe.structure) > 0,
                "Cannot execute this recipe"
            );
        }
        require(
            block.timestamp > cooldowns[_wizId][_recipeId] + recipe.cooldown,
            "On cooldown"
        );
        ITEMS.destroy(msg.sender, recipe.inputIds, recipe.inputAmounts);
        ITEMS.mintItems(msg.sender, recipe.outputIds, recipe.outputAmounts);
        cooldowns[_wizId][_recipeId] = block.timestamp;
    }

    function createRecipe(
        uint256 _recipeId,
        uint256[] memory _requiredIds,
        uint256[] memory _requiredAmounts,
        uint256[] memory _rewardIds,
        uint256[] memory _rewardAmounts,
        uint16 _cooldown,
        uint16 _structure,
        uint16 _xp
    ) external onlyOwner {
        recipes[_recipeId].id = uint16(_recipeId);
        recipes[_recipeId].inputIds = _requiredIds;
        recipes[_recipeId].inputAmounts = _requiredAmounts;
        recipes[_recipeId].outputIds = _rewardIds;
        recipes[_recipeId].outputAmounts = _rewardAmounts;
        recipes[_recipeId].cooldown = _cooldown;
        recipes[_recipeId].structure = _structure;
        recipes[_recipeId].xp = _xp;
    }

    function getRecipeInfos(
        uint256 _wizId,
        uint256 _recipeId
    )
        external
        view
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currCooldown = cooldowns[_wizId][_recipeId];
        uint256 recipeId = _recipeId;
        return (
            recipes[recipeId].inputIds,
            recipes[recipeId].inputAmounts,
            recipes[recipeId].outputIds,
            recipes[recipeId].outputAmounts,
            recipes[recipeId].cooldown,
            recipes[recipeId].structure,
            recipes[recipeId].xp,
            currCooldown
        );
    }

    function getTimer(
        uint256 _wizId,
        uint256 _recipeId
    ) external view returns (uint256 timestamp) {
        return cooldowns[_wizId][_recipeId];
    }

    function setData(
        address _arcane,
        address _professions,
        address _items,
        address _adventure
    ) external onlyOwner {
        ARCANE = IArcane(_arcane);
        ADVENTURE = IAdventure(_adventure);
        PROFESSIONS = IProfessions(_professions);
        ITEMS = IItems(_items);
    }
}

