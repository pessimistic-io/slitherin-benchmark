// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";

import "./IRentShares.sol";

contract GameCoordinator is Ownable, ReentrancyGuard {

  using EnumerableSet for EnumerableSet.AddressSet;
    
    
  EnumerableSet.AddressSet private gameContracts;

	IRentShares public rentShares;

  uint256 public activeTimeLimit;

	struct GameInfo {
		address contractAddress; // game contract
		uint256 minLevel; // min level for this game to be unlocked
		uint256 maxLevel; // max level this game can give
	}

	struct PlayerInfo {
      uint256 rewards; //pending rewards that are not rent shares
      uint256 level; //the current level for this player
      uint256 totalClaimed; //lifetime mPCKT claimed from the game
      uint256 totalPaid; //lifetime rent and taxes paid
      uint256 totalRolls; //total rolls for this player
      uint256 lastRollTime; // timestamp of the last roll on any board
    }

    mapping(uint256 => GameInfo) public gameInfo;
    mapping(address => PlayerInfo) public playerInfo;
    mapping(uint256 => uint256) public levelSummary;

    uint256 public totalPlayers;

    constructor(
        IRentShares _rentSharesAddress, // rent share contract
        uint256 _activeTimeLimit 
    ) {

      	rentShares = _rentSharesAddress;
        activeTimeLimit = _activeTimeLimit;
      /*
      	for (uint i=0; i<_gameContracts.length; i++) {
      		setGame(i,_gameContracts[i],_minLevel[i],_maxLevel[i]);
      	} */
    }

    /** 
    * @notice Modifier to only allow updates by the VRFCoordinator contract
    */
    modifier onlyGame {
        require(gameContracts.contains(address(msg.sender)), 'Game Only');
        _;
    }

    function getRewards(address _address) external view returns(uint256) {
      return playerInfo[_address].rewards;
    }

    function getLevel(address _address) external view returns(uint256) {
    	return playerInfo[_address].level;
    }

    function getTotalRolls(address _address) external view returns(uint256) {
      return playerInfo[_address].totalRolls;
    }

    function getLastRollTime(address _address) external view returns(uint256) {
      return playerInfo[_address].lastRollTime;
    }

    function addTotalPlayers(uint256 _amount) public onlyGame {
      totalPlayers = totalPlayers + _amount;
    }    

    function addRewards(address _address, uint256 _amount) public onlyGame {
      playerInfo[_address].rewards = playerInfo[_address].rewards + _amount;
    }

    event LevelSet(address indexed user, uint256 level);
    function setLevel(address _address, uint256 _level) public onlyGame {

      // dont keep stats on level 0
      if(playerInfo[_address].level > 0){
        levelSummary[playerInfo[_address].level] = levelSummary[playerInfo[_address].level] - 1;
      }

      if(_level > 0){
        levelSummary[_level] = levelSummary[_level] + 1;
      }

      playerInfo[_address].level = _level;
      emit LevelSet(_address, _level);

    }

    function addTotalClaimed(address _address, uint256 _amount) public onlyGame {
      playerInfo[_address].totalClaimed = playerInfo[_address].totalClaimed + _amount;
    }

    function addTotalPaid(address _address, uint256 _amount) public onlyGame {
      playerInfo[_address].totalPaid = playerInfo[_address].totalPaid + _amount;
    }

    function addTotalRolls(address _address) public onlyGame {
      playerInfo[_address].totalRolls = playerInfo[_address].totalRolls + 1;
    }

    function setLastRollTime(address _address, uint256 _lastRollTime) public onlyGame {
      playerInfo[_address].lastRollTime = _lastRollTime;
      // update the nft staking last update with the roll time

    }

    event GameSet(uint256 gameId, address gameContract, uint256 minLevel, uint256 maxLevel);
    function setGame(uint256 _gameId, address _gameContract, uint256 _minLevel, uint256 _maxLevel) public onlyOwner {
    	
      if(!gameContracts.contains(address(_gameContract))){
        gameContracts.add(address(_gameContract));
      }
      gameInfo[_gameId].contractAddress = _gameContract;
    	gameInfo[_gameId].minLevel = _minLevel;
    	gameInfo[_gameId].maxLevel = _maxLevel;

      emit GameSet(_gameId,_gameContract,_minLevel,_maxLevel);
    }

    event GameRemoved(uint256 _gameId);
    function removeGame(uint256 _gameId) public onlyOwner {
    	require(gameInfo[_gameId].maxLevel > 0, 'Game Not Found');
      gameContracts.remove(address(gameInfo[_gameId].contractAddress));
    	delete gameInfo[_gameId];
      emit GameRemoved(_gameId);
    }

    function canPlay(address _player, uint256 _gameId)  external view returns(bool){
    	return _canPlay(_player, _gameId);
    }
    
    function _canPlay(address _player, uint256 _gameId)  internal view returns(bool){
    	if(playerInfo[_player].level >= gameInfo[_gameId].minLevel){
    		return true;
    	}

    	return false;
    }

    function playerActive(address _player) external view returns(bool){
        return _playerActive(_player);
    }

    function _playerActive(address _player) internal view returns(bool){
        if(block.timestamp <= playerInfo[_player].lastRollTime + activeTimeLimit){
            return true;
        }
        return false;
    }


    function claimRent() public nonReentrant {
    	require(rentShares.canClaim(msg.sender,0) > 0, 'Nothing to Claim');
      require( playerInfo[msg.sender].lastRollTime + activeTimeLimit >= block.timestamp, 'Roll to Claim');
    	// claim the rent share
      // _getMod(msg.sender)
    	rentShares.claimRent(msg.sender,0);
    }

    function getRentOwed(address _address) public view returns(uint256) {
    	// _getMod(_address)
      return rentShares.canClaim(_address,0);

    }
/*
    // @dev removed the total reduction, at this moment unsure if we add it back
    function getRentMod(address _address) public view returns(uint256) {
      return _getMod(_address);
    }


    /**
     * @dev return the penalty mod for this address, reduce 10% each day down to 10% total
    function _getMod(address _address) private view returns(uint256) {
    	uint256 mod = 100;
    	uint256 cutOff = playerInfo[_address].lastRollTime + activeTimeLimit;

    	if(cutOff > block.timestamp) {
    		// we need to adjust 
    		// see how many days
    		uint256 d = (cutOff - block.timestamp) / activeTimeLimit;
    		//if over 10 days, force it to 10%
    		if(d > 10) {
    			mod = 10;
    		} else {
    			mod = mod - (d * 10);
    		}
    	}
    	return mod;
    }
*/
    function setRentShares(IRentShares _rentSharesAddress) public onlyOwner {
      rentShares = _rentSharesAddress;
    }

    function setActiveTimeLimi(uint256 _activeTimeLimit) public onlyOwner {
      activeTimeLimit = _activeTimeLimit;
    }
    
}
