// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./IVault.sol";
import "./IWLPManager.sol";
import "./ITokenManager.sol";
import "./IWINRStaking.sol";
import "./IFeeCollectorV2.sol";
import "./IBasicFDT.sol";
import "./AccessControlBase.sol";

contract FeeCollectorV2 is ReentrancyGuard, AccessControlBase, IFeeCollectorV2 {
	using EnumerableSet for EnumerableSet.AddressSet;
	/*==================== Constants *====================*/
	uint256 private constant MAX_INTERVAL = 14 days;
	uint256 private constant BASIS_POINTS_DIVISOR = 1e4;
	uint256 private constant PRICE_PRECISION = 1e30;

	/*==================== State Variabes *====================*/
	IVault public vault;
	IWLPManager public wlpManager;
	IERC20 public wlp;
	IWINRStaking public winrStaking;
	// the fee distribution reward interval
	uint256 public rewardInterval = 1 days;
	// array with addresses of all tokens fees are collected in
	// address[] public allWhitelistedTokensFeeCollector;
	EnumerableSet.AddressSet internal allWhitelistedTokensSet;
	mapping(address => bool) private whitelistedDestinations;
	// stores tokens amounts of referral
	mapping(address => uint256) public referralReserve;
	// ratio configuration for receivers of accumulated wagerfees
	WagerDistributionRatio public wagerDistributionConfig;
	// ratio configuration for receivers of accumulated swapfees
	SwapDistributionRatio public swapDistributionConfig;
	// stores wlp amounts of addresses
	Reserve public reserves;
	// distribution addresses
	DistributionAddresses public addresses;
	// last distribution times of destinations
	DistributionTimes public lastDistributionTimes;
	// if true, the contract will revert on time based distribution functions
	bool public failOnTime = false;

	constructor(
		address _vaultRegistry,
		address _vault,
		address _wlpManager,
		address _wlpClaimContract,
		address _tokenManagerContract,
		address _winrStakingContract,
		address _buybackAndBurnContract,
		address _coreDevelopment,
		address _luckyStrikeContract,
		address _referralContract,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		_checkNotNull(_vault);
		_checkNotNull(_wlpManager);
		vault = IVault(_vault);
		wlpManager = IWLPManager(_wlpManager);

		addresses = IFeeCollectorV2.DistributionAddresses(
			_wlpClaimContract,
			_tokenManagerContract,
			_buybackAndBurnContract,
			_coreDevelopment,
			_referralContract,
			_luckyStrikeContract
		);

		lastDistributionTimes = DistributionTimes(
			block.timestamp,
			block.timestamp,
			block.timestamp,
			block.timestamp,
			block.timestamp,
			block.timestamp
		);

		wlp = IERC20(wlpManager.wlp());
		winrStaking = IWINRStaking(_winrStakingContract);

		whitelistedDestinations[_wlpClaimContract] = true;
		whitelistedDestinations[_tokenManagerContract] = true;
		whitelistedDestinations[_coreDevelopment] = true;
		whitelistedDestinations[_buybackAndBurnContract] = true;
		whitelistedDestinations[_referralContract] = true;
		whitelistedDestinations[_timelock] = true;
		whitelistedDestinations[_luckyStrikeContract] = true;
	}

	/*==================== Configuration functions (onlyGovernance) *====================*/

	/**
	 * @notice function that sets vault address
	 */
	function setVault(address vault_) external onlyTimelockGovernance {
		_checkNotNull(vault_);
		vault = IVault(vault_);
		emit VaultUpdated(vault_);
	}

	/**
	 * @notice function that changes wlp manager address
	 */
	function setWlpManager(address wlpManager_) public onlyTimelockGovernance {
		_checkNotNull(wlpManager_);
		wlpManager = IWLPManager(wlpManager_);
		wlp = IERC20(wlpManager.wlp());
		_checkNotNull(address(wlp));
		emit WLPManagerUpdated(address(wlpManager_));
	}

	/**
	 * @param _wlpClaimContract address for the claim destination
	 */
	function setWlpClaimContract(address _wlpClaimContract) external onlyTimelockGovernance {
		_checkNotNull(_wlpClaimContract);
		// remove previous destination from whitelist
		whitelistedDestinations[addresses.wlpClaim] = false;
		addresses.wlpClaim = _wlpClaimContract;
		whitelistedDestinations[_wlpClaimContract] = true;
		emit SetClaimDestination(_wlpClaimContract);
	}

	/**
	 * @param _buybackAndBurnContract address for the buyback and burn destination
	 */
	function setBuyBackAndBurnContract(
		address _buybackAndBurnContract
	) external onlyTimelockGovernance {
		_checkNotNull(_buybackAndBurnContract);
		// remove previous destination from whitelist
		whitelistedDestinations[addresses.buybackAndBurn] = false;
		addresses.buybackAndBurn = _buybackAndBurnContract;
		whitelistedDestinations[_buybackAndBurnContract] = true;
		emit SetBuybackAndBurnDestination(_buybackAndBurnContract);
	}

	/**
	 * @notice function that sets the referral contract address
	 * @param _luckyStrikeContract address for the lucky strike destination
	 */
	function setLuckyStrikeContract(
		address _luckyStrikeContract
	) external onlyTimelockGovernance {
		_checkNotNull(_luckyStrikeContract);
		// remove previous destination from whitelist
		whitelistedDestinations[addresses.luckyStrikePot] = false;
		addresses.luckyStrikePot = _luckyStrikeContract;
		whitelistedDestinations[_luckyStrikeContract] = true;
		emit SetLuckyStrikeDestination(_luckyStrikeContract);
	}

	/**
	 * @param _tokenManagerContract address for the winr staking destination
	 */
	function setTokenManagerContract(
		address _tokenManagerContract
	) external onlyTimelockGovernance {
		_checkNotNull(_tokenManagerContract);
		// remove previous destination from whitelist
		whitelistedDestinations[addresses.tokenManager] = false;
		addresses.tokenManager = _tokenManagerContract;
		whitelistedDestinations[_tokenManagerContract] = true;
		emit SetStakingDestination(_tokenManagerContract);
	}

	function setWinrStakingContract(address _winrStakingContract) external onlyTimelockGovernance() {
		_checkNotNull(_winrStakingContract);
		winrStaking = IWINRStaking(_winrStakingContract);
		emit setWINRStakingContract(_winrStakingContract);
	}

	function returnLuckyStrikeRatio() external view returns (uint256) {
		return uint256(wagerDistributionConfig.luckyStrikePot);
	}

	/**
	 * @param _coreDevelopment  address for the core destination
	 */
	function setCoreDevelopment(address _coreDevelopment) external onlyTimelockGovernance {
		_checkNotNull(_coreDevelopment);
		// remove previous destination from whitelist
		whitelistedDestinations[addresses.core] = false;
		addresses.core = _coreDevelopment;
		whitelistedDestinations[_coreDevelopment] = true;
		emit SetCoreDestination(_coreDevelopment);
	}

	/**
	 * @param _referralAddress  address for the referral distributor
	 */
	function setReferralDistributor(address _referralAddress) external onlyTimelockGovernance {
		_checkNotNull(_referralAddress);
		// remove previous destination from whitelist
		whitelistedDestinations[addresses.referral] = false;
		addresses.referral = _referralAddress;
		whitelistedDestinations[_referralAddress] = true;
		emit SetReferralDestination(_referralAddress);
	}

	/**
	 * @notice function to add a fee destination address to the whitelist
	 * @dev can only be called by the timelock governance contract
	 * @param _toWhitelistAddress address to whitelist
	 * @param _setting bool to either whitelist or 'unwhitelist' address
	 */
	function addToWhitelist(address _toWhitelistAddress, bool _setting) external onlyTeam {
		_checkNotNull(_toWhitelistAddress);
		whitelistedDestinations[_toWhitelistAddress] = _setting;
		emit WhitelistEdit(_toWhitelistAddress, _setting);
	}

	/**
	 * @notice configuration function for reward interval
	 * @dev the configured fee collection interval cannot exceed the MAX_INTERVAL
	 * @param _timeInterval uint time interval for fee collection
	 */
	function setRewardInterval(uint256 _timeInterval) external onlyTeam {
		require(_timeInterval <= MAX_INTERVAL, "FeeCollector: invalid interval");
		rewardInterval = _timeInterval;
		emit SetRewardInterval(_timeInterval);
	}

	/**
	 * @notice function that configures the collected wager fee distribution
	 * @dev the ratios together should equal 1e4 (100%)
	 * @param _stakingRatio the ratio of the winr stakers
	 * @param _buybackAndBurnRatioWager the ratio of the buyback and burning amounts
	 * @param _coreRatio  the ratio of the core dev
	 * @param _luckyStrikeRatio  the ratio of the lucky strike pot
	 */
	function setWagerDistribution(
		uint64 _stakingRatio,
		uint64 _buybackAndBurnRatioWager,
		uint64 _coreRatio,
		uint64 _luckyStrikeRatio
	) external onlyGovernance {
		// together all the ratios need to sum to 1e4 (100%)
		require(
			(_stakingRatio +
				_buybackAndBurnRatioWager +
				_coreRatio +
				_luckyStrikeRatio) == 1e4,
			"FeeCollector: Wager Ratios together don't sum to 1e4"
		);
		wagerDistributionConfig = WagerDistributionRatio(
			_stakingRatio,
			_buybackAndBurnRatioWager,
			_coreRatio,
			_luckyStrikeRatio
		);
		emit WagerDistributionSet(
			_stakingRatio,
			_buybackAndBurnRatioWager,
			_coreRatio,
			_luckyStrikeRatio
		);
	}

	/**
	 * @notice function that configures the collected swap fee distribution
	 * @dev the ratios together should equal 1e4 (100%)
	 * @param _wlpHoldersRatio the ratio of the totalRewards going to WLP holders
	 * @param _stakingRatio the ratio of the totalRewards going to WINR stakers
	 * @param _buybackAndBurnRatio  the ratio of the buyBack and burn going to buyback and burn address
	 * @param _coreRatio  the ratio of the totalRewars going to core dev
	 */
	function setSwapDistribution(
		uint64 _wlpHoldersRatio,
		uint64 _stakingRatio,
		uint64 _buybackAndBurnRatio,
		uint64 _coreRatio
	) external onlyGovernance {
		// together all the ratios need to sum to 1e4 (100%)
		require(
			(_wlpHoldersRatio + _stakingRatio + _buybackAndBurnRatio + _coreRatio) ==
				1e4,
			"FeeCollector: Ratios together don't sum to 1e4"
		);
		swapDistributionConfig = SwapDistributionRatio(
			_wlpHoldersRatio,
			_stakingRatio,
			_buybackAndBurnRatio,
			_coreRatio
		);
		emit SwapDistributionSet(
			_wlpHoldersRatio,
			_stakingRatio,
			_buybackAndBurnRatio,
			_coreRatio
		);
	}

	/**
	 * @notice function that syncs the whitelisted tokens with the vault
	 */
	function syncWhitelistedTokens() external onlySupport {
		// delete allWhitelistedTokensFeeCollector;
		_deleteAllWhitelistedTokensSet();
		uint256 count_ = vault.allWhitelistedTokensLength();
		for (uint256 i = 0; i < count_; ++i) {
			address token_ = vault.allWhitelistedTokens(i);
			allWhitelistedTokensSet.add(token_);
		}
		emit SyncTokens();
	}

	function allWhitelistedTokensLength()
		external
		view
		override
		returns (uint256 whitelistedLength_)
	{
		whitelistedLength_ = allWhitelistedTokensSet.length();
	}

	function _deleteAllWhitelistedTokensSet() internal {
		uint256 length_ = allWhitelistedTokensSet.length();
		for (uint256 i = 0; i < length_; ++i) {
			allWhitelistedTokensSet.remove(allWhitelistedTokensSet.at(0));
		}
	}

	function isWhitelistedToken(address _token) external view returns (bool) {
		return allWhitelistedTokensSet.contains(_token);
	}

	function allWhitelistedTokensFeeCollectorAtIndex(
		uint256 _index
	) external view override returns (address token_) {
		token_ = allWhitelistedTokensSet.at(_index);
	}

	/**
	 * @notice manually adds a tokenaddress to the vault
	 * @param _tokenToAdd address to manually add to the llWhitelistedTokensFeeCollector array
	 */
	function addTokenToWhitelistList(address _tokenToAdd) external onlyTeam {
		// allWhitelistedTokensFeeCollector.push(_tokenToAdd);
		allWhitelistedTokensSet.add(_tokenToAdd);
		emit TokenAddedToWhitelist(_tokenToAdd);
	}

	/**
	 * @notice deletes entire whitelist array
	 * @dev this function should be used before syncWhitelistedTokens is called!
	 */
	function deleteWhitelistTokenList() external onlyTeam {
		// delete allWhitelistedTokensFeeCollector;
		_deleteAllWhitelistedTokensSet();
		emit DeleteAllWhitelistedTokens();
	}

	/*==================== Operational functions WINR/JB *====================*/

	/**
	 * @notice manually sync last distribution time so they are in line again
	 */
	function syncLastDistribution() external onlySupport {
		lastDistributionTimes = DistributionTimes(
			block.timestamp,
			block.timestamp,
			block.timestamp,
			block.timestamp,
			block.timestamp,
			block.timestamp
		);
		emit DistributionSync();
	}

	/*==================== Public callable operational functions *====================*/

	/**
	 * @notice returns accumulated/pending rewards for distribution addresses
	 */
	function getReserves() external view returns (Reserve memory reserves_) {
		reserves_ = reserves;
	}

	/**
	 * @notice returns the swap fee distribution ratios
	 */
	function getSwapDistribution()
		external
		view
		returns (SwapDistributionRatio memory swapDistributionConfig_)
	{
		swapDistributionConfig_ = swapDistributionConfig;
	}

	/**
	 * @notice returns the wager fee distribution ratios
	 */
	function getWagerDistribution()
		external
		view
		returns (WagerDistributionRatio memory wagerDistributionConfig_)
	{
		wagerDistributionConfig_ = wagerDistributionConfig;
	}

	/**
	 * @notice returns the distribution addresses (recipients of wager and swap fees) per destination
	 */
	function getAddresses() external view returns (DistributionAddresses memory addresses_) {
		addresses_ = addresses;
	}

	/**
	 * @notice function that checks if a given address is whitelisted
	 * @dev outgoing transfers of any type can only happen if a destination address is whitelisted (safetly measure)
	 * @param _address address to check if it is whitelisted
	 */
	function isWhitelistedDestination(
		address _address
	) external view returns (bool whitelisted_) {
		whitelisted_ = whitelistedDestinations[_address];
	}

	/**
	 * @notice function that claims/farms the wager+swap fees in vault, and distributes it to wlp holders, stakers and core dev
	 * @dev function can only be called once per interval period
	 */
	function withdrawFeesAll() external onlySupport {
		_withdrawAllFees();
		emit FeesDistributed();
	}

	function withdrawFeesAndDistribute() external {
		_withdrawAllFees();
		_transferCore();
		_transferBuyBackAndBurn();
		_transferReferral();
		_transferWinrStaking();
		_transferWlpRewards();
		_transferLuckyStrikeContract();
		emit FeesDistributed();
	}

	/**
	 * @notice manaul transfer tokens from the feecollector to a whitelisted destination address
	 * @dev our of safety concerns it is only possilbe to do a manual transfer to a address/wallet that is whitelisted by the governance contract/address
	 * @param _targetToken address of the token to manually distriuted
	 * @param _amount amount of the _targetToken
	 * @param _destination destination address that will receive the token
	 */
	function manualDistributionTo(
		address _targetToken,
		uint256 _amount,
		address _destination
	) external onlySupport {
		/**
		 * context: even though the manager role will be a trusted signer, we do not want that that it is possible for this role to steal funds. Therefor the manager role can only manually transfer funds to a wallet that is whitelisted. On this whitelist only multi-sigs and governance controlled treasury wallets should be added.
		 */
		require(
			whitelistedDestinations[_destination],
			"FeeCollector: Destination not whitelisted"
		);
		SafeERC20.safeTransfer(IERC20(_targetToken), _destination, _amount);
		emit ManualDistributionManager(_targetToken, _amount, _destination);
	}

	/*==================== View functions *====================*/

	/**
	 * @notice calculates what is a percentage portion of a certain input
	 * @param _amountToDistribute amount to charge the fee over
	 * @param _basisPointsPercentage basis point percentage scaled 1e4
	 * @return amount_ amount to distribute
	 */
	function calculateDistribution(
		uint256 _amountToDistribute,
		uint64 _basisPointsPercentage
	) public pure returns (uint256 amount_) {
		amount_ = ((_amountToDistribute * _basisPointsPercentage) / BASIS_POINTS_DIVISOR);
	}

	/**
	 * @notice governance function to rescue or correct any tokens that end up in this contract by accident
	 * @dev this is a timelocked function! Only the timelock contract can call this function
	 * @param _tokenAddress address of the token to be transferred out
	 * @param _amount amount of the token to be transferred out
	 * @param _recipient address of the receiver of the token
	 */
	function removeTokenByGoverance(
		address _tokenAddress,
		uint256 _amount,
		address _recipient
	) external onlyTimelockGovernance {
		SafeERC20.safeTransfer(IERC20(_tokenAddress), timelockAddressImmutable, _amount);
		emit TokenTransferredByTimelock(_tokenAddress, _recipient, _amount);
	}

	/**
	 * @notice emergency function that transfers all the tokens in this contact to the timelock contract.
	 * @dev this function should be called when there is an exploit or a key of one of the manager is exposed
	 */
	function emergencyDistributionToTimelock() external onlyTeam {
		// address[] memory wlTokens_ = allWhitelistedTokensFeeCollector;
		// iterate over all te tokens that now sit in this contract
		for (uint256 i = 0; i < allWhitelistedTokensSet.length(); ++i) {
			address token_ = allWhitelistedTokensSet.at(i);
			uint256 bal_ = IERC20(token_).balanceOf(address(this));
			if (bal_ == 0) {
				// no balance to swipe, so proceed to next interations
				continue;
			}
			SafeERC20.safeTransfer(IERC20(token_), timelockAddressImmutable, bal_);
			emit EmergencyWithdraw(
				msg.sender,
				token_,
				bal_,
				address(timelockAddressImmutable)
			);
		}
	}

	/**
	 * @notice function distributes all the accumulated/realized fees to the different destinations
	 * @dev this function does not collect fees! only distributes fees that are already in the feecollector contract
	 */
	function distributeAll() external onlySupport {
		_transferBuyBackAndBurn();
		_transferWinrStaking();
		_transferWlpRewards();
		_transferCore();
		_transferReferral();
		_transferLuckyStrikeContract();
	}

	// transfer the wlp tokens to the luckystrike contract
	function transferToLuckyStrikeContract() public onlySupport {
		if (!_checkLastTime(lastDistributionTimes.luckyStrikePot)) {
			// we return early, since the last time the winr staking was called was less than the reward interval
			return;
		}
		lastDistributionTimes.luckyStrikePot = block.timestamp;
		_transferLuckyStrikeContract();
	}

	function _transferLuckyStrikeContract() internal {
		// collected fees can only be distributed once every rewardIntervval
		uint256 amount_ = reserves.luckyStrikePot;
		reserves.luckyStrikePot = 0;
		if (amount_ == 0) {
			return;
		}
		wlp.transfer(addresses.luckyStrikePot, amount_);
		emit TransferLuckyStrikeTokens(addresses.luckyStrikePot, amount_);
	}

	function returnAmountWlpForLuckyStrike() external view returns (uint256) {
		return reserves.luckyStrikePot;
	}

	/**
	 * @notice function that transfers the accumulated fees to the configured buyback contract
	 */
	function transferBuyBackAndBurn() public onlySupport {
		_transferBuyBackAndBurn();
	}

	function _transferBuyBackAndBurn() internal {
		// collected fees can only be distributed once every rewardIntervval
		if (!_checkLastTime(lastDistributionTimes.buybackAndBurn)) {
			// we return early, since the last time the winr staking was called was less than the reward interval
			return;
		}
		lastDistributionTimes.buybackAndBurn = block.timestamp;
		uint256 amount_ = reserves.buybackAndBurn;
		reserves.buybackAndBurn = 0;
		if (amount_ == 0) {
			return;
		}
		wlp.transfer(addresses.buybackAndBurn, amount_);
		emit TransferBuybackAndBurnTokens(addresses.buybackAndBurn, amount_);
	}

	/**
	 * @notice function that transfers the accumulated fees to the configured core/dev contract destination
	 */
	function transferCore() public onlySupport {
		_transferCore();
	}

	function _transferCore() internal {
		// collected fees can only be distributed once every rewardIntervval
		if (!_checkLastTime(lastDistributionTimes.core)) {
			// we return early, since the last time the winr staking was called was less than the reward interval
			return;
		}
		lastDistributionTimes.core = block.timestamp;
		uint256 amount_ = reserves.core;
		reserves.core = 0;
		if (amount_ == 0) {
			return;
		}
		wlp.transfer(addresses.core, amount_);
		emit TransferCoreTokens(addresses.core, amount_);
	}

	/**
	 * @notice function that transfers the accumulated fees to the configured wlp contract destination
	 */
	function transferWlpRewards() public onlySupport {
		// collected fees can only be distributed once every rewardIntervval
		if (!_checkLastTime(lastDistributionTimes.wlpClaim)) {
			// we return early, since the last time the winr staking was called was less than the reward interval
			return;
		}
		lastDistributionTimes.wlpClaim = block.timestamp;
		_transferWlpRewards();
	}

	/**
	 * @param _token address of the token fees will be withdrawn for
	 */
	function manualWithdrawFeesFromVault(address _token) external onlyTeam {
		IVault vault_ = vault;
		(uint256 swapReserve_, uint256 wagerReserve_, uint256 referralReserve_) = vault_
			.withdrawAllFees(_token);
		emit ManualFeeWithdraw(_token, swapReserve_, wagerReserve_, referralReserve_);
	}

	function collectFeesOnLotteryWin() external onlySupport {
		// withdraw fees from the vault and register/distribute the fees to according to the distribution ot all destinations
		_withdrawAllFees();
		// transfer the wlp rewards to the wlp claim contract
		_transferLuckyStrikeContract();
		// todo here it needs to be transferred only to the lottery contract!
		// note we do not the other tokens of the partition
	}

	function collectFeesBeforeLPEvent() external {
		require(
			msg.sender == address(wlpManager),
			"Only WLP Manager can call this function"
		);
		// withdraw fees from the vault and register/distribute the fees to according to the distribution ot all destinations
		_withdrawAllFees();
		// transfer the wlp rewards to the wlp claim contract
		_transferWlpRewards();
		// note we do not the other tokens of the partition
	}

	/**
	 * @notice configure if it is preferred the FC fails tx's when collecfions are collected within time interval
	 */
	function setFailOnTime(bool _setting) external onlyGovernance {
		failOnTime = _setting;
	}

	/**
	 * @notice internal function that transfers the accumulated wlp fees to the wlp token contract and realizes the fees
	 */
	function _transferWlpRewards() internal {
		uint256 amount_ = reserves.wlpHolders;
		reserves.wlpHolders = 0;
		if (amount_ == 0) {
			return;
		}
		// transfer the wlp rewards to the wlp token contract
		wlp.transfer(addresses.wlpClaim, amount_);
		// call the update funds received function so that the transferred wlp tokens will be attributed to liquid wlp holders
		IBasicFDT(addresses.wlpClaim).updateFundsReceived_WLP();
		// for good measure we also call the vwinr rewards distribution (so that the wlp claim contract can also attribute the vwinr rewards)
		IBasicFDT(addresses.wlpClaim).updateFundsReceived_VWINR();
		// Since the wlp distributor calls the function no need to do anything
		emit TransferWLPRewardTokens(addresses.wlpClaim, amount_);
	}

	/**
	 * @notice transfer the winr staking reward to the desination vwinr staking contract for claiming
	 * @notice the destination address is the Token Manager contract
	 * @notice checks if the total weight is 0, if so, does not transfer
	 */
	function transferWinrStaking() public onlySupport {
		_transferWinrStaking();
	}

	function _transferWinrStaking() internal {
		// collected fees can only be distributed once every rewardIntervval
		if (!_checkLastTime(lastDistributionTimes.winrStaking)) {
			// we return early, since the last time the winr staking was called was less than the reward interval
			return;
		}
		lastDistributionTimes.winrStaking = block.timestamp;

		uint256 amount_ = reserves.staking;
		reserves.staking = 0;
		if (amount_ == 0) {
			return;
		}
		if (winrStaking.totalWeight() == 0) {
			return;
		}
		wlp.transfer(addresses.tokenManager, amount_);
		// call winrStaking.share with amount
		ITokenManager(addresses.tokenManager).share(amount_);
		emit TransferWinrStakingTokens(addresses.tokenManager, amount_);
	}

	/**
	 * @notice transfer the referral reward to the desination referral contract for distribution and cliaming
	 */
	function transferReferral() public onlySupport {
		_transferReferral();
	}

	function _transferReferral() internal {
		// collected fees can only be distributed once every rewardIntervval
		if (!_checkLastTime(lastDistributionTimes.referral)) {
			// we return early, since the last time the referral was called was less than the reward interval
			return;
		}
		lastDistributionTimes.referral = block.timestamp;
		// all the swap and wager fees from the vault now sit in this contract
		// address[] memory wlTokens_ = allWhitelistedTokensFeeCollector;
		// iterate over all te tokens that now sit in this contract
		for (uint256 i = 0; i < allWhitelistedTokensSet.length(); ++i) {
			address token_ = allWhitelistedTokensSet.at(i);
			uint256 amount_ = referralReserve[token_];
			referralReserve[token_] = 0;
			if (amount_ != 0) {
				IERC20(token_).transfer(addresses.referral, amount_);
				emit TransferReferralTokens(token_, addresses.referral, amount_);
			}
		}
	}

	/**
	 * @notice function to be used when for some reason the balances are incorrect, need to be corrected manually
	 * @dev the function is timelocked via a gov timelock so is extremely hard to abuse at short notice
	 */
	function setReserveByTimelockGov(
		uint256 _wlpHolders,
		uint256 _staking,
		uint256 _buybackAndBurn,
		uint256 _core,
		uint256 _luckyStrikePot
	) external onlyTimelockGovernance {
		reserves = Reserve(_wlpHolders, _staking, _buybackAndBurn, _core, _luckyStrikePot);
	}

	/*==================== Internal functions *====================*/

	/**
	 * @notice internal function that calls the vault and withdraws all the fees
	 */
	function _withdrawAllFees() internal {
		// all the swap and wager fees from the vault now sit in this contract
		// address[] memory wlTokens_ = allWhitelistedTokensFeeCollector;
		// iterate over all te tokens that now sit in this contract
		for (uint256 i = 0; i < allWhitelistedTokensSet.length(); ++i) {
			_withdraw(allWhitelistedTokensSet.at(i));
		}
	}

	function _checkLastTime(uint256 _lastTime) internal view returns (bool) {
		// if true, it means a distribution can be done, since the current time is greater than the last time + the reward interval
		bool outsideInterval_ = _lastTime + rewardInterval <= block.timestamp;
		if (failOnTime) {
			require(
				outsideInterval_,
				"Fees can only be transferred once per rewardInterval"
			);
		}
		return outsideInterval_;
	}

	/**
	 * @notice internal withdraw function
	 * @param _token address of the token to be distributed
	 */
	function _withdraw(address _token) internal {
		IVault vault_ = vault;
		(uint256 swapReserve_, uint256 wagerReserve_, uint256 referralReserve_) = vault_
			.withdrawAllFees(_token);
		if (swapReserve_ != 0) {
			uint256 swapWlpAmount_ = _addLiquidity(_token, swapReserve_);
			// distribute the farmed swap fees to the addresses tat
			_setAmountsForSwap(swapWlpAmount_);
		}
		if (wagerReserve_ != 0) {
			uint256 wagerWlpAmount_ = _addLiquidity(_token, wagerReserve_);
			_setAmountsForWager(wagerWlpAmount_);
		}
		if (referralReserve_ != 0) {
			referralReserve[_token] += referralReserve_;
		}
	}

	/**
	 * @notice internal function that deposits tokens and returns amount of wlp
	 * @param _token token address of amount which wants to deposit
	 * @param _amount amount of the token collected (FeeCollector contract)
	 * @return wlpAmount_ amount of the token minted to this by depositing
	 */
	function _addLiquidity(
		address _token,
		uint256 _amount
	) internal returns (uint256 wlpAmount_) {
		IERC20(_token).approve(address(wlpManager), _amount);
		wlpAmount_ = wlpManager.addLiquidityFeeCollector(_token, _amount, 0, 0);
		return wlpAmount_;
	}

	/**
	 * @notice internal function that calculates how much of each asset accumulated in the contract need to be distributed to the configured contracts and set
	 * @param _amount amount of the token collected by swap in this (FeeCollector contract)
	 */
	function _setAmountsForSwap(uint256 _amount) internal {
		reserves.wlpHolders += calculateDistribution(
			_amount,
			swapDistributionConfig.wlpHolders
		);
		reserves.staking += calculateDistribution(_amount, swapDistributionConfig.staking);
		reserves.buybackAndBurn += calculateDistribution(
			_amount,
			swapDistributionConfig.buybackAndBurn
		);
		reserves.core += calculateDistribution(_amount, swapDistributionConfig.core);
	}

	/**
	 * @notice internal function that calculates how much of each asset accumulated in the contract need to be distributed to the configured contracts and set
	 * @param _amount amount of the token collected by wager in this (FeeCollector contract)
	 */
	function _setAmountsForWager(uint256 _amount) internal {
		reserves.staking += calculateDistribution(_amount, wagerDistributionConfig.staking);
		reserves.buybackAndBurn += calculateDistribution(
			_amount,
			wagerDistributionConfig.buybackAndBurn
		);
		reserves.core += calculateDistribution(_amount, wagerDistributionConfig.core);
		reserves.luckyStrikePot += calculateDistribution(
			_amount,
			wagerDistributionConfig.luckyStrikePot
		);
	}

	/**
	 * @notice internal function that checks if an address is not 0x0
	 */
	function _checkNotNull(address _setAddress) internal pure {
		require(_setAddress != address(0x0), "FeeCollector: Null not allowed");
	}
}

