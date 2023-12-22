//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UserAccessible_Constants.sol";
import "./TokenAccess_Types.sol";

import "./IUserAccess.sol";
import "./ITokenAccess.sol";

import "./UserAccessible.sol";
import "./SkillManager.sol";
import "./ItemManager.sol";
import "./RandomManager.sol";
import "./EOA.sol";
import "./Probable.sol";

contract Kitchen is 
  UserAccessible, 
  EOA,
  ItemManager,
  RandomManager,
  SkillManager,
  Probable
{

  mapping (uint => Recipe) public itemToRecipe; // itemId => Recipe
  mapping (uint => Result[]) public itemToResults; // itemId => Result[]

  mapping (uint => Activity) public playerToActivity; // playerId => Activity

  // statistics
  mapping (uint => mapping (uint => uint)) public playerToItemToCookCount;
  mapping (uint => uint) public itemToCookCount;

  event StartedCooking (uint playerId, uint itemId, uint timestamp);
  event FinishedCooking (uint playerId, uint itemId, uint rewardId, uint timestamp);

  constructor(
    address _items, 
    address _randomizer, 
    address _skills,
    address _userAccess
  )
    UserAccessible(_userAccess) 
    ItemManager(_items)
    RandomManager(_randomizer)
    SkillManager(_skills)
    {}

  function getRecipe (uint itemId) public view returns (Recipe memory) {
    return itemToRecipe[itemId];
  }

  function updateRecipeRequirement (uint itemId, uint expRequired) public onlyAdmin { itemToRecipe[itemId].expRequired = expRequired; }
  function updateRecipeDuration (uint itemId, uint newDuration) public onlyAdmin { itemToRecipe[itemId].duration = newDuration; }
  function setRecipeActive (uint itemId, bool newState) public onlyAdmin { itemToRecipe[itemId].active = newState; }
  function setResultsForItem (uint itemId, Result[] calldata newResults) public onlyAdmin { _setResultsForItem(itemId, newResults); }
  function resetActivity (uint playerId) public onlyAdmin { delete playerToActivity[playerId]; }

  function updateRecipe (
    uint itemId, 
    bool active, 
    uint duration, 
    uint expRequired
  ) public onlyAdmin {
    itemToRecipe[itemId].active = active;
    itemToRecipe[itemId].duration = duration;
    itemToRecipe[itemId].expRequired = expRequired;
  }

  function setRecipeForItem (
    uint itemId, 
    Result[] calldata newResults, 
    bool active, 
    uint duration,
    uint expRequired
  ) 
    public 
    onlyAdmin 
  {
    _setResultsForItem(itemId, newResults);
    itemToRecipe[itemId].active = active;
    itemToRecipe[itemId].duration = duration;
    itemToRecipe[itemId].expRequired = expRequired;
  }

  function setRandomizer (address _randomizer) public onlyAdmin {
    _setRandomizer(_randomizer);
  }

  function cookFor (address from, uint playerId, uint itemId) 
    public
    adminOrRole(KITCHEN_ROLE)
  {
    _safeCookFor(from, playerId, itemId);
  }

  function claimFor (address to, uint playerId, uint boostFactor) 
    public
    adminOrRole(KITCHEN_ROLE)
  {
    _safeClaimFor(to, playerId, boostFactor);
  }

  function unsafeCookFor (address from, uint playerId, uint itemId) 
    public
    adminOrRole(KITCHEN_ROLE)
  {
    _cookFor(from, playerId, itemId);
  }

   function unsafeClaimFor (address to, uint playerId, uint boostFactor) 
    public
    adminOrRole(KITCHEN_ROLE)
  {
    _claimFor(to, playerId, boostFactor);
  }

  function _safeCookFor (address from, uint playerId, uint itemId) private {
    Recipe memory recipe = itemToRecipe[itemId];
    require(recipe.active, 'RECIPE_INACTIVE');
    require(skills.experienceOf(playerId, SKILL_COOKING) >= recipe.expRequired, 'NOT_ENOUGH_EXP');
    require(items.balanceOf(from, itemId) > 0, 'NO_ITEM');
    _cookFor(from, playerId, itemId);
  }

  function _cookFor (address from, uint playerId, uint itemId) private {
    Activity storage activity = playerToActivity[playerId];
    items.burn(from, itemId, 1);
    activity.itemId = itemId;
    activity.started = block.timestamp;
    activity.randomId = randomizer.requestRandomNumber();

    emit StartedCooking(playerId, itemId, activity.started);
  }

  function _safeClaimFor (address to, uint playerId, uint boostFactor) private {
    Activity storage activity = playerToActivity[playerId];
    Recipe memory recipe = itemToRecipe[activity.itemId];
    require(block.timestamp - activity.started >= recipe.duration, 'NOT_COOKED');
    _claimFor(to, playerId, boostFactor);
  }

  function _claimFor (address to, uint playerId, uint boostFactor) private {
    Activity storage activity = playerToActivity[playerId];
    Recipe memory recipe = itemToRecipe[activity.itemId];
    require(block.timestamp - activity.started >= recipe.duration, 'NOT_COOKED');
    require(randomizer.isRandomReady(activity.randomId), 'RANDOM_NOT_READY');

    uint randomSeed = uint(keccak256(abi.encode(
      randomizer.revealRandomNumber(activity.randomId),
      playerId
    )));
    Result memory result = _rewardForScore(
      randomSeed % baseChance, 
      itemToResults[activity.itemId], 
      baseChance, 
      boostFactor
    );

    items.mint(to, result.itemId, 1);
    skills.addExperience(playerId, SKILL_COOKING, result.experience);
    
    playerToItemToCookCount[playerId][result.itemId] += 1;
    itemToCookCount[result.itemId] += 1;

    emit FinishedCooking(playerId, activity.itemId, result.itemId, block.timestamp);

  }

  function _rewardForScore (
    uint _score, 
    Result[] memory results, 
    uint probability, 
    uint boostFactor
  ) 
    private 
    pure
    returns (Result memory) 
  {
    assert(boostFactor >= probability);
    int score = int(_score);
    int offset = int(boostFactor - probability);
    assert(offset >= 0);
    int bottom = 0 - offset; // offset results to the left.
    for (uint i = 0; i < results.length; i++) {
      int p = int((results[i].probability * boostFactor) / probability);
      if (score >= bottom && score < bottom + p) return results[i]; 
      bottom += p;
    }
    assert(false);
  }

  function _sumOfProbability (Result[] memory results) private pure returns (uint) {
    uint sum = 0;
    for (uint i = 0; i < results.length; i++) {
      sum += results[i].probability;
    }
    return sum;
  }

  function _setResultsForItem (
    uint itemId, 
    Result[] memory newResults
  ) 
    private
  {
    require(_sumOfProbability(newResults) == baseChance, 'INVALID_PROBABILITY');
    delete itemToResults[itemId];
    for (uint i = 0; i < newResults.length; i++) {
      itemToResults[itemId].push(newResults[i]);
    }
  }

  function __testRecipeLength (uint itemId) public view returns (uint) {
    return itemToResults[itemId].length;
  }

  function __testRewardForScore (uint score, Result[] memory results, uint probability, uint boostFactor) 
    public
    pure
    returns (Result memory) 
  {
    return _rewardForScore(score, results, probability, boostFactor);
  }

}
