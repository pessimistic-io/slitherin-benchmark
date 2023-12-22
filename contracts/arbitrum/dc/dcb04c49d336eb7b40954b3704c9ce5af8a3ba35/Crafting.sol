pragma solidity ^0.8.13;

import "./Ownable.sol";

interface IArcane {
    function ownerOf(uint256 tokenId) external returns (address);
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

    mapping(uint256 => Recipe) public recipes;
    mapping(uint256 => mapping(uint256 => uint256)) public cooldowns;

    modifier isOwner(uint256 _wizId) {
        require(ARCANE.ownerOf(_wizId) == msg.sender,"Not owner");
        _;
    }

    function executeRecipe(
        uint256 _wizId,
        uint256 _recipeId
    ) external isOwner(_wizId) {
        Recipe memory recipe = recipes[_recipeId];
        require(recipe.inputAmounts.length > 0, "Empty");
        require(
            PROFESSIONS.checkSpec(_wizId, recipe.structure),
            "Cannot execute this recipe"
        );
        require(
            block.timestamp > cooldowns[_wizId][_recipeId] + recipe.cooldown,
            "On cooldown"
        );
        ITEMS.destroy(msg.sender, recipe.inputIds, recipe.inputAmounts);
        ITEMS.mintItems(msg.sender, recipe.outputIds, recipe.outputAmounts);
        cooldowns[_wizId][_recipeId] = block.timestamp;
        PROFESSIONS.earnXP(_wizId, recipe.xp);
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

    function getTimer(
        uint256 _wizId,
        uint256 _recipeId
    ) external view returns (uint256 timestamp) {
        return cooldowns[_wizId][_recipeId];
    }

    function setData(address _arcane, address _professions, address _items) external onlyOwner{
        ARCANE = IArcane(_arcane);
        PROFESSIONS = IProfessions(_professions);
        ITEMS = IItems(_items);
    }
}

