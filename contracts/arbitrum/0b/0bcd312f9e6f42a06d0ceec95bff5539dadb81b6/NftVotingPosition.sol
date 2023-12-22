pragma solidity 0.8.17;

// SPDX-License-Identifier: MIT

import "./ERC721.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ERC4626.sol";
import "./NftBattleArena.sol";
import "./IZooFunctions.sol";
import "./IGLPRewardRouter.sol";

/// @title NftVotingPosition
/// @notice contract for voters to interacte with BattleArena functions
contract NftVotingPosition is ERC721, Ownable
{
	event NftBattleArenaSet(address nftBattleArena);

	event ClaimedIncentiveRewardFromVoting(address indexed voter, address beneficiary, uint256 zooReward, uint256 votingPositionId);

	NftBattleArena public nftBattleArena;
	IZooFunctions public zooFunctions;                               // zooFunctions contract.
	address payable public team;
	IERC20 public dai;
	IERC20 public zoo;
	ERC4626 public lpZoo;
	IGLPRewardRouter public glpRewardRouter;
	address public glpManager;

	mapping(uint256 => bool) public isAllowedToSwapVotes;

	constructor(string memory _name, string memory _symbol, address _dai, address _zoo, address _lpZoo, address baseZooFunctions, address payable _team, address payable _glpRewardRouter, address _glpManager) ERC721(_name, _symbol)
	{
		dai = IERC20(_dai);
		zoo = IERC20(_zoo);
		lpZoo = ERC4626(_lpZoo);
		zooFunctions = IZooFunctions(baseZooFunctions);
		team = _team;
		glpRewardRouter = IGLPRewardRouter(_glpRewardRouter);
		glpManager = _glpManager;
	}

	modifier onlyVotingOwner(uint256 votingPositionId) {
		require(ownerOf(votingPositionId) == msg.sender, "Not the owner of voting");
		_;
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

	function createNewVotingPosition(uint256 stakingPositionId, uint256 amount, bool allowToSwapVotes) payable feePaid(msg.value) external returns (uint256 votes)
	{
		require(amount != 0, "zero vote not allowed");                                        // Requires for vote amount to be more than zero.
		require(nftBattleArena.getCurrentStage() != Stage.ThirdStage, "Wrong stage!");

		dai.transferFrom(msg.sender, address(nftBattleArena), amount);                        // Transfers DAI to arena contract for vote.
		
		uint256 votingPositionId;
		(votes, votingPositionId) = nftBattleArena.createVotingPosition(stakingPositionId, msg.sender, amount);
		_safeMint(msg.sender, votingPositionId);
		isAllowedToSwapVotes[votingPositionId] = allowToSwapVotes;
		return votes;
	}

	function getfsGLP(address token, uint256 amount, uint256 minUsdg, uint256 minGlp) internal returns(uint256) {
		// transfer tokens to Contract
		IERC20(token).transferFrom(msg.sender, address(this), amount);
		
		// take fee 1.5%
		IERC20(token).transfer(team, 15 * amount / 1000);

		// get fsGLP
		IERC20(token).approve(glpManager, 985 * amount / 1000);
		uint256 amountOut = glpRewardRouter.mintAndStakeGlp(token, 985 * amount / 1000, minUsdg, minGlp);
		
		return amountOut;
	}

	function createNewVotingPositionStablecoin(uint256 stakingPositionId, uint256 amount, bool allowToSwapVotes, address token, uint256 minUsdg, uint256 minGlp) payable feePaid(msg.value) external returns (uint256 votes)
	{
		require(amount != 0, "zero vote not allowed");                                        // Requires for vote amount to be more than zero.
		require(nftBattleArena.getCurrentStage() != Stage.ThirdStage, "Wrong stage!");

		// get fsGLP
		uint256 amountOut = getfsGLP(token, amount, minUsdg, minGlp);
		
		// send fsGLP to arena
		dai.transfer(address(nftBattleArena), amountOut);                        // Transfers DAI to arena contract for vote.
		
		uint256 votingPositionId;
		(votes, votingPositionId) = nftBattleArena.createVotingPosition(stakingPositionId, msg.sender, amountOut);
		_safeMint(msg.sender, votingPositionId);
		isAllowedToSwapVotes[votingPositionId] = allowToSwapVotes;
		return votes;
	}

	function addDaiToPosition(uint256 votingPositionId, uint256 amount) payable feePaid(msg.value) external returns (uint256 votes)
	{
		dai.transferFrom(msg.sender, address(nftBattleArena), amount);                        // Transfers DAI to arena contract for vote.
		return nftBattleArena.addDaiToVoting(votingPositionId, msg.sender, amount, 0);               // zero for yTokens coz its not swap.
	}

	function addDaiToPositionStablecoin(uint256 votingPositionId, uint256 amount, address token, uint256 minUsdg, uint256 minGlp) payable feePaid(msg.value) external returns (uint256 votes)
	{
		// get fsGLP
		uint256 amountOut = getfsGLP(token, amount, minUsdg, minGlp);

		dai.transfer(address(nftBattleArena), amountOut);                        // Transfers DAI to arena contract for vote.
		return nftBattleArena.addDaiToVoting(votingPositionId, msg.sender, amountOut, 0);               // zero for yTokens coz its not swap.
	}

	function addZooToPosition(uint256 votingPositionId, uint256 amount) payable feePaid(msg.value) external returns (uint256 votes) 
	{
		require(nftBattleArena.getCurrentStage() == Stage.FourthStage, "Wrong stage!");
		lpZoo.transferFrom(msg.sender, address(nftBattleArena), amount);                        // Transfers ZOO to arena contract for vote.
		return nftBattleArena.addZooToVoting(votingPositionId, msg.sender, amount);
	}

	function withdrawDaiFromVotingPosition(uint256 votingPositionId, address beneficiary, uint256 daiNumber) external onlyVotingOwner(votingPositionId)
	{
		nftBattleArena.withdrawDaiFromVoting(votingPositionId, msg.sender, beneficiary, daiNumber, false);
	}

	function withdrawDaiFromVotingPositionStablecoin(uint256 votingPositionId, address beneficiary, uint256 daiNumber, uint256 minOut, address tokenToReceive) external onlyVotingOwner(votingPositionId)
	{
		uint256 balanceBeforeWithdraw = dai.balanceOf(address(this));
		uint256 lpZooBalanceBeforeWithdraw = lpZoo.balanceOf(address(this));

		nftBattleArena.withdrawDaiFromVoting(votingPositionId, address(this), address(this), daiNumber, false);
		uint256 diff = dai.balanceOf(address(this)) - balanceBeforeWithdraw;

		// unstake tokens and receive in tokenToReceive
		uint256 amountOut = glpRewardRouter.unstakeAndRedeemGlp(tokenToReceive, diff, minOut, address(this));

		// take fee 1.5% of tokenToReceive
		IERC20(tokenToReceive).transfer(team, 15 * amountOut / 1000);

		// transfer 98.5% of tokenToReceive to msg.sender
		IERC20(tokenToReceive).transfer(msg.sender, 985 * amountOut / 1000);	

		// Send lpZoo to beneficiary if needed
		uint256 lpZooDiff = lpZooBalanceBeforeWithdraw - lpZoo.balanceOf(address(this));
		if (lpZooDiff != 0) {
			lpZoo.transfer(beneficiary, lpZooDiff);
		}
	}

	function withdrawZooFromVotingPosition(uint256 votingPositionId, uint256 zooNumber, address beneficiary) external onlyVotingOwner(votingPositionId)
	{
		nftBattleArena.withdrawZooFromVoting(votingPositionId, msg.sender, zooNumber, beneficiary);
	}

	function claimRewardFromVoting(uint256 votingPositionId, address beneficiary) external onlyVotingOwner(votingPositionId) returns (uint256)
	{
		return nftBattleArena.claimRewardFromVoting(votingPositionId, msg.sender, beneficiary);
	}

	function batchSwapVotesFromPrositionsForUnstakedNft(uint256[] calldata positions) external
	{
		for (uint256 i = 0; i < positions.length; i++)
		{
			swapVotesFromPositionForUnstackedNft(positions[i]);
		}
	}

	/// @notice Function to move votes from one position to another for unstacked NFT
	/// @notice If moving to nft not voted before(i.e. creating new position), then newVotingPosition should be zero.
	/// @param votingPositionId - Id of position votes moving from.
	function swapVotesFromPositionForUnstackedNft(uint256 votingPositionId) public
	{
		require(nftBattleArena.getCurrentStage() == Stage.FirstStage, "Wrong stage!");                         // Requires correct stage.
		require(isAllowedToSwapVotes[votingPositionId], "Owner of voting position didn't allow to swap votes");

		(uint256 stakingPositionId,uint256 daiInvested,,,,,,uint256 endEpoch,,,,) =  nftBattleArena.votingPositionsValues(votingPositionId);    // Gets id of staker position.
		(,uint256 endEpochOldStakingPosition,,,,) =  nftBattleArena.stakingPositionsValues(stakingPositionId);     // Gets endEpoch of staker position.
		
		require(endEpochOldStakingPosition != 0, "Nft is not unstacked");                         // Check if nft is unstacked
		// require(daiInvested != 0, "zero vote not allowed");                                                      // Requires for vote amount to be more than zero.
		require(endEpoch == 0, "E1");                  // Requires to be not liquidated yet.

		uint256 stakingPositionsAmount = nftBattleArena.getStakerPositionsLength();
		require(stakingPositionsAmount != 0, "There is no opponent for Nft");
		uint256 index = zooFunctions.computePseudoRandom()%stakingPositionsAmount;
		uint256 newStakingPositionId = nftBattleArena.activeStakerPositions(index);
		
		_swapVotesFromPosition(votingPositionId, daiInvested, newStakingPositionId, ownerOf(votingPositionId), 0, true);
	}

	/// @notice Function to move votes from one position to another for owner of voting position
	/// @notice If moving to nft not voted before(i.e. creating new position), then newVotingPosition should be zero.
	/// @param votingPositionId - Id of position votes moving from.
	/// @param daiNumber - amount of dai moving.
	/// @param newStakingPositionId - id of stakingPosition moving to.
	/// @param newVotingPosition - id of voting position moving to, if exist. If there are no such, should be zero.
	function swapVotesFromPositionForOwner(uint256 votingPositionId, uint256 daiNumber, uint256 newStakingPositionId, address beneficiary, uint256 newVotingPosition, bool allowToSwapVotes) external onlyVotingOwner(votingPositionId)
	{
		require(daiNumber != 0, "zero vote not allowed");                                                      // Requires for vote amount to be more than zero.
		require(newVotingPosition == 0 || ownerOf(newVotingPosition) == msg.sender, "Not the owner of voting");
		require(nftBattleArena.getCurrentStage() == Stage.FirstStage, "Wrong stage!");                         // Requires correct stage.
		_swapVotesFromPosition(votingPositionId, daiNumber, newStakingPositionId, beneficiary, newVotingPosition, allowToSwapVotes);
	}

	/// @notice Function to move votes from one position to another.
	function _swapVotesFromPosition(uint256 votingPositionId, uint256 daiNumber, uint256 newStakingPositionId, address beneficiary, uint256 newVotingPosition, bool allowToSwap) internal
	{

		(uint256 stakingPositionId, uint256 daiInvested,,,,,,,,,,) =  nftBattleArena.votingPositionsValues(votingPositionId);    // Gets id of staker position.

		if (daiNumber > daiInvested)                                                            // If swap amount more than invested.
		{
			daiNumber = daiInvested;                                                            // Set swap amount to maximum, same as in withdrawDai.
		}

		nftBattleArena.updateInfo(stakingPositionId);
		nftBattleArena.updateInfo(newStakingPositionId);

		uint256 yTokens = nftBattleArena.tokensToShares(daiNumber);

		nftBattleArena.withdrawDaiFromVoting(votingPositionId, ownerOf(votingPositionId), beneficiary, daiNumber, true);      // Calls internal withdrawDai.

		if (newVotingPosition == 0)                   // If zero, i.e. new position doesn't exist.
		{
			(, newVotingPosition) = nftBattleArena._createVotingPosition(newStakingPositionId, beneficiary, yTokens, daiNumber); // Creates new position to swap there.
			_safeMint(beneficiary, newVotingPosition);
			isAllowedToSwapVotes[newVotingPosition] = allowToSwap;
		}
		else                                          // If position existing, swap to it.
		{
			(,,,,,,,uint256 endEpoch,,,,) = nftBattleArena.votingPositionsValues(newVotingPosition);
			require(endEpoch == 0, "unstaked");       // Requires for position to exist and still be staked.

			nftBattleArena.addDaiToVoting(newVotingPosition, beneficiary, daiNumber, yTokens);                // swap votes to existing position.
		}
	}

	/// @notice Claims rewards from multiple voting positions
	/// @param votingPositionIds array of voting positions indexes
	/// @param beneficiary address to transfer reward to
	function batchClaimRewardsFromVotings(uint256[] calldata votingPositionIds, address beneficiary) external returns (uint256 reward)
	{
		for (uint256 i = 0; i < votingPositionIds.length; i++)
		{
			require(msg.sender == ownerOf(votingPositionIds[i]), "Not the owner of voting");

			reward += nftBattleArena.claimRewardFromVoting(votingPositionIds[i], msg.sender, beneficiary);
		}
	}

	function batchWithdrawDaiFromVoting(uint256[] calldata votingPositionIds, address beneficiary, uint256 daiNumber) external
	{
		for (uint256 i = 0; i < votingPositionIds.length; i++)
		{
			require(msg.sender == ownerOf(votingPositionIds[i]), "Not the owner of voting");

			nftBattleArena.withdrawDaiFromVoting(votingPositionIds[i], msg.sender, beneficiary, daiNumber, false);
		}
	}

	function batchWithdrawZooFromVoting(uint256[] calldata votingPositionIds, uint256 zooNumber, address beneficiary) external
	{
		for (uint256 i = 0; i < votingPositionIds.length; i++)
		{
			require(msg.sender == ownerOf(votingPositionIds[i]), "Not the owner of voting");

			nftBattleArena.withdrawZooFromVoting(votingPositionIds[i], msg.sender, zooNumber, beneficiary);
		}
	}

	/// @notice Function to claim incentive reward for voting, proportionally of collection weight in ve-Model pool.
	function claimIncentiveVoterReward(uint256 votingPositionId, address beneficiary) external returns (uint256)
	{
		require(ownerOf(votingPositionId) == msg.sender, "Not the owner!");                     // Requires to be owner of position.

		uint256 reward = nftBattleArena.calculateIncentiveRewardForVoter(votingPositionId);

		zoo.transfer(beneficiary, reward);

		return reward;
	}

	function batchClaimIncentiveVoterReward(uint256[] calldata votingPositionIds, address beneficiary) external returns (uint256 reward)
	{
		for (uint256 i = 0; i < votingPositionIds.length; i++)
		{
			require(ownerOf(votingPositionIds[i]) == msg.sender, "Not the owner!");             // Requires to be owner of position.

			uint256 claimed = nftBattleArena.calculateIncentiveRewardForVoter(votingPositionIds[i]);
			reward += claimed;

			emit ClaimedIncentiveRewardFromVoting(msg.sender, beneficiary, claimed, votingPositionIds[i]);
		}
		zoo.transfer(beneficiary, reward);
	}
}
