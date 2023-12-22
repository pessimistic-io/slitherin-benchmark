pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./IERC20.sol";
import "./ERC721.sol";
import "./NftBattleArena.sol";
import "./IVault.sol";

/// @title XZoo
/// @notice Contract for staking zoo for aditional rewards.
contract XZoo is ERC721
{
	struct ZooStakerPosition
	{
		// epoch number => amount
		mapping (uint256 => uint256) amounts; 
		uint256 amount;
		uint256 startEpoch;
		uint256 endEpoch; 
		uint256 yTokensDebt;
	}

	IERC20 public stablecoin;

	IERC20 public zoo;

	VaultAPI public vault;

	NftBattleArena public arena;

	uint256 public indexCounter = 1;

	mapping (uint256 => ZooStakerPosition) public xZooPositions;

	// epoch => total staked zoo
	mapping (uint256 => int256) public totalStakedZoo;

	mapping (address => uint256[]) public tokenOfOwnerByIndex;

	uint256 public lastEpochWhereTotalStakedUpdated;

	event ZooStaked(address indexed staker, address indexed beneficiary, uint256 amount, uint256 positionId);

	event ZooWithdrawal(address indexed staker, address beneficiary, uint256 amount, uint256 positionId);

	event Claimed(address indexed staker, address beneficiary, uint256 amount, uint256 positionId);

	event NftBattleArenaSet(address nftBattleArena);

	constructor (string memory _name, string memory _symbol, address _stablecoin, address _zoo, address _vault) ERC721(_name, _symbol)
	{
		zoo = IERC20(_zoo);
		stablecoin = IERC20(_stablecoin);
		vault = VaultAPI(_vault);
	}

	/// @notice Function to set arena address.
	function setNftBattleArena(address _nftBattleArena) external
	{
		require(address(arena) == address(0));

		arena = NftBattleArena(_nftBattleArena);

		emit NftBattleArenaSet(_nftBattleArena);
	}

	/// @notice Function to stake zoo.
	/// @return xZooPositionId - Id of position.
	function stakeZoo(uint256 amount, address beneficiary) external returns (uint256 xZooPositionId)
	{
		zoo.transferFrom(msg.sender, address(this), amount);
		xZooPositions[indexCounter].amount = amount;
		xZooPositions[indexCounter].startEpoch = arena.currentEpoch() + 1;
		totalStakedZoo[arena.currentEpoch() + 1] += int256(amount);
		tokenOfOwnerByIndex[beneficiary].push(indexCounter);

		_mint(beneficiary, indexCounter);
		emit ZooStaked(msg.sender, beneficiary, amount, indexCounter);

		return indexCounter++;
	}


	/// @notice Function to claim reward from zoo staking.
	function claimRewards(uint256 positionId, address beneficiary) external returns (uint256 amountOfstablecoins)
	{
		require(ownerOf(positionId) == msg.sender, "not owner");
		updateTotalStakedUpdated();

		ZooStakerPosition storage position = xZooPositions[positionId];
		uint256 rewards = getPendingReward(positionId);
		position.yTokensDebt = 0;
		position.startEpoch = arena.currentEpoch();

		vault.redeem(rewards);
		amountOfstablecoins = stablecoin.balanceOf(address(this));
		IERC20(arena.dai()).transfer(beneficiary, amountOfstablecoins);

		emit Claimed(msg.sender, beneficiary, amountOfstablecoins, positionId);
	}

	/// @notice Function to return zoo to beneficiary used when staked.
	function unlockZoo(uint256 positionId, address beneficiary) external returns (uint256 amountOfZoo)
	{
		require(ownerOf(positionId) == msg.sender);
		updateTotalStakedUpdated();

		ZooStakerPosition storage position = xZooPositions[positionId];
		require(position.endEpoch == 0);
		position.yTokensDebt = getPendingReward(positionId);
		position.endEpoch = arena.currentEpoch();
		zoo.transfer(beneficiary, position.amount);
		totalStakedZoo[arena.currentEpoch() + 1] -= int256(position.amount);

		emit ZooWithdrawal(msg.sender, beneficiary, position.amount, positionId);
		amountOfZoo = position.amount;
		position.amount = 0;
	}

	/// @notice Function for both unlock and claim.
	function unlockAndClaim(uint256 positionId, address beneficiary) external returns (uint256 amountOfZoo, uint256 rewardsForClaimer)
	{
		require(ownerOf(positionId) == msg.sender);
		updateTotalStakedUpdated();

		ZooStakerPosition storage position = xZooPositions[positionId];
		require(position.endEpoch == 0);
		uint256 rewards = getPendingReward(positionId);
		position.yTokensDebt = 0;
		position.startEpoch = arena.currentEpoch();
		vault.redeem(rewards);
		uint256 amountOfstablecoins = stablecoin.balanceOf(address(this));
		IERC20(stablecoin).transfer(beneficiary, amountOfstablecoins);
		position.endEpoch = arena.currentEpoch();
		zoo.transfer(beneficiary, position.amount);
		totalStakedZoo[arena.currentEpoch() + 1] -= int256(position.amount);

		emit Claimed(msg.sender, beneficiary, amountOfstablecoins, positionId);
		emit ZooWithdrawal(msg.sender, beneficiary, position.amount, positionId);
		amountOfZoo = position.amount;
		rewardsForClaimer = amountOfstablecoins;
		position.amount = 0;
	}

	/// @notice Function to add zoo to position.
	function addZoo(uint256 positionId, uint256 amount) external
	{
		require(ownerOf(positionId) == msg.sender);
		ZooStakerPosition storage position = xZooPositions[positionId];
		require(position.endEpoch == 0);

		try arena.updateEpoch()
		{

		}
		catch
		{
			
		}

		updateTotalStakedUpdated();

		zoo.transferFrom(msg.sender, address(this), amount);

		uint256 currentEpoch = arena.currentEpoch();
		position.yTokensDebt = getPendingReward(positionId);
		if (position.startEpoch <= currentEpoch)
			position.startEpoch = currentEpoch;

		position.amounts[currentEpoch] = position.amounts[currentEpoch] == 0 ? position.amount : position.amounts[currentEpoch];
		position.amount += amount;
		totalStakedZoo[currentEpoch + 1] += int256(amount);

		emit ZooStaked(msg.sender, ownerOf(positionId), amount, positionId);
	}

	/// @notice Function to withdraw only part of staked zoo.
	function withdrawZoo(uint256 positionId, uint256 amount, address beneficiary) external
	{
		require(ownerOf(positionId) == msg.sender);
		updateTotalStakedUpdated();

		ZooStakerPosition storage position = xZooPositions[positionId];
		require(position.endEpoch == 0);

		position.yTokensDebt = getPendingReward(positionId);
		uint256 currentEpoch = arena.currentEpoch();
		if (position.startEpoch <= currentEpoch)
			position.startEpoch = currentEpoch;

		position.amounts[currentEpoch] = position.amounts[currentEpoch] == 0 ? position.amount - amount : position.amounts[currentEpoch] - amount;
		position.amount -= amount;
		totalStakedZoo[currentEpoch + 1] -= int256(amount);
		zoo.transfer(beneficiary, amount);

		emit ZooWithdrawal(msg.sender, beneficiary, amount, positionId);
	}

	function updateTotalStakedUpdated() public
	{
		uint256 i = lastEpochWhereTotalStakedUpdated + 1;
		for (; i < arena.currentEpoch(); i++)
		{
			totalStakedZoo[i] += totalStakedZoo[i - 1];
		}

		lastEpochWhereTotalStakedUpdated = i - 1;
	}

	/// @notice Function to get pending reward from staking zoo.
	function getPendingReward(uint256 positionId) public view returns (uint256 yvTokens)
	{
		ZooStakerPosition storage position = xZooPositions[positionId];
		uint256 end = position.endEpoch == 0 ? arena.currentEpoch() : position.endEpoch;
		yvTokens += position.yTokensDebt;

		for (uint256 epoch = position.startEpoch; epoch < end; epoch++)
		{
			yvTokens += getAmountByEpochAndPosition(epoch, position) * arena.xZooRewards(epoch) / uint256(totalStakedZoo[epoch]); 
		}
	}

	function getAmountByEpochAndPosition(uint256 epoch, ZooStakerPosition storage position) internal view returns (uint256 amount)
	{
		if (position.amounts[epoch] == 0)
			return position.amount;
		else
			position.amounts[epoch];
	}
}
