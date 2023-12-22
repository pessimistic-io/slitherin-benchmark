// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import "./OwnableUpgradeable.sol";

import { IGMXRewardRouterV2 } from "./IGMXRewardRouterV2.sol";
import { IGMXRewardTracker } from "./IGMXRewardTracker.sol";
import { IVestaGMXStaking } from "./IVestaGMXStaking.sol";
import { TransferHelper, IERC20 } from "./TransferHelper.sol";
import { FullMath } from "./FullMath.sol";
import { IPriceFeedV2 } from "./IPriceFeedV2.sol";

contract VestaGLPStaking is IVestaGMXStaking, OwnableUpgradeable {
	uint256 private constant PRECISION = 1e27;
	bool private reentrancy;

	address public vestaTreasury;
	address public sGLP;

	IGMXRewardRouterV2 public gmxRewardRouterV2;
	IGMXRewardTracker public feeGlpTrackerRewards; //fsGLP

	uint256 public baseTreasuryFee;
	uint256 public rewardShare;

	uint256 public lastBalance;
	uint256 public totalStaked;

	mapping(address => bool) internal operators;
	mapping(address => uint256) internal stakes;
	mapping(address => uint256) internal userShares;

	uint256 constant BPS = 10_000;
	uint256 constant YEARLY = 31_536_000; //86400 * 365

	IGMXRewardTracker public constant fGLP =
		IGMXRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);

	IPriceFeedV2 public priceFeed;

	bool public useStaticFee;
	bool public newFeeFlow;
	uint256 public failedToSend;

	mapping(address => uint256) private recoverableETH;

	modifier onlyOperator() {
		if (!operators[msg.sender]) revert CallerIsNotAnOperator(msg.sender);
		_;
	}

	modifier onlyNonZero(uint256 _amount) {
		if (_amount == 0) revert ZeroAmountPassed();
		_;
	}

	modifier onlyActiveAddress(address _addr) {
		if (_addr == address(0)) revert InvalidAddress();
		_;
	}

	modifier onlyContract(address _address) {
		if (_address.code.length == 0) revert InvalidAddress();
		_;
	}

	modifier noReentrancy() {
		if (reentrancy) revert ReentrancyDetected();
		reentrancy = true;
		_;
		reentrancy = false;
	}

	function setUp(
		address _vestaTreasury,
		address _sGLP,
		address _gmxRewardRouterV2,
		address _feeGlpTrackerRewards
	)
		external
		onlyActiveAddress(_vestaTreasury)
		onlyActiveAddress(_sGLP)
		onlyActiveAddress(_gmxRewardRouterV2)
		onlyActiveAddress(_feeGlpTrackerRewards)
		initializer
	{
		__Ownable_init();

		vestaTreasury = _vestaTreasury;
		sGLP = _sGLP;
		gmxRewardRouterV2 = IGMXRewardRouterV2(_gmxRewardRouterV2);
		feeGlpTrackerRewards = IGMXRewardTracker(_feeGlpTrackerRewards);

		baseTreasuryFee = 2_000; // 20% in BPS
	}

	function stake(address _behalfOf, uint256 _amount)
		external
		override
		onlyOperator
		onlyActiveAddress(_behalfOf)
		onlyNonZero(_amount)
		noReentrancy
	{
		_harvest(_behalfOf);

		TransferHelper.safeTransferFrom(sGLP, msg.sender, address(this), _amount);

		uint256 userStaked = stakes[_behalfOf] += _amount;

		totalStaked += _amount;

		userShares[_behalfOf] = FullMath.mulDivRoundingUp(
			userStaked,
			rewardShare,
			PRECISION
		);

		emit StakingUpdated(totalStaked);
	}

	function claim() external override noReentrancy {
		if (stakes[msg.sender] == 0) revert InsufficientStakeBalance();
		_unstake(msg.sender, 0, msg.sender);
	}

	function unstake(address _behalfOf, uint256 _amount)
		external
		override
		onlyOperator
		noReentrancy
	{
		_unstake(_behalfOf, _amount, msg.sender);
	}

	function forceExiting(address _user) external onlyOwner {
		//Send back to ActivePool https://arbiscan.io/address/0xBE3dE7fB9Aa09B3Fa931868Fb49d5BA5fEe2eBb1
		_unstake(_user, stakes[_user], 0xBE3dE7fB9Aa09B3Fa931868Fb49d5BA5fEe2eBb1);
	}

	function _unstake(
		address _behalfOf,
		uint256 _amount,
		address _receiver
	) internal {
		if (totalStaked < _amount || stakes[_behalfOf] < _amount) {
			revert InsufficientStakeBalance();
		}
		_harvest(_behalfOf);
		uint256 userStaked = stakes[_behalfOf] -= _amount;

		if (_amount != 0) {
			uint256 withdrawalAmount = totalStaked < _amount ? totalStaked : _amount;
			totalStaked -= withdrawalAmount;
			TransferHelper.safeTransfer(sGLP, _receiver, _amount);
		}

		userShares[_behalfOf] = FullMath.mulDivRoundingUp(
			userStaked,
			rewardShare,
			PRECISION
		);

		emit StakingUpdated(totalStaked);
	}

	function _harvest(address _behalfOf) internal {
		gmxRewardRouterV2.handleRewards(true, true, true, true, true, true, true);

		if (totalStaked > 0) {
			rewardShare += FullMath.mulDiv(
				getBalance() - lastBalance,
				PRECISION,
				totalStaked
			);
		}

		uint256 last = userShares[_behalfOf];
		uint256 curr = FullMath.mulDiv(stakes[_behalfOf], rewardShare, PRECISION);

		if (curr > last) {
			uint256 totalReward = curr - last;

			(bool success, ) = _behalfOf.call{ value: totalReward }("");
			if (!success) {
				recoverableETH[_behalfOf] += totalReward;
				emit FailedToSendETH(_behalfOf, totalReward);
			}
		}

		lastBalance = getBalance();
	}

	function recoverETH() external {
		uint256 toUser = recoverableETH[msg.sender];
		recoverableETH[msg.sender] = 0;

		require(toUser > 0, "Nothing to recover.");

		(bool success, ) = msg.sender.call{ value: toUser }("");
		if (!success) {
			revert ETHTransferFailed(msg.sender, toUser);
		}
	}

	function setOperator(address _address, bool _enabled)
		external
		onlyContract(_address)
		onlyOwner
	{
		operators[_address] = _enabled;
	}

	function setPriceFeed(address _priceFeed) external onlyOwner {
		priceFeed = IPriceFeedV2(_priceFeed);
	}

	function setBaseTreasuryFee(uint256 _sharesBPS) external onlyOwner {
		if (_sharesBPS > BPS) revert BPSHigherThanOneHundred();
		if (!useStaticFee && _sharesBPS > 2_000) revert FeeTooHigh();

		baseTreasuryFee = _sharesBPS;
	}

	function setTreasury(address _newTreasury) external onlyOwner {
		vestaTreasury = _newTreasury;
	}

	function enableStaticTreasuryFee(bool _enabled) external onlyOwner {
		useStaticFee = _enabled;

		if (!_enabled && baseTreasuryFee > 2_000) {
			baseTreasuryFee = 2_000;
		}
	}

	function applyNewFeeFlow() external onlyOwner {
		require(!newFeeFlow, "Function already called");
		newFeeFlow = true;

		_payTreasuryFee(address(this).balance);
		lastBalance = address(this).balance;
	}

	function treasuryFee() public view override returns (uint256 feeBPS_) {
		if (useStaticFee) return baseTreasuryFee;

		uint256 interval = fGLP.tokensPerInterval();
		uint256 totalSupply = feeGlpTrackerRewards.totalSupply();
		uint256 ethPrice = priceFeed.getExternalPrice(address(0));
		uint256 glpPrice = priceFeed.getExternalPrice(sGLP);

		feeBPS_ = ((YEARLY * interval * ethPrice) * BPS) / (totalSupply * glpPrice);

		return
			(feeBPS_ <= 2500)
				? baseTreasuryFee
				: BPS - ((baseTreasuryFee * BPS) / feeBPS_);
	}

	function retrySendTreasuryFund() external onlyOwner {
		uint256 toTreasury = failedToSend;
		failedToSend = 0;

		(bool success, ) = vestaTreasury.call{ value: toTreasury }("");
		if (!success) {
			revert ETHTransferFailed(vestaTreasury, toTreasury);
		}
	}

	function setFeeGlpTrackerReward(address _feeTracker) external onlyOwner {
		feeGlpTrackerRewards = IGMXRewardTracker(_feeTracker);
	}

	function getVaultStake(address _vaultOwner)
		external
		view
		override
		returns (uint256)
	{
		return stakes[_vaultOwner];
	}

	function getVaultOwnerShare(address _vaultOwner)
		external
		view
		override
		returns (uint256)
	{
		return userShares[_vaultOwner];
	}

	function getVaultOwnerClaimable(address _vaultOwner)
		external
		view
		returns (uint256)
	{
		uint256 claimableReward = feeGlpTrackerRewards.claimable(address(this));
		claimableReward -= FullMath.mulDiv(claimableReward, treasuryFee(), BPS);

		uint256 totalFutureBalance = getBalance() + claimableReward;
		uint256 futureRewardShare = rewardShare;

		if (totalStaked > 0) {
			futureRewardShare += FullMath.mulDiv(
				totalFutureBalance - lastBalance,
				PRECISION,
				totalStaked
			);
		}

		uint256 last = userShares[_vaultOwner];
		uint256 curr = FullMath.mulDiv(
			stakes[_vaultOwner],
			futureRewardShare,
			PRECISION
		);

		if (curr > last) {
			return curr - last;
		}

		return 0;
	}

	function getBalance() public view returns (uint256) {
		return address(this).balance - failedToSend;
	}

	function getRecoverableETH(address _user)
		external
		view
		override
		returns (uint256)
	{
		return recoverableETH[_user];
	}

	function isOperator(address _operator) external view override returns (bool) {
		return operators[_operator];
	}

	receive() external payable {
		_payTreasuryFee(msg.value);
		emit RewardReceived(msg.value);
	}

	function _payTreasuryFee(uint256 _rawRewards) internal {
		uint256 toTheTreasury = (((_rawRewards * PRECISION) * treasuryFee()) / BPS) /
			PRECISION;

		(bool success, ) = vestaTreasury.call{ value: toTheTreasury }("");
		if (!success) {
			failedToSend += toTheTreasury;
			emit FailedToSendETH(vestaTreasury, toTheTreasury);
		}
	}
}


