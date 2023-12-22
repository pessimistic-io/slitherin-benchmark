//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ExplorationSettings.sol";

contract Exploration is Initializable, ExplorationSettings {
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

	function initialize() external initializer {
		ExplorationSettings.__ExplorationSettings_init();
	}

	function setMinStakingTimeInSeconds(uint256 _minStakingTime) 
		external
		override  
		onlyAdminOrOwner 
	{
		require(_minStakingTime >= 0, "Staking time cannot be negative");
		minStakingTimeInSeconds = _minStakingTime;
	}

	function claimBarns(uint256[] calldata _tokenIds)
		external
		onlyEOA
		whenNotPaused
		contractsAreSet
		nonZeroLength(_tokenIds)
	{
		require(minStakingTimeInSeconds > 0, "Minimum staking time is not defined");
		for(uint256 i = 0; i < _tokenIds.length; i++) {
			require(ownerForStakedDonkey(_tokenIds[i]) == msg.sender, "Exploration: User does not own Donkey");
			//User will only be allowed to claim if donkey is staked
			require(locationForStakedDonkey(_tokenIds[i]) == Location.EXPLORATION, "Exploration: Donkey is not exploring");
			require(isBarnClaimEligible(_tokenIds[i]), "Donkey is not eligible for claim");
			_claimBarn(_tokenIds[i], msg.sender);
		}
	}

	function _claimBarn(uint256 _tokenId, address _to) private {
		uint256 lastStakedTime = tokenToStakeInfo[_tokenId].lastStakedTime;
		require(lastStakedTime > 0, "Exploration: Cannot have last staked time of 0");

		uint256 totalTimeStaked = (block.timestamp - lastStakedTime);

		//Seconds as time unit
		require(totalTimeStaked > minStakingTimeInSeconds, "Exploration: Donkey has not been staked long enough");

		tokenIdToBarnClaimed[_tokenId] = true;

		barn.mint(_to, 1);

		emit ClaimedBarn(_tokenId, _to, block.timestamp);
	}

	function isBarnClaimedForToken(uint256 _tokenId) external view returns(bool) {
		return tokenIdToBarnClaimed[_tokenId];
	}

	function transferDonkeysToExploration(uint256[] calldata _tokenIds)
		external
		whenNotPaused
		contractsAreSet
		onlyEOA
		nonZeroLength(_tokenIds)
	{
		for(uint256 i = 0; i < _tokenIds.length; i++) {
			uint256 _tokenId = _tokenIds[i];
			_requireValidDonkeyAndLocation(_tokenId, Location.EXPLORATION);
			_transferFromLocation(_tokenId);
		}

		emit DonkeyLocationChanged(_tokenIds, msg.sender, Location.EXPLORATION);
	}

	function transferDonkeysOutOfExploration(uint256[] calldata _tokenIds)
		external
		whenNotPaused
		contractsAreSet
		onlyEOA
		nonZeroLength(_tokenIds)
	{
		for(uint256 i = 0; i < _tokenIds.length; i++) {
			uint256 _tokenId = _tokenIds[i];
			_requireValidDonkeyAndLocation(_tokenId, Location.NOT_STAKED);
			_transferFromLocation(_tokenId);
		}

		emit DonkeyLocationChanged(_tokenIds, msg.sender, Location.NOT_STAKED);
	}

	function _transferFromLocation(uint256 _tokenId) private {
		Location _oldLocation = tokenIdToInfo[_tokenId].location;		
		// If old location is exploration, then we want to unstake it
		if(_oldLocation == Location.EXPLORATION) {
			ownerToStakedTokens[msg.sender].remove(_tokenId);
			delete tokenIdToInfo[_tokenId];
			tokenToStakeInfo[_tokenId].lastStakedTime = 0;
			tld.safeTransferFrom(address(this), msg.sender, _tokenId);
			emit StoppedExploring(_tokenId, msg.sender);
		} else if(_oldLocation == Location.NOT_STAKED) {
			ownerToStakedTokens[msg.sender].add(_tokenId);
			tokenIdToInfo[_tokenId].owner = msg.sender;
			tokenIdToInfo[_tokenId].location = Location.EXPLORATION;
			tokenToStakeInfo[_tokenId].lastStakedTime = block.timestamp;
			// Will revert if user doesn't own token.
			tld.safeTransferFrom(msg.sender, address(this), _tokenId);
			emit StartedExploring(_tokenId, msg.sender);
		} else {
			revert("Exploration: Unknown location");
		}
	}

	function _requireValidDonkeyAndLocation(uint256 _tokenId, Location _newLocation) private view {
		Location _oldLocation = tokenIdToInfo[_tokenId].location;
		// Donkey is Exploring
		if(_oldLocation != Location.NOT_STAKED) {
			require(ownerToStakedTokens[msg.sender].contains(_tokenId), "Exploration: Caller does not own Donkey");
		}
		require(_oldLocation != _newLocation, "Exploration: Location must be different");
	}

	function balanceOf(address _owner) external view override returns (uint256) {
		return ownerToStakedTokens[_owner].length();
	}

	function ownerForStakedDonkey(uint256 _tokenId) public view override returns(address) {
		address _owner = tokenIdToInfo[_tokenId].owner;
		require(_owner != address(0), "Exploration: Donkey is not staked");
		return _owner;
	}

	function totalStakedTimeForDonkeyInSec(uint256 _tokenId) internal view returns (uint256) {
		uint256 lastStakedTime = tokenToStakeInfo[_tokenId].lastStakedTime;
		// require(lastStakedTime > 0, "Exploration: Donkey is not staked");
		if (lastStakedTime == 0) {
			return 0;
		}

		return ((tokenIdToStakeTimeInSeconds[_tokenId]) + (block.timestamp - lastStakedTime));
	}

	function locationForStakedDonkey(uint256 _tokenId) public view override returns(Location) {
		return tokenIdToInfo[_tokenId].location;
	}

	function isDonkeyStaked(uint256 _tokenId) public view returns(bool) {
		return tokenIdToInfo[_tokenId].owner != address(0);
	}

	function infoForDonkey(uint256 _tokenId) external view returns(TokenInfo memory) {
		require(isDonkeyStaked(_tokenId), "Exploration: Donkey is not staked");
		return tokenIdToInfo[_tokenId];
	}

	function isBarnClaimEligible(uint256 _tokenId) public view returns(bool) {
		if (minStakingTimeInSeconds <= 0) {
			return false;
		}
		uint256 lastStakedTime = tokenToStakeInfo[_tokenId].lastStakedTime;
		uint256 totalTimeStaked = (block.timestamp - lastStakedTime);
		bool isBarnClaimed =  tokenIdToBarnClaimed[_tokenId];
		return (totalTimeStaked >= minStakingTimeInSeconds) && (lastStakedTime > 0) && !isBarnClaimed;
	}

	function timeStakedForDonkey(uint256 _tokenId) public view returns(uint256) {
		uint256 lastStakedTime = tokenToStakeInfo[_tokenId].lastStakedTime;
		require(lastStakedTime > 0, "Exploration: Donkey is not staked");
		return lastStakedTime;
	}
}

