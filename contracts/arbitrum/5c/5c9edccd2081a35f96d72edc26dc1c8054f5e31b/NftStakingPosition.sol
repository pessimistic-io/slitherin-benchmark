pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./ERC721.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ListingList.sol";
import "./NftBattleArena.sol";
import "./IZooFunctions.sol";

/// @title NftStakingPosition
/// @notice Contract to stake/unstake NFTs
contract NftStakingPosition is ERC721, Ownable
{
	struct Nft
	{
		address token;
		uint256 id;
	}

	IZooFunctions public zooFunctions;                               // zooFunctions contract.
	address payable public team;

	event NftBattleArenaSet(address nftBattleArena);

	event ClaimedIncentiveRewardFromVoting(address indexed staker, address beneficiary, uint256 zooReward, uint256 stakingPositionId);

	// Records NFT contracts available for staking.
	NftBattleArena public nftBattleArena;
	ListingList public listingList;
	IERC20 public zoo;

	mapping (uint256 => Nft) public positions;

	constructor(string memory _name, string memory _symbol, address _listingList, address _zoo, address baseZooFunctions, address payable _team) ERC721(_name, _symbol) Ownable()
	{
		listingList = ListingList(_listingList);
		zoo = IERC20(_zoo);
		zooFunctions = IZooFunctions(baseZooFunctions);
		team = _team;
	}

	modifier feePaid(uint256 fee) {
		require(fee >= zooFunctions.getArenaFee(), "Fee wasn't provide to arena");
		_;
		(bool sent, ) = address(team).call{value: msg.value}("");
		require(sent, "Failed to send");
	}

	function setNftBattleArena(address _nftBattleArena) external onlyOwner
	{
		require(address(nftBattleArena) == address(0));

		nftBattleArena = NftBattleArena(_nftBattleArena);

		emit NftBattleArenaSet(_nftBattleArena);
	}

	function stakeNft(address token, uint256 id) payable feePaid(msg.value) external
	{
		require(listingList.eligibleCollections(token), "NFT collection is not allowed");
		require(nftBattleArena.getCurrentStage() == Stage.FirstStage, "Wrong stage!");

		IERC721(token).transferFrom(msg.sender, address(this), id);                // Sends NFT token to this contract.

		uint256 index = nftBattleArena.createStakerPosition(msg.sender, token);
		_safeMint(msg.sender, index);
		positions[index] = Nft(token, id);
	}

	function unstakeNft(uint256 stakingPositionId) external
	{
		require(ownerOf(stakingPositionId) == msg.sender, "Not the owner of NFT");
		require(nftBattleArena.getCurrentStage() == Stage.FirstStage, "Wrong stage!");

		nftBattleArena.removeStakerPosition(stakingPositionId, msg.sender);

		Nft storage nft = positions[stakingPositionId];
		IERC721(nft.token).transferFrom(address(this), msg.sender, nft.id);                 // Transfers token back to owner.
	}

	function claimRewardFromStaking(uint256 stakingPositionId, address beneficiary) external
	{
		require(ownerOf(stakingPositionId) == msg.sender, "Not the owner of NFT");
		
		nftBattleArena.claimRewardFromStaking(stakingPositionId, msg.sender, beneficiary);
	}

	/// Claims rewards from multiple staking positions
	/// @param stakingPositionIds array of staking positions indexes
	/// @param beneficiary address to transfer reward to
	function batchClaimRewardsFromStaking(uint256[] calldata stakingPositionIds, address beneficiary) external
	{
		for (uint256 i = 0; i < stakingPositionIds.length; i++)
		{
			require(msg.sender == ownerOf(stakingPositionIds[i]), "Not the owner of NFT");

			nftBattleArena.claimRewardFromStaking(stakingPositionIds[i], msg.sender, beneficiary);
		}
	}

	function batchUnstakeNft(uint256[] calldata stakingPositionIds) external
	{
		require(nftBattleArena.getCurrentStage() == Stage.FirstStage, "Wrong stage!");

		for (uint256 i = 0; i < stakingPositionIds.length; i++)
		{
			require(msg.sender == ownerOf(stakingPositionIds[i]), "Not the owner of NFT");

			nftBattleArena.removeStakerPosition(stakingPositionIds[i], msg.sender);

			Nft storage nft = positions[stakingPositionIds[i]];
			IERC721(nft.token).transferFrom(address(this), msg.sender, nft.id);                 // Transfers token back to owner.
		}
	}

	function claimIncentiveStakerReward(uint256 stakingPositionId, address beneficiary) external returns (uint256)
	{
		require(ownerOf(stakingPositionId) == msg.sender, "Not the owner!");             // Requires to be owner of position.
		uint256 reward = nftBattleArena.calculateIncentiveRewardForStaker(stakingPositionId);

		zoo.transfer(beneficiary, reward);

		return reward;
	}

	function batchClaimIncentiveStakerReward(uint256[] calldata stakingPositionIds, address beneficiary) external returns (uint256 reward)
	{
		for (uint256 i = 0; i < stakingPositionIds.length; i++)
		{
			require(ownerOf(stakingPositionIds[i]) == msg.sender, "Not the owner!");             // Requires to be owner of position.

			uint256 claimed = nftBattleArena.calculateIncentiveRewardForStaker(stakingPositionIds[i]);
			reward += claimed;

			emit ClaimedIncentiveRewardFromVoting(msg.sender, beneficiary, claimed, stakingPositionIds[i]);
		}
		zoo.transfer(beneficiary, reward);
	}
}
