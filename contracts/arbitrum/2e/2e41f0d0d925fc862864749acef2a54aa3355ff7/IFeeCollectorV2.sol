// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IFeeCollectorV2 {
	struct SwapDistributionRatio {
		uint64 wlpHolders;
		uint64 staking;
		uint64 buybackAndBurn;
		uint64 core;
	}

	struct WagerDistributionRatio {
		uint64 staking;
		uint64 buybackAndBurn;
		uint64 core;
		uint64 luckyStrikePot;
	}

	struct Reserve {
		uint256 wlpHolders;
		uint256 staking;
		uint256 buybackAndBurn;
		uint256 core;
		uint256 luckyStrikePot;
	}

	// *** Destination addresses for the farmed fees from the vault *** //
	// note: the 6 addresses below need to be able to receive ERC20 tokens
	struct DistributionAddresses {
		// the destination address for the collected fees attributed to WLP holders
		address wlpClaim;
		// the destination address for the collected fees attributed  to WINR stakers
		address tokenManager;
		// address of the contract that does the 'buyback and burn'
		address buybackAndBurn;
		// the destination address for the collected fees attributed to core development
		address core;
		// address of the contract/EOA that will distribute the referral fees
		address referral;
		address luckyStrikePot;
	}

	struct DistributionTimes {
		uint256 wlpClaim;
		uint256 winrStaking;
		uint256 buybackAndBurn;
		uint256 core;
		uint256 referral;
		uint256 luckyStrikePot;
	}

	function isWhitelistedToken(address _token) external view returns (bool);

	function getReserves() external returns (Reserve memory);

	function getSwapDistribution() external returns (SwapDistributionRatio memory);

	function getWagerDistribution() external returns (WagerDistributionRatio memory);

	function getAddresses() external returns (DistributionAddresses memory);

	function allWhitelistedTokensLength() external view returns (uint256 whitelistedLength_);

	function allWhitelistedTokensFeeCollectorAtIndex(
		uint256 _index
	) external view returns (address token_);

	function calculateDistribution(
		uint256 _amountToDistribute,
		uint64 _ratio
	) external pure returns (uint256 amount_);

	function withdrawFeesAll() external;

	function isWhitelistedDestination(address _address) external returns (bool);

	function syncWhitelistedTokens() external;

	function addToWhitelist(address _toWhitelistAddress, bool _setting) external;

	function setLuckyStrikeContract(address _luckyStrikeContract) external;

	function returnLuckyStrikeRatio() external view returns (uint256);

	function setReferralDistributor(address _distributorAddress) external;

	function setCoreDevelopment(address _coreDevelopment) external;

	function setWinrStakingContract(address _winrStakingContract) external;

	function transferToLuckyStrikeContract() external;

	function setBuyBackAndBurnContract(address _buybackAndBurnContract) external;

	function setWlpClaimContract(address _wlpClaimContract) external;

	function returnAmountWlpForLuckyStrike() external view returns (uint256);

	function setWagerDistribution(
		uint64 _stakingRatio,
		uint64 _burnRatio,
		uint64 _coreRatio,
		uint64 _luckyStrikeRatio
	) external;

	function setSwapDistribution(
		uint64 _wlpHoldersRatio,
		uint64 _stakingRatio,
		uint64 _buybackRatio,
		uint64 _coreRatio
	) external;

	function addTokenToWhitelistList(address _tokenToAdd) external;

	function deleteWhitelistTokenList() external;

	function collectFeesBeforeLPEvent() external;

	function collectFeesOnLotteryWin() external;

	/*==================== Events *====================*/
	event DistributionSync();
	event WithdrawSync();
	event WhitelistEdit(address whitelistAddress, bool setting);
	event EmergencyWithdraw(address caller, address token, uint256 amount, address destination);
	event ManualGovernanceDistro();
	event FeesDistributed();
	event WagerFeesManuallyFarmed(address tokenAddress, uint256 amountFarmed);
	event ManualDistributionManager(
		address targetToken,
		uint256 amountToken,
		address destinationAddress
	);
	event SetRewardInterval(uint256 timeInterval);
	event SetCoreDestination(address newDestination);
	event SetBuybackAndBurnDestination(address newDestination);
	event SetClaimDestination(address newDestination);
	event SetReferralDestination(address referralDestination);
	event SetStakingDestination(address newDestination);
	event SwapFeesManuallyFarmed(address tokenAddress, uint256 totalAmountCollected);
	event CollectedWagerFees(address tokenAddress, uint256 amountCollected);
	event CollectedSwapFees(address tokenAddress, uint256 amountCollected);
	event NothingToDistribute(address token);
	event DistributionComplete(
		address token,
		uint256 toWLP,
		uint256 toStakers,
		uint256 toBuyBack,
		uint256 toCore,
		uint256 toReferral
	);
	event WagerDistributionSet(
		uint64 stakingRatio,
		uint64 burnRatio,
		uint64 coreRatio,
		uint64 luckyStrikeRatio
	);
	event SwapDistributionSet(
		uint64 _wlpHoldersRatio,
		uint64 _stakingRatio,
		uint64 _buybackRatio,
		uint64 _coreRatio
	);
	event SyncTokens();
	event DeleteAllWhitelistedTokens();
	event TokenAddedToWhitelist(address addedTokenAddress);
	event TokenTransferredByTimelock(address token, address recipient, uint256 amount);
	event SetLuckyStrikeDestination(address newDestination);
	event TransferLuckyStrikeTokens(address receiver, uint256 amount);

	event ManualFeeWithdraw(
		address token,
		uint256 swapFeesCollected,
		uint256 wagerFeesCollected,
		uint256 referralFeesCollected
	);

	event TransferBuybackAndBurnTokens(address receiver, uint256 amount);
	event TransferCoreTokens(address receiver, uint256 amount);
	event TransferWLPRewardTokens(address receiver, uint256 amount);
	event TransferWinrStakingTokens(address receiver, uint256 amount);
	event TransferReferralTokens(address token, address receiver, uint256 amount);
	event VaultUpdated(address vault);
	event WLPManagerUpdated(address wlpManager);
	event setWINRStakingContract(address winrStakingContract);
}

