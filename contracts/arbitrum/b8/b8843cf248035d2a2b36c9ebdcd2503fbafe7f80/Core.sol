// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import { IAddressProvider } from "./IAddressProvider.sol";
import { IOracleMaster } from "./IOracleMaster.sol";
import "./CoreStorage.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "./SafeERC20Upgradeable.sol";

/**
 * @title HedgeCore Upgradable Contract for `gohm`
 * @author Entropyfi
 * @notice Main Core contract for `Soft Hedge & Leverage` protocol
 * - Users(EOA or WhitelistedContracts) can:
 *   # deposit
 *   # withdraw
 *   # swap
 *   # sponsor & sponsorWithdraw
 */
contract Core is ICore, Initializable, UUPSUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, CoreStorageV1 {
	using SafeERC20 for IERC20;

	modifier hedgeCoreAllowed() {
		require(hedgeCoreStatus(), "HC: LOCKED");
		_;
	}

	/**
	 * @dev initialize function for upgradable contract
	 * @param name_ name of this contract
	 * @param addressProvider_ addressProvider
	 * @param wToken_ wrapped token (gohm)
	 */
	function initialize(
		string memory name_,
		address addressProvider_,
		address wToken_
	) public initializer {
		// 1. param checks
		require(bytes(name_).length != 0, "HC:STR MTY!");
		require(IAddressProvider(addressProvider_).getDAO() != address(0), "HT:AP INV");
		require(IERC20(wToken_).totalSupply() > 0, "HC:G INV");

		// 2. inheritance contract init
		__UUPSUpgradeable_init();
		__Pausable_init();
		__ReentrancyGuard_init();

		// 3. assign parameters
		name = name_;
		addressProvider = IAddressProvider(addressProvider_);
		wToken = IERC20(wToken_);

		// 4. other init
		/// 4.1 for `withdrawAllWhenPaused`
		withdrawAllPaused = true;
		/// 4.2 restricted period. defualt is 4 hours (can be modified no bigger than 8hours)
		resctrictedPeriod = 14400;
		/// 4.3 price ratio (RATIO_PRECISION = 1E5, default is 2%)
		isPriceRatioUp = true;
		priceRatio = 2000;
		/// 4.4 min single side deposit amount
		minSingleSideDepositAmount = 1;
	}

	/**
	 * @dev [onlyDAO] we init critical settings and variables for rebase here
	 * @param hgeToken_ Hedge token (interest bearing token)
	 * @param levToken_ Leverage token (interest bearing token)
	 * @param sponsorToken_ Sponsor token (normal ERC20 token)
	 * @param lastRebaseTime_  set the last rebase begin time. (for rebase and price update)
	 */
	function initGnesisHedge(
		address hgeToken_,
		address levToken_,
		address sponsorToken_,
		uint256 lastRebaseTime_
	) public onlyDAO {
		// 1. para checks
		require(!initialized, "HC:INITED!");
		require(lastRebaseTime_ != 0, "HC: T INV");

		// 2. tokens
		hgeToken = IHedgeToken(hgeToken_);
		levToken = IHedgeToken(levToken_);
		sponsorToken = ISponsorToken(sponsorToken_);
		/// check tokens // cannot check if core address matches since the core address is the proxy address not address(this)
		hgeToken.index();
		levToken.index();
		sponsorToken.core();

		// 2 price and index fectch
		/// 2.1 price and index
		hedgeInfo.hedgeTokenPrice = wTokenPrice(); //(lastPrice is zero during the first warmup round)
		require(hedgeInfo.hedgeTokenPrice != 0, "HC:W P INV");
		currSTokenIndex = index();
		require(currSTokenIndex != 0, "HC:IDX INV");
		/// 2.2 timestamp (round 1 is warmup round since the initial price fectch is not at the `lastrebase time`)
		lastPriceUpdateTimestamp = lastRebaseTime_;
		hedgeInfo.rebaseTime = lastRebaseTime_;

		// 3. finish initialization set it to true.
		initialized = true;
	}

	//---------------------------------- core logic for user interactions ---------------------//
	/**
	 * @notice deposit gOHM to soft hedge & leverage and get hgeToken and levToken
	 * @dev for frontend
	 */
	function deposit(uint256 hgeAmount_, uint256 levAmount_)
		public
		override
		nonReentrant
		onlyInitialized
		whenNotPaused
		hedgeCoreAllowed
		isEligibleSender
		minAmount(hgeAmount_, levAmount_)
	{
		_depositFor(msg.sender, hgeAmount_, levAmount_);
	}

	/**
	 * @notice caller depositFor depositFor `user_`.
	 */
	function depositFor(
		address user_,
		uint256 hgeAmount_,
		uint256 levAmount_
	) public override nonReentrant onlyInitialized whenNotPaused hedgeCoreAllowed isEligibleSender minAmount(hgeAmount_, levAmount_) {
		_depositFor(user_, hgeAmount_, levAmount_);
	}

	/**
	 * @notice withdraw gOHM
	 * @dev for frontend
	 */
	function withdraw(uint256 hgeAmount_, uint256 levAmount_)
		public
		override
		nonReentrant
		onlyInitialized
		whenNotPaused
		hedgeCoreAllowed
		isEligibleSender
	{
		_withdrawTo(msg.sender, hgeAmount_, levAmount_);
	}

	/**
	 * @notice caller withdrawTo withdrawTo `user_`.
	 */
	function withdrawTo(
		address recipent_,
		uint256 hgeAmount_,
		uint256 levAmount_
	) public override nonReentrant onlyInitialized whenNotPaused hedgeCoreAllowed isEligibleSender {
		_withdrawTo(recipent_, hgeAmount_, levAmount_);
	}

	/**
	 * @notice redeem back all available sVSQ after game paused
	 * @dev for user to exit the game completely after the game paused. All hgeToken and levToken of `msg.sender` will be burned
	 */
	function withdrawAllWhenPaused() public override nonReentrant onlyInitialized whenPaused onlyWithdrawAllNotPaused isEligibleSender {
		// 1. cal hge and lev and sponsor balance
		uint256 hgeBalance = hgeToken.balanceOf(msg.sender);
		uint256 levBalance = levToken.balanceOf(msg.sender);
		uint256 sponsorBalance = sponsorToken.balanceOf(msg.sender);

		// 2. withdraw all to user
		_withdrawTo(msg.sender, hgeBalance, levBalance);
		_sponsorWithraw(sponsorBalance);
	}

	/**
	 * @notice swap between soft hedge and soft leverage
	 */
	function swap(bool fromLongToShort_, uint256 amount_)
		public
		override
		nonReentrant
		onlyInitialized
		whenNotPaused
		hedgeCoreAllowed
		isEligibleSender
	{
		_swap(fromLongToShort_, amount_);
	}

	function sponsorDeposit(uint256 amount_)
		public
		override
		nonReentrant
		onlyInitialized
		whenNotPaused
		isEligibleSender
		minAmount(amount_, minSingleSideDepositAmount)
	{
		_sponsorDeposit(amount_);
	}

	function sponsorWithdraw(uint256 amount_) public override nonReentrant onlyInitialized whenNotPaused isEligibleSender {
		_sponsorWithraw(amount_);
	}

	function startNewHedge() public override nonReentrant onlyInitialized whenNotPaused onlyAfterRebase(index()) {
		_startNewHedge();
	}

	/**
	 * @dev record price every 8 hours. called by keeper. can only be called before rebase
	 */
	function updatePriceBeforeRebase() external override nonReentrant onlyInitialized whenNotPaused returns (uint256 price_) {
		require(!_isSTokenRebased(index()), "HC:REBASED!"); // make sure not rebased
		require(!isPriceUpdatedBeforeRebase(), "HC: P UPDATED"); // make sure price updated before rebase
		require(block.timestamp >= lastPriceUpdateTimestamp + 8 hours, "HC:P NOT READY");
		price_ = _updatePrice();
	}

	// ----------------------------- internal core functions-------------------------------//
	/**
	 * @dev `msg.sender` transfer `hgeAmount_ + levAmount_` of sToken to contract and mint `user_` hgeToken and levToken
	 * @param hgeAmount_ The amount of gohm user wishes to soft hedge
	 * @param levAmount_ The amount of gohm user wishes to soft leverage
	 */
	function _depositFor(
		address user_,
		uint256 hgeAmount_,
		uint256 levAmount_
	) internal {
		require(user_ != address(0), "HC:ADDR ZR");
		require(hgeAmount_ + levAmount_ != 0, "HC:AMNT ZR");

		// gohm is not feeOnTransfer token so no need to check pre and post balance
		wToken.safeTransferFrom(msg.sender, address(this), hgeAmount_ + levAmount_);

		// calc balance in sToken
		uint256 hgeBalance = balanceFromWToken(hgeAmount_);
		uint256 levBalance = balanceFromWToken(levAmount_);
		// mint user game token for LONG and SHORT
		if (hgeBalance != 0) {
			hgeToken.mint(user_, hgeBalance);
		}
		if (levBalance != 0) {
			levToken.mint(user_, levBalance);
		}

		// update mappings for user view earned profits
		userDeposited[user_] += hgeAmount_ + levAmount_;

		// emit deposit event and game status
		emit Deposited(user_, hgeAmount_, levAmount_);
	}

	/**
	 * @dev burn `msg.sender`'s hgeToken and levToken and transfer gohm to `recipient`
	 * @param recipient_ The address which receives withrawed sVSQ
	 * @param hgeAmount_ The amount of hgeToken needs to burn
	 * @param levAmount_ The amount of levToken needs to burn
	 */
	function _withdrawTo(
		address recipient_,
		uint256 hgeAmount_,
		uint256 levAmount_
	) internal {
		require(hgeAmount_ + levAmount_ != 0, "HC:AMNT ZR");
		require(recipient_ != address(0), "HC:ADDR ZR");

		// 1. burn user hge & lev token
		if (hgeAmount_ != 0) {
			hgeToken.burn(msg.sender, hgeAmount_);
		}
		if (levAmount_ != 0) {
			levToken.burn(msg.sender, levAmount_);
		}

		// 2. convert game token to sToken
		uint256 wrappedTokenBalance = balanceToWToken(hgeAmount_ + levAmount_);

		wToken.safeTransfer(recipient_, wrappedTokenBalance);

		// 3. update mappings for user view earned profits (rough calculation. reference only)
		// note we need to be careful of underflow since balance would increase and user might withdraw more than they initially deposit
		uint256 deposited = userDeposited[msg.sender];
		uint256 left;
		if (deposited > wrappedTokenBalance) {
			left = deposited - wrappedTokenBalance;
		}
		userDeposited[msg.sender] = left;

		// 4. emit withdraw event and game status
		emit Withdrawn(recipient_, hgeAmount_, levAmount_);
	}

	/**
	 * @dev swap between soft hedge & leverage. (burn and mint the corresponding hge/lev tokens)
	 * @param fromLongToShort_ swap options
	 * @param amount_ The swap amount (hedgeToken amount)
	 */
	function _swap(bool fromLongToShort_, uint256 amount_) internal {
		require(amount_ != 0, "HC:AMNT ZR");
		if (fromLongToShort_) {
			levToken.burn(msg.sender, amount_);
			hgeToken.mint(msg.sender, amount_);
		} else {
			hgeToken.burn(msg.sender, amount_);
			levToken.mint(msg.sender, amount_);
		}

		emit Swaped(msg.sender, fromLongToShort_, amount_);
	}

	/**
	 * @dev sponsor `amount_` of gohm (sponsor will not receive rewards)
	 * @param amount_ gohm amount
	 */
	function _sponsorDeposit(uint256 amount_) internal {
		require(amount_ != 0, "HC:AMNT ZR");
		wToken.safeTransferFrom(msg.sender, address(this), amount_);
		uint256 sTokenBalance = balanceFromWToken(amount_);

		// 2. mint same amount of sponsorToken
		sponsorToken.mint(msg.sender, sTokenBalance);

		// emit events
		emit Sponsored(msg.sender, amount_);
	}

	/**
	 * @dev withdraw `amount_` sponsored sToken (sponsor will not receive the rebase rewards)
	 * @param amount_ sponsorToken amount
	 */
	function _sponsorWithraw(uint256 amount_) internal {
		require(amount_ > 0, "HC:AMNT ZR");
		// 1. burn sponsor token
		sponsorToken.burn(msg.sender, amount_);

		// 2. transfer gohm to msg.sender
		uint256 wrappedTokenBalance = balanceToWToken(amount_);
		wToken.safeTransfer(msg.sender, wrappedTokenBalance);

		// 3. emit events
		emit SponsorWithdrawn(msg.sender, wrappedTokenBalance);
	}

	/**
	 * @dev triggered after sToken rebased. (only when both hedge and leverage sides exsit)
	 */
	function _startNewHedge() internal {
		require(hgeToken.totalSupply() > 0 && levToken.totalSupply() > 0, "HC:B NON ZR TS");
		bool isLev;

		// 1. fetch price and determines the result of current round
		// check if price updated. if not update price here.
		if (isPriceUpdatedBeforeRebase()) {
			require(hedgeInfo.lastPrice != 0, "HC: INV"); // not possible but extra check (lastPrice is zero during the first warmup round before price updated)
			isLev = isLevWin(isPriceRatioUp, hedgeInfo.lastPrice, hedgeInfo.hedgeTokenPrice);
		} else {
			// if prcie update not called by chainlink, update the price here.
			_updatePrice();
			isLev = isLevWin(isPriceRatioUp, hedgeInfo.lastPrice, hedgeInfo.hedgeTokenPrice);
		}

		// 2. calc the rebaseDistributeAmount. (part of the interest(loser side's) will be sent to gauge if the setting's on)
		// 2.1 calc rebase amount
		uint256 rebaseTotalAmount;
		uint256 oldAmount = hgeToken.totalSupply() + levToken.totalSupply() + sponsorToken.totalSupply();
		uint256 wrappedTokenBalance = wToken.balanceOf(address(this));
		uint256 sTokenBalance = balanceFromWToken(wrappedTokenBalance);
		if (sTokenBalance > oldAmount) {
			//// in case of underflow
			rebaseTotalAmount = sTokenBalance - oldAmount;
		}

		// 2.2 calc the toGauge amount. The amount is only deducted from the (loser+ sponsor) side's interest(rebase amount) so winner's rewards >= the regular rebase rewards
		uint256 toGauge;
		// fee on if both non zero
		if (toGaugeRatio != 0 && gauge != address(0)) {
			if (isLev) {
				toGauge =
					((rebaseTotalAmount * toGaugeRatio * (hgeToken.totalSupply() + sponsorToken.totalSupply())) / (oldAmount)) /
					RATIO_PRECISION;
			} else {
				toGauge =
					((rebaseTotalAmount * toGaugeRatio * (levToken.totalSupply() + sponsorToken.totalSupply())) / (oldAmount)) /
					RATIO_PRECISION;
			}
		}

		//// no fee if toGauge is zero
		if (toGauge != 0) {
			wToken.safeTransfer(gauge, balanceToWToken(toGauge));
		}

		uint256 rebaseDistributeAmount = rebaseTotalAmount - toGauge;

		// 3 start new game
		/// 3.1 update epoch and rebaseEndTime
		currSTokenIndex = index();
		/// update rebase time
		hedgeInfo.rebaseTime = block.timestamp;
		/// 3.2 update token indices
		_rebaseHedgeToken(isLev, rebaseDistributeAmount, rebaseTotalAmount);

		// 4. emit event
		emit HedgeLog(logs.length, isLev, rebaseTotalAmount);
	}

	/**
	 * @dev update token index for winning side and store some logs
	 * @param isLev_ true: soft lev win. false: soft hge win
	 * @param atualRebasedAmount_ actual rebase rebase reward being distributed to user
	 * @param totalRebasedAmount_ totalRebase rewards
	 */
	function _rebaseHedgeToken(
		bool isLev_,
		uint256 atualRebasedAmount_,
		uint256 totalRebasedAmount_
	) internal {
		Log memory currLog;
		// 1. record results (do not affect the core logic, just for result recording)
		currLog.isLev = isLev_;
		currLog.atualRebasedAmount = atualRebasedAmount_;
		currLog.totalRebasedAmount = totalRebasedAmount_;
		currLog.index = index();

		// 2. update token index
		if (isLev_) {
			// 2.1 if soft leverage win
			uint256 oldIdx = levToken.index();
			uint256 levIdx = oldIdx + (atualRebasedAmount_ * PRECISION) / levToken.rawTotalSupply();
			levToken.updateIndex(levIdx);
			currLog.tokenIdx = levIdx;
			logs.push(currLog);
			levRebaseCnt += 1;
		} else {
			// 2.2 if soft hedge win
			uint256 oldIdx = hgeToken.index();
			uint256 hgeIdx = oldIdx + (atualRebasedAmount_ * PRECISION) / hgeToken.rawTotalSupply();
			hgeToken.updateIndex(hgeIdx);
			currLog.tokenIdx = hgeIdx;
			logs.push(currLog);
			hedgeRebaseCnt += 1;
		}

		// 3. emit events
		emit Rebased(atualRebasedAmount_, totalRebasedAmount_);
	}

	function _updatePrice() internal returns (uint256 price_) {
		price_ = wTokenPrice();
		hedgeInfo.lastPrice = hedgeInfo.hedgeTokenPrice;
		hedgeInfo.hedgeTokenPrice = price_;
		hedgeInfo.cnt += 1; // equals to logs.length + 1
		lastPriceUpdateTimestamp = block.timestamp;
	}

	// ------------------------------------ADMIN / DAO---------------------------- //
	/**
	 * @dev onlyEmergencyAdmin can update implementation
	 */
	function _authorizeUpgrade(address) internal override onlyEmergencyAdmin {}

	function setWhiteListContract(address contract_, bool whitelisted_) external onlyDAO {
		whitelistedContracts[contract_] = whitelisted_;
	}

	/**
	 * @dev update toGauge address and ratio. The fee is activated when both are set correct. the fee is deducted from the loser' side rebase reward
	 * @param newGauge_ gauge address. set to address(0) to turn off fee
	 * @param ratio_ fee ratio. ratio is 10^5 precision. so 1000 => 1%. 20000 => 20%
	 */
	function updateGaugeAndRatio(address newGauge_, uint256 ratio_) external onlyDAO {
		gauge = newGauge_;
		require(ratio_ <= RATIO_PRECISION, "HC:R INV"); // <= 100%
		toGaugeRatio = ratio_;
	}

	/** @dev update price impact
	 *	@param newRatio_ no upper limit (0-100%)
	 */
	function updatePriceRatio(bool isUp_, uint256 newRatio_) external onlyDAO {
		require(newRatio_ <= RATIO_PRECISION, "HC:PR INV");
		priceRatio = newRatio_;
		isPriceRatioUp = isUp_;
	}

	/**
	 * @dev [onlyEmergencyAdmin] pause or unpause protocol
	 * @param paused_ true => pause, false => unpause
	 */
	function setPause(bool paused_) external onlyEmergencyAdmin {
		if (paused_) {
			_pause();
		} else {
			_unpause();
		}
	}

	/**
	 * @dev [onlyEmergencyAdmin] pause or unpause withdrawAll
	 * @param paused_ true => pause, false => unpause
	 */
	function setWithdrawAllPause(bool paused_) external onlyEmergencyAdmin {
		if (paused_) {
			// pause withdraw all
			require(!withdrawAllPaused, "HC:WA PAUSED");
		} else {
			// unpause withdraw all
			require(withdrawAllPaused, "HC:WA NOT PAUSED");
		}
		withdrawAllPaused = paused_;
	}

	/**
	 * @dev [onlyDAO] range 0-8hours => deposit available window (0 - 8 hours)
	 * @param value_ new restricted period
	 */
	function updateRestrictedPeriod(uint256 value_) external onlyDAO {
		require(value_ <= 8 hours, "HC:RP INV");
		resctrictedPeriod = value_;
	}

	/**
	 * @dev [onlyDAO] rescue leftover tokens and send them to DAO
	 * @param token_ reserve curreny
	 * @param amount_ amount of reserve token to transfer
	 */
	function rescueTokens(address token_, uint256 amount_) external onlyDAO whenPaused {
		IERC20(token_).safeTransfer(msg.sender, amount_);
	}

	function setSingleSideMinDepositAmount(uint256 minAmount_) external onlyDAO {
		minSingleSideDepositAmount = minAmount_;
	}

	//--------------------------- view / pure --------------------------------

	/**
	 * @notice fetch index. data source is chainlink oracle
	 * @dev get from oracle master and the mapping entry is set to the chainlink aggregator address
	 */
	function index() public view returns (uint256) {
		address oracleMaster = addressProvider.getOracleMaster();
		return IOracleMaster(oracleMaster).queryInfo(0x48C4721354A3B29D80EF03C65E6644A37338a0B1); //use chainlink ohm index aggregator address (on arbitrum)
	}

	/**
	 * @notice gohm => ohm balance
	 * @param amount_ gohm amount
	 * @return ohm/sohm amount
	 */
	function balanceFromWToken(uint256 amount_) public view returns (uint256) {
		return (amount_ * (index())) / (10**9);	// gOHM - 18, index - 9 => sToken -> 18
	}

	/**
	 * @notice ohm => gohm balance
	 * @param amount_ ohm/sohm amount
	 * @return gohm amount
	 */
	function balanceToWToken(uint256 amount_) public view returns (uint256) {
		return (amount_ * (10**9)) / (index());
	}

	/**
	 * @notice gohm price.
	 */
	function wTokenPrice() public view returns (uint256) {
		address oracleMaster = addressProvider.getOracleMaster();
		return IOracleMaster(oracleMaster).queryInfo(address(wToken));
	}

	function priceAfterRatio() external view returns (uint256 price_) {
		return _priceAfterRatio(isPriceRatioUp, hedgeInfo.hedgeTokenPrice);
	}

	/**
	 * @notice get the (1 + ratio)% price
	 */
	function _priceAfterRatio(bool up_, uint256 originPrice_) internal view returns (uint256 price_) {
		uint256 deltaPrice = (originPrice_ * priceRatio) / RATIO_PRECISION;
		if (up_) {
			price_ = originPrice_ + deltaPrice;
		} else {
			price_ = originPrice_ - deltaPrice;
		}
	}

	/**
	 * @notice check if current round price fetched
	 * if updated before rebase. the priceCnt = logs.length(rebase cnt) + 1
	 * if updated after rebase or not updated before rebase. the priceCnt = rebaseCnt
	 */
	function isPriceUpdatedBeforeRebase() public view returns (bool updated) {
		uint256 rebaseCnt = logs.length;
		uint256 priceCnt = hedgeInfo.cnt;
		if (priceCnt == rebaseCnt + 1) {
			updated = true;
		}
	}

	/**
	 * @notice check if lev win. (>=: lev, <: hedge)
	 */
	function isLevWin(
		bool ispriceRatioUp_,
		uint256 lastPrice_,
		uint256 currPrice_
	) public view returns (bool isLev_) {
		if (currPrice_ >= _priceAfterRatio(ispriceRatioUp_, lastPrice_)) {
			isLev_ = true;
		}
	}

	/**
	 * @notice true: deposit open. false: deposit close
	 * @dev 2 & 3 is not likely to happen but tripple check
	 *		1. in allowed period,
	 * 		2. price updated is not called.
	 *		3. before rebased
	 */
	function hedgeCoreStatus() public view override returns (bool isUnlocked_) {
		bool isInAllowedPriod;
		bool isCurrentRoundPriceUpdated;
		bool isRebased;

		isInAllowedPriod = (block.timestamp <= hedgeInfo.rebaseTime + resctrictedPeriod) ? true : false;
		isCurrentRoundPriceUpdated = isPriceUpdatedBeforeRebase();
		isRebased = _isSTokenRebased(index());

		isUnlocked_ = isInAllowedPriod && (!isCurrentRoundPriceUpdated) && (!isRebased);
	}

	/**
	 * @notice check if sToken rebase since last time
	 */
	function isSTokenRebased() external view override returns (bool) {
		return _isSTokenRebased(index());
	}

	function _isSTokenRebased(uint256 index_) internal view returns (bool) {
		return index_ > currSTokenIndex ? true : false;
	}

	/**
	 * @notice view your earned profits
	 * @dev for user view and reference only! might not be accurate if user transfer their hge/lev tokens
	 * @param user_ user address
	 * @return earnedProfit_ earned profit for `user_`
	 */
	function earnedProfit(address user_) external view returns (uint256 earnedProfit_) {
		uint256 totalBalance = hgeToken.balanceOf(user_) + levToken.balanceOf(user_);
		uint256 totalBalanceInWrappedToken = balanceToWToken(totalBalance);
		uint256 userDepositedAmount = userDeposited[user_];
		if (totalBalanceInWrappedToken >= userDepositedAmount) {
			// in case of underflow since user might transfer token themselves
			earnedProfit_ = totalBalanceInWrappedToken - userDepositedAmount;
		}
	}

	function logsLen() external view returns (uint256) {
		return logs.length;
	}

	/**
	 * @notice return last n rounds result in an array. results array start from old result to new results
	 * @param n_ number of results you wish to fectch.
	 */
	function fetchLastNRoundsResults(uint256 n_) external view returns (bool[] memory results_) {
		n_ = (n_ > logs.length) ? logs.length : n_;
		results_ = new bool[](n_);
		for (uint256 i = 0; i < n_; i++) {
			results_[i] = logs[logs.length - n_ + i].isLev;
		}
	}
}

