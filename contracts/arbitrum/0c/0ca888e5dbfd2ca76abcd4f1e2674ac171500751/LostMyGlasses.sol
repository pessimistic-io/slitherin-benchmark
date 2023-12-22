// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.7;

import {IERC20, ILostMyGlasses} from "./ILostMyGlasses.sol";
import {SafeOwnableUpgradeable} from "./SafeOwnableUpgradeable.sol";
import {IERC20Permit} from "./draft-IERC20Permit.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

contract LostMyGlasses is
  ILostMyGlasses,
  ReentrancyGuardUpgradeable,
  SafeOwnableUpgradeable
{
  bool private _redemptionsEnded;
  uint256 private _nextListingId;
  uint256 private _minSaleWethValue;
  uint256 private _minCollateralRatio;
  uint256 private _maxListingsPerSeller;
  uint256 private _globalWethSpent;
  uint256 private _settlementWethPerBlurSetTime;
  uint256 private _settlementWethPerBlur;

  mapping(uint256 => Listing) private _idToListing;
  mapping(uint256 => bool) private _idToCancelled;
  mapping(address => uint256) private _sellerToListingCount;
  mapping(uint256 => uint256) private _idToWethSpent;
  mapping(uint256 => uint256) private _idToWethRedeemed;
  mapping(uint256 => uint256) private _idToWethReclaimed;
  mapping(uint256 => mapping(address => uint256))
    private _idToAccountToWethSpent;
  mapping(uint256 => mapping(address => bool)) _idToAccountToRedeemed;
  mapping(address => bool) private _accountToBlurAmountSet;
  mapping(address => uint256) private _accountToBlurAmount;

  uint256 public immutable override REDEMPTION_WINDOW;

  uint256 public constant override HUNDRED_PERCENT = 1_000_000;
  IERC20 public constant override WETH =
    IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

  constructor(uint256 redemptionWindow) {
    REDEMPTION_WINDOW = redemptionWindow;
  }

  function initialize() public initializer {
    __ReentrancyGuard_init();
    __Ownable_init();
  }

  function createListing(
    address airdropRecipient,
    uint256 saleValuation,
    uint256 saleWethValue,
    uint256 collateralWethValue,
    Permit calldata permit
  ) external override nonReentrant {
    _revertIfSettled(airdropRecipient);
    if (saleWethValue < _minSaleWethValue) revert SaleWethValueBelowMin();
    if (
      (collateralWethValue * HUNDRED_PERCENT) / saleWethValue <
      getMinCollateralRatio()
    ) revert CollateralRatioTooLow();
    if (++_sellerToListingCount[msg.sender] > _maxListingsPerSeller)
      revert MaxListingsExceeded();
    _idToListing[_nextListingId++] = Listing(
      msg.sender,
      airdropRecipient,
      saleValuation,
      saleWethValue,
      collateralWethValue
    );
    uint256 collateralNeeded = collateralWethValue - saleWethValue;
    _processWethPermit(msg.sender, address(this), collateralNeeded, permit);
    if (WETH.allowance(msg.sender, address(this)) < collateralNeeded)
      revert InsufficientWethAllowance();
    if (WETH.balanceOf(msg.sender) < collateralNeeded)
      revert InsufficientWethBalance();
  }

  function cancelListing(uint256 id) external override nonReentrant {
    Listing memory listing = _idToListing[id];
    _revertIfSettled(listing.airdropRecipient);
    if (msg.sender != listing.seller) revert MsgSenderIsNotSeller();
    _idToCancelled[id] = true;
    _sellerToListingCount[msg.sender]--;
  }

  function reclaimCollateral(
    uint256[] calldata ids
  ) external override nonReentrant {
    if (_settlementWethPerBlurSetTime == 0) revert WethPerBlurNotSet();
    if (_redemptionsEnded) revert RedemptionsEnded();
    uint256 totalReclaimableWeth;
    for (uint256 i; i < ids.length; ++i) {
      uint256 id = ids[i];
      Listing memory listing = _idToListing[id];
      if (msg.sender != listing.seller) revert MsgSenderIsNotSeller();
      if (!_accountToBlurAmountSet[listing.airdropRecipient])
        revert BlurAmountNotSet();
      uint256 reclaimableWethForListing = getReclaimableCollateralWethValue(
        id
      );
      _idToWethReclaimed[id] += reclaimableWethForListing;
      totalReclaimableWeth += reclaimableWethForListing;
    }
    WETH.transfer(msg.sender, totalReclaimableWeth);
  }

  function buy(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external override nonReentrant {
    Listing memory listing = _idToListing[id];
    _revertIfSettled(listing.airdropRecipient);
    if (_idToCancelled[id]) revert ListingCancelled();
    uint256 ethSpent = _idToWethSpent[id];
    if (ethSpent + wethAmount > listing.saleWethValue)
      revert SaleWethValueExceeded();
    _globalWethSpent += wethAmount;
    _idToWethSpent[id] += wethAmount;
    _idToAccountToWethSpent[id][msg.sender] += wethAmount;
    _processWethPermit(msg.sender, listing.seller, wethAmount, permit);
    WETH.transferFrom(msg.sender, listing.seller, wethAmount);
    uint256 collateralNeeded = (listing.collateralWethValue * wethAmount) /
      listing.saleWethValue;
    WETH.transferFrom(listing.seller, address(this), collateralNeeded);
  }

  function redeem(uint256 id) external override nonReentrant {
    _revertIfNotSettled(_idToListing[id].airdropRecipient);
    if (_redemptionsEnded) revert RedemptionsEnded();
    if (_idToAccountToRedeemed[id][msg.sender]) revert AlreadyRedeemed();
    uint256 redeemableWeth = getRedeemableWeth(id, msg.sender);
    _idToAccountToRedeemed[id][msg.sender] = true;
    _idToWethRedeemed[id] += redeemableWeth;
    WETH.transfer(msg.sender, redeemableWeth);
  }

  function setMinSaleWethValue(uint256 wethValue) external override onlyOwner {
    _minSaleWethValue = wethValue;
  }

  function setMinCollateralRatio(uint256 ratio) external override onlyOwner {
    if (ratio < HUNDRED_PERCENT) revert MinCollateralRatioBelowOne();
    _minCollateralRatio = ratio;
  }

  function setMaxListingsPerSeller(
    uint256 maxListingsPerSeller
  ) external override onlyOwner {
    _maxListingsPerSeller = maxListingsPerSeller;
  }

  function setSettlementWethPerBlur(
    uint256 settlementWethPerBlur
  ) external override onlyOwner {
    if (_settlementWethPerBlurSetTime > 0) revert WethPerBlurAlreadySet();
    _settlementWethPerBlurSetTime = block.timestamp;
    _settlementWethPerBlur = settlementWethPerBlur;
  }

  function setSettlementBlurAmount(
    address airdropRecipient,
    uint256 blurAmount
  ) external override onlyOwner {
    if (_accountToBlurAmountSet[airdropRecipient])
      revert BlurAmountAlreadySet();
    _accountToBlurAmountSet[airdropRecipient] = true;
    _accountToBlurAmount[airdropRecipient] = blurAmount;
  }

  function endRedemptions() external override onlyOwner {
    if (getMinRedemptionEndTime() > block.timestamp)
      revert BeforeMinRedemptionEndTime();
    _redemptionsEnded = true;
    WETH.transfer(msg.sender, WETH.balanceOf(address(this)));
  }

  function getListing(
    uint256 id
  ) external view override returns (Listing memory) {
    return _idToListing[id];
  }

  function isListingCancelled(
    uint256 id
  ) external view override returns (bool) {
    return _idToCancelled[id];
  }

  function getHighestListingId() external view override returns (uint256) {
    return (_nextListingId == 0) ? 0 : _nextListingId - 1;
  }

  function getMinSaleWethValue() external view override returns (uint256) {
    return _minSaleWethValue;
  }

  function getCollateralRatio(
    uint256 id
  ) external view override returns (uint256) {
    return
      (_idToListing[id].collateralWethValue * HUNDRED_PERCENT) /
      _idToListing[id].saleWethValue;
  }

  function getMinCollateralRatio() public view override returns (uint256) {
    return (_minCollateralRatio == 0) ? HUNDRED_PERCENT : _minCollateralRatio;
  }

  function getListingCount(
    address seller
  ) external view override returns (uint256) {
    return _sellerToListingCount[seller];
  }

  function getMaxListingsPerSeller() external view override returns (uint256) {
    return _maxListingsPerSeller;
  }

  function getWethSpent() external view override returns (uint256) {
    return _globalWethSpent;
  }

  function getWethSpent(uint256 id) external view override returns (uint256) {
    return _idToWethSpent[id];
  }

  function getWethSpent(
    uint256 id,
    address buyer
  ) external view override returns (uint256) {
    return _idToAccountToWethSpent[id][buyer];
  }

  function getWethRedeemed(
    uint256 id
  ) external view override returns (uint256) {
    return _idToWethRedeemed[id];
  }

  function getWethReclaimed(
    uint256 id
  ) external view override returns (uint256) {
    return _idToWethReclaimed[id];
  }

  function getSettlementWethPerBlur()
    external
    view
    override
    returns (uint256)
  {
    if (_settlementWethPerBlurSetTime == 0) revert WethPerBlurNotSet();
    return _settlementWethPerBlur;
  }

  function isSettlementBlurAmountSet(
    address airdropRecipient
  ) external view override returns (bool) {
    return _accountToBlurAmountSet[airdropRecipient];
  }

  function getSettlementBlurAmount(
    address airdropRecipient
  ) external view override returns (uint256) {
    if (!_accountToBlurAmountSet[airdropRecipient]) revert BlurAmountNotSet();
    return _accountToBlurAmount[airdropRecipient];
  }

  function getSettlementValuation(
    uint256 id
  ) public view override returns (uint256) {
    return
      (_accountToBlurAmount[_idToListing[id].airdropRecipient] *
        _settlementWethPerBlur) / 1e18;
  }

  function getAllBuyersShare(
    uint256 id
  ) public view override returns (uint256) {
    return
      _min(
        (getSettlementValuation(id) * 1e18) / _idToListing[id].saleValuation,
        1e18
      );
  }

  function getRedeemableWeth(
    uint256 id,
    address buyer
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    if (_isNotSettled(listing.airdropRecipient)) return 0;
    if (_idToAccountToRedeemed[id][buyer]) return 0;
    uint256 lockedCollateralWethValue = getLockedCollateralWethValue(id);
    uint256 buyersWethSpentForListing = _idToAccountToWethSpent[id][
      msg.sender
    ];
    uint256 totalWethSpentForListing = _idToWethSpent[id];
    uint256 individualBuyersShare = (buyersWethSpentForListing * 1e18) /
      totalWethSpentForListing;
    return
      (individualBuyersShare *
        getAllBuyersShare(id) *
        lockedCollateralWethValue) / (1e36);
  }

  function getReclaimableCollateralWethValue(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    if (_isNotSettled(listing.airdropRecipient)) return 0;
    if (_redemptionsEnded) return 0;
    uint256 sellersShare = 1e18 - getAllBuyersShare(id);
    uint256 lockedCollateralWethValue = getLockedCollateralWethValue(id);
    uint256 maxReclaimableAmount = (sellersShare * lockedCollateralWethValue) /
      1e18;
    return
      (maxReclaimableAmount > _idToWethReclaimed[id])
        ? maxReclaimableAmount - _idToWethReclaimed[id]
        : 0;
  }

  function getSettlementWethPerBlurSetTime()
    public
    view
    override
    returns (uint256)
  {
    return
      (_settlementWethPerBlurSetTime == 0)
        ? type(uint256).max
        : _settlementWethPerBlurSetTime;
  }

  function getMinRedemptionEndTime() public view override returns (uint256) {
    return
      (_settlementWethPerBlurSetTime == 0)
        ? type(uint256).max
        : _settlementWethPerBlurSetTime + REDEMPTION_WINDOW;
  }

  function hasRedemptionEnded() public view override returns (bool) {
    return _redemptionsEnded;
  }

  function getLockedCollateralWethValue(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    return
      (_idToWethSpent[id] * listing.collateralWethValue) /
      listing.saleWethValue;
  }

  function getMaxSpendableWeth(
    uint256 id
  ) external view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 remainingSaleWethValue = listing.saleWethValue -
      _idToWethSpent[id];
    uint256 effectiveBalance = _min(
      WETH.balanceOf(listing.seller),
      WETH.allowance(listing.seller, address(this))
    );
    uint256 maxSaleWethValue = (effectiveBalance * listing.saleWethValue) /
      listing.collateralWethValue;
    return _min(remainingSaleWethValue, maxSaleWethValue);
  }

  function getAdditionalCollateralNeeded(
    uint256 id
  ) external view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 sellersBalance = WETH.balanceOf(listing.seller);
    uint256 remainingSaleWethValue = listing.saleWethValue -
      _idToWethSpent[id];
    uint256 remainingCollateralWethValue = listing.collateralWethValue -
      getLockedCollateralWethValue(id);
    uint256 additionalCollateralNeeded = remainingCollateralWethValue -
      remainingSaleWethValue;
    return (
      sellersBalance >= additionalCollateralNeeded
        ? 0
        : additionalCollateralNeeded - sellersBalance
    );
  }

  function getAdditionalAllowanceNeeded(
    uint256 id
  ) external view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 sellersAllowance = WETH.allowance(listing.seller, address(this));
    uint256 remainingSaleWethValue = listing.saleWethValue -
      _idToWethSpent[id];
    uint256 remainingCollateralWethValue = listing.collateralWethValue -
      getLockedCollateralWethValue(id);
    uint256 additionalCollateralNeeded = remainingCollateralWethValue -
      remainingSaleWethValue;
    return (
      sellersAllowance >= additionalCollateralNeeded
        ? 0
        : additionalCollateralNeeded - sellersAllowance
    );
  }

  function _processWethPermit(
    address owner,
    address spender,
    uint256 amount,
    Permit calldata permit
  ) internal {
    if (permit.deadline > 0)
      IERC20Permit(address(WETH)).permit(
        owner,
        spender,
        amount,
        permit.deadline,
        permit.v,
        permit.r,
        permit.s
      );
  }

  function _revertIfSettled(address airdropRecipient) internal view {
    if (_settlementWethPerBlurSetTime > 0) revert WethPerBlurAlreadySet();
    if (_accountToBlurAmountSet[airdropRecipient])
      revert BlurAmountAlreadySet();
  }

  function _revertIfNotSettled(address airdropRecipient) internal view {
    if (_settlementWethPerBlurSetTime == 0) revert WethPerBlurNotSet();
    if (!_accountToBlurAmountSet[airdropRecipient]) revert BlurAmountNotSet();
  }

  function _isNotSettled(
    address airdropRecipient
  ) internal view returns (bool) {
    return (_settlementWethPerBlurSetTime == 0 ||
      !_accountToBlurAmountSet[airdropRecipient]);
  }

  function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}

