// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ReentrancyGuardUpgradeable.sol";
import "./IERC3525.sol";
import "./ISFTIssuableDelegate.sol";
import "./IMultiRechargeableDelegate.sol";
import "./ISFTMintableDelegate.sol";
import "./ResolverCache.sol";
import "./Constants.sol";
import "./ERC20TransferHelper.sol";
import "./ISFTDelegateControl.sol";
import "./UnderwriterProfitConcrete.sol";
import "./IssueMarketStorage.sol";
import "./IIssueMarket.sol";
import "./IPriceStrategyManager.sol";
import "./IWhitelistStrategyManager.sol";

contract IssueMarket is IIssueMarket, IssueMarketStorage, ReentrancyGuardUpgradeable, ResolverCache {
	using EnumerableSet for EnumerableSet.Bytes32Set;

	function initialize(address resolver_, address owner_) external initializer {
		__OwnControl_init(owner_);
		__ReentrancyGuard_init();
		__ResolverCache_init(resolver_);
	}

	struct IssueVars {
		InputIssueInfo inputIssueInfo;
		bytes32 issueKey;
		bytes32 underwriterKey;
	}
	
	function issue(address sft_, address currency_, bytes calldata inputSlotInfo_, bytes calldata inputIssueInfo_, 
        bytes calldata inputPriceInfo_) external payable override nonReentrant returns (uint256 slot_) {
		IssueVars memory vars;
		vars.inputIssueInfo = abi.decode(inputIssueInfo_, (InputIssueInfo));
		require(currencies[currency_], "IssueMarket: currency not supported");
		require(sftInfos[sft_].isValid, "IssueMarket: sft not supported");
		require(sftInfos[sft_].issuer == address(0) || sftInfos[sft_].issuer == _msgSender(), "IssueMarket: not issuer");
		_validateInputIssueInfo(vars.inputIssueInfo, inputPriceInfo_);

		slot_ = ISFTIssuableDelegate(sft_).createSlotOnlyIssueMarket(_msgSender(), inputSlotInfo_);
		vars.issueKey = _getIssueKey(sft_, slot_);

		PurchaseLimitInfo memory purchaseLimitInfo = PurchaseLimitInfo({
			min: vars.inputIssueInfo.min,
			max: vars.inputIssueInfo.max,
			startTime: vars.inputIssueInfo.startTime,
			endTime: vars.inputIssueInfo.endTime,
			useWhitelist: vars.inputIssueInfo.whitelist.length > 0 ? true : false
		});

		IssueInfo memory issueInfo = IssueInfo({
			issuer: _msgSender(),
			sft: sft_,
			slot: slot_,
			currency: currency_,
			issueQuota: vars.inputIssueInfo.issueQuota,
			value: vars.inputIssueInfo.issueQuota,
			receiver: vars.inputIssueInfo.receiver,
			purchaseLimitInfo: purchaseLimitInfo,
			priceType: vars.inputIssueInfo.priceType,
			status: IssueStatus.ISSUING
		});
		
		issueInfos[vars.issueKey] = issueInfo;

		for (uint256 i = 0; i < vars.inputIssueInfo.underwriters.length; i++) {
			string memory underwriterName = vars.inputIssueInfo.underwriters[i];
			vars.underwriterKey = _getUnderwriterKey(underwriterName);
			require(underwriterInfos[vars.underwriterKey].isValid, "IssueMarket: underwriters not supported");
			UnderwriterIssueInfo memory underwriterIssueInfo = UnderwriterIssueInfo({
					name: underwriterName,
					quota: vars.inputIssueInfo.quotas[i],
					value: vars.inputIssueInfo.quotas[i]
				});
			underwriterIssueInfos[vars.underwriterKey][vars.issueKey] = underwriterIssueInfo;
		} 

		priceInfos[vars.issueKey] = inputPriceInfo_;

		_whitelistStrategyManager().setWhitelist(vars.issueKey, vars.inputIssueInfo.whitelist);

		emit Issue(sft_, slot_, issueInfo, issueInfo.priceType, inputPriceInfo_, vars.inputIssueInfo.underwriters, vars.inputIssueInfo.quotas);
	}

	struct SubscribeVars {
		address buyer;
		SFTInfo sftInfo;
		bytes32 issueKey;
		bytes32 underwriterKey;
		uint256 price;
		uint256 issueFee;
		uint256 underwriterFee;
		uint256 tokenId;
		uint256 payment;
	}
	function subscribe(address sft_, uint256 slot_, string calldata underwriter_, uint256 value_, uint64 expireTime_) external payable override nonReentrant returns (uint256, uint256) {
		SubscribeVars memory vars;
		require(expireTime_ > block.timestamp, "IssueMarket: expired");

		vars.sftInfo = sftInfos[sft_];
		require(vars.sftInfo.isValid, "IssueMarket: sft not supported");

		vars.buyer = _msgSender();
		vars.issueKey = _getIssueKey(sft_, slot_);

		IssueInfo storage issueInfo = issueInfos[vars.issueKey];
		require(issueInfo.status == IssueStatus.ISSUING, "IssueMarket: not issuing");
		require(issueInfo.purchaseLimitInfo.startTime <= block.timestamp, "IssueMarket: issue not start");
		require(issueInfo.purchaseLimitInfo.endTime >= block.timestamp, "IssueMarket: issue expired");
		require(issueInfo.purchaseLimitInfo.useWhitelist == false || _whitelistStrategyManager().isWhitelisted(vars.issueKey, vars.buyer), "IssueMarket: not whitelisted");

		if (issueInfo.value >= issueInfo.purchaseLimitInfo.min) {
			require(value_ >= issueInfo.purchaseLimitInfo.min, "IssueMarket: value less than min");
		}
		if (issueInfo.purchaseLimitInfo.max > 0) {
			uint256 purchased = purchasedRecords[vars.issueKey][vars.buyer] + value_;
			require(purchased <= issueInfo.purchaseLimitInfo.max, "IssueMarket: value more than max");
			purchasedRecords[vars.issueKey][vars.buyer] = purchased;
		}

		require(issueInfo.value >= value_, "IssueMarket: issue value not enough");

		vars.underwriterKey = _getUnderwriterKey(underwriter_);
		UnderwriterInfo storage underwriterInfo = underwriterInfos[vars.underwriterKey];
		require(underwriterInfo.isValid, "IssueMarket: underwriter not supported");
		UnderwriterIssueInfo storage underwriterIssueInfo = underwriterIssueInfos[vars.underwriterKey][vars.issueKey];
		require(underwriterIssueInfo.value >= value_, "IssueMarket: underwriter quota not enough");

		issueInfo.value -= value_;
		underwriterIssueInfo.value -= value_;

		if (issueInfo.value == 0) {
			issueInfo.status = IssueStatus.SOLD_OUT;
		}

		vars.price = _priceStrategyManager().getPrice(issueInfo.priceType, priceInfos[vars.issueKey]);
		vars.payment = (vars.price * value_)/(10**vars.sftInfo.decimals);
		require(vars.price == 0 || vars.payment > 0, "IssueMarket: payment must be greater than 0");
		vars.issueFee = _getFee(vars.sftInfo.defaultFeeRate, vars.payment);
		vars.underwriterFee = _getFee(underwriterInfo.feeRate, vars.issueFee);
		require(vars.issueFee >= vars.underwriterFee, "IssueMarket: issue fee less than underwriter fee");
		totalReservedFees[issueInfo.currency] += (vars.issueFee - vars.underwriterFee);

		vars.tokenId = ISFTIssuableDelegate(sft_).mintOnlyIssueMarket(_msgSender(), issueInfo.currency, vars.buyer, issueInfo.slot, value_);
		ERC20TransferHelper.doTransferIn(issueInfo.currency, vars.buyer, vars.payment);
		ERC20TransferHelper.doApprove(issueInfo.currency, _underwriterProfitToken(), vars.underwriterFee);
		IMultiRechargeableDelegate(_underwriterProfitToken())
			.recharge(underwriterProfitSlot[vars.underwriterKey][issueInfo.currency], issueInfo.currency, vars.underwriterFee);
		ERC20TransferHelper.doTransferOut(issueInfo.currency, payable(issueInfo.receiver), vars.payment - vars.issueFee);

		emit Subscribe(sft_, slot_, vars.buyer, vars.tokenId, underwriter_, value_, issueInfo.currency, 
			vars.price, vars.payment, vars.issueFee, vars.underwriterFee);

		return (vars.tokenId, vars.payment);
	}

	function _validateInputIssueInfo(InputIssueInfo memory input_, bytes memory priceInfo_) internal view {
		require(input_.underwriters.length == input_.quotas.length, "IssueMarket: markets length not match");
		require(input_.min <= input_.max, "IssueMarket: min > max");
		require(input_.startTime <= input_.endTime, "IssueMarket: startTime > endTime");
		require(input_.receiver != address(0), "IssueMarket: receiver is zero address");
		require(input_.endTime > block.timestamp, "IssueMarket: endTime must be greater than now");
		if (input_.max > 0 && input_.min > 0) {
			require(input_.min <= input_.max, "IssueMarket: min > max");
		}
		require(input_.max <= input_.issueQuota, "IssueMarket: max > totalIssuance");
		require(input_.issueQuota > 0, "IssueMarket: totalIssuance must be greater than 0");

		require(_priceStrategyManager().checkPrice(input_.priceType, priceInfo_), "IssueMarket: priceInfo invalid");
	}

	function _getFee(uint16 feeRate_, uint256 payment_) internal pure returns (uint256) {
		return (payment_ * feeRate_) / Constants.FULL_PERCENTAGE;
	}

	function _getIssueKey(address sft_, uint256 slot_) internal pure returns (bytes32) {
		return keccak256(abi.encode(sft_, slot_));
	}
	function _getUnderwriterKey(string memory underwriteName) internal pure returns (bytes32) {
		return keccak256(abi.encode(underwriteName));
	}

	function _priceStrategyManager() internal view returns (IPriceStrategyManager) {
		return IPriceStrategyManager(getRequiredAddress(
			Constants.CONTRACT_ISSUE_MARKET_PRICE_STRATEGY_MANAGER, 
			"IssueMarket: PriceStrategyManager address not found"));
	}

	function _whitelistStrategyManager() internal view returns (IWhitelistStrategyManager) {
		return IWhitelistStrategyManager(getRequiredAddress(
			Constants.CONTRACT_ISSUE_MARKET_WHITELIST_STRATEGY_MANAGER, 
			"IssueMarket: WhitelistStrategyManager address not found"));
	}

	function _underwriterProfitToken() internal view returns (address) {
		return getRequiredAddress(
			Constants.CONTRACT_ISSUE_MARKET_UNDERWRITER_PROFIT_TOKEN, 
			"IssueMarket: UnderwriteProfitToken address not found");
	}

	function setWhitelist(address sft_, uint256 slot_, address[] calldata whitelist_) external {
		bytes32 issueKey = _getIssueKey(sft_, slot_);
		require(_msgSender() == issueInfos[issueKey].issuer, "IssueMarket: only issuer");
		issueInfos[issueKey].purchaseLimitInfo.useWhitelist = whitelist_.length > 0 ? true : false;
		_whitelistStrategyManager().setWhitelist(issueKey, whitelist_);
	}

	function addSFTOnlyOwner(address sft_, uint8 decimals_, uint16 defaultFeeRate_, address issuer_) external onlyOwner {
		sftInfos[sft_] = SFTInfo(sft_, issuer_, decimals_, defaultFeeRate_, true);
		emit AddSFT(sft_, issuer_, decimals_, defaultFeeRate_);
	}

	function removeSFTOnlyOwner(address sft_) external onlyOwner {
		sftInfos[sft_].isValid = false;
		emit RemoveSFT(sft_);
	}

	function setCurrencyOnlyOwner(address currency_, bool enabled_) external onlyOwner {
		currencies[currency_] = enabled_;
		emit SetCurrency(currency_, enabled_);
	}

	function addUnderwriterOnlyOwner(string calldata underwriter_, uint16 defaultFeeRate_, address[] calldata currencies_, address initialHolder_) public onlyOwner {
		bytes32 underwriterKey = _getUnderwriterKey(underwriter_);
		underwriterInfos[underwriterKey] = UnderwriterInfo(underwriter_, defaultFeeRate_, true);
		underwriterKeys.add(underwriterKey);
		emit AddUnderwriter(underwriter_, defaultFeeRate_);

		for (uint256 i = 0; i < currencies_.length; i++) {
			_createUnderwriterProfitSlot(underwriter_, currencies_[i], initialHolder_);
		}
	}
	function addUnderwriterCurrenciesOnlyOwner(string calldata underwriter_, address[] calldata currencies_, address initialHolder_) public onlyOwner {
		for (uint256 i = 0; i < currencies_.length; i++) {
			_createUnderwriterProfitSlot(underwriter_, currencies_[i], initialHolder_);
		}
	}
	function _createUnderwriterProfitSlot(string memory underwriter_, address currency_, address initialHolder_) internal {
		require(initialHolder_ != address(0), "IssueMarket: initial holder cannot zero address");
		
		bytes32 underwriterKey = _getUnderwriterKey(underwriter_);
		UnderwriterProfitConcrete underwriterProfitConcrete = UnderwriterProfitConcrete(ISFTDelegateControl(_underwriterProfitToken()).concrete());
		uint256 slot = underwriterProfitConcrete.getSlot(underwriter_, currency_);
		if (!underwriterProfitConcrete.isSlotValid(slot)) {
			IUnderwriterProfitConcrete.InputSlotInfo memory input = IUnderwriterProfitConcrete.InputSlotInfo(underwriter_, currency_);
			slot = ISFTMintableDelegate(_underwriterProfitToken()).createSlot(abi.encode(input));
			ISFTMintableDelegate(_underwriterProfitToken()).mint(initialHolder_, slot, 1e8 * (10 ** IERC3525(_underwriterProfitToken()).valueDecimals()));
		}
		underwriterProfitSlot[underwriterKey][currency_] = slot;
		emit AddUnderwriterCurrency(underwriter_, currency_, slot);
	}

	function withdrawFee(address to_, address currency_, uint256 amount_) external onlyOwner {
		require(totalReservedFees[currency_] >= amount_, "IssueMarket: insufficient reserved fee");
		ERC20TransferHelper.doTransferOut(currency_, payable(to_), amount_);
	}

	function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory) {
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](3);
		newAddresses[0] = Constants.CONTRACT_ISSUE_MARKET_PRICE_STRATEGY_MANAGER;
		newAddresses[1] = Constants.CONTRACT_ISSUE_MARKET_WHITELIST_STRATEGY_MANAGER;
		newAddresses[2] = Constants.CONTRACT_ISSUE_MARKET_UNDERWRITER_PROFIT_TOKEN;
		return _combineArrays(existAddresses, newAddresses);
	}
}
