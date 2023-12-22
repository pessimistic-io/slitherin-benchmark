// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.7;

import {IERC20, ILostMyGlasses} from "./ILostMyGlasses.sol";
import {IWETH9} from "./IWETH9.sol";
import {SafeOwnableUpgradeable} from "./SafeOwnableUpgradeable.sol";
import {IERC20Permit} from "./draft-IERC20Permit.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

contract LostMyGlasses is
  ILostMyGlasses,
  ReentrancyGuardUpgradeable,
  SafeOwnableUpgradeable
{
  uint256 private _nextListingId;
  uint256 private _minSaleWethValue;
  uint256 private _minCollateralRatio;
  uint256 private _maxListingsPerSeller;
  uint256 private _globalWethSpent;
  uint256 private _settlementWethPerPointSetTime;
  uint256 private _settlementWethPerPoint;

  mapping(uint256 => Listing) private _idToListing;
  mapping(uint256 => bool) private _idToCancelled;
  mapping(uint256 => uint256) private _idToWethSpent;
  mapping(uint256 => uint256) private _idToWethDebt;
  mapping(uint256 => uint256) private _idToWethRedeemed;
  mapping(uint256 => mapping(address => uint256))
    private _idToAccountToWethSpent;
  mapping(uint256 => mapping(address => bool)) _idToAccountToRedeemed;
  mapping(address => uint256) private _sellerToListingCount;
  mapping(address => string) private _sellerToContactUrl;
  mapping(address => string) private _sellerToVerificationUrl;

  uint256 public constant override HUNDRED_PERCENT = 1_000_000;
  IERC20 public constant override WETH =
    IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

  function initialize() public initializer {
    __ReentrancyGuard_init();
    __Ownable_init();
  }

  function createListing(
    uint256 pointsForSale,
    uint256 saleWethPerPoint,
    uint256 collateralWethPerPoint,
    string calldata messageFromSeller,
    string calldata contactUrl,
    string calldata verificationUrl,
    Permit calldata permit
  ) external payable override nonReentrant {
    if (_settlementWethPerPointSetTime > 0) revert WethPerPointAlreadySet();
    if (bytes(contactUrl).length > 0)
      _sellerToContactUrl[msg.sender] = contactUrl;
    if (bytes(verificationUrl).length > 0)
      _sellerToVerificationUrl[msg.sender] = verificationUrl;
    uint256 saleWethValue = (pointsForSale * saleWethPerPoint) / 1e18;
    if (saleWethValue < _minSaleWethValue) revert SaleWethValueBelowMin();
    if (
      (collateralWethPerPoint * HUNDRED_PERCENT) / saleWethPerPoint <
      _minCollateralRatio
    ) revert CollateralRatioTooLow();
    if (++_sellerToListingCount[msg.sender] > _maxListingsPerSeller)
      revert MaxListingsExceeded();
    _idToListing[_nextListingId++] = Listing(
      msg.sender,
      pointsForSale,
      saleWethPerPoint,
      collateralWethPerPoint,
      messageFromSeller
    );
    uint256 collateralWethValue = (pointsForSale * collateralWethPerPoint) /
      1e18;
    _processWethPermit(msg.sender, address(this), collateralWethValue, permit);
    if (WETH.allowance(msg.sender, address(this)) < collateralWethValue)
      revert InsufficientWethAllowance();
    if (msg.value > 0) {
      IWETH9(address(WETH)).deposit{value: msg.value}();
      WETH.transfer(msg.sender, msg.value);
    }
    if (collateralWethValue > saleWethValue) {
      uint256 collateralNeeded = collateralWethValue - saleWethValue;
      if (WETH.balanceOf(msg.sender) < collateralNeeded)
        revert InsufficientWethBalance();
    }
  }

  function cancelListing(uint256 id) external override nonReentrant {
    if (_settlementWethPerPointSetTime > 0) revert WethPerPointAlreadySet();
    if (msg.sender != _idToListing[id].seller) revert MsgSenderIsNotSeller();
    _idToCancelled[id] = true;
    _sellerToListingCount[msg.sender]--;
  }

  function setContactUrl(string calldata url) external override nonReentrant {
    _sellerToContactUrl[msg.sender] = url;
  }

  function setVerificationUrl(
    string calldata url
  ) external override nonReentrant {
    _sellerToVerificationUrl[msg.sender] = url;
  }

  function addCollateral(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external payable override nonReentrant {
    if (msg.value > 0) IWETH9(address(WETH)).deposit{value: msg.value}();
    if (wethAmount > 0) {
      _processWethPermit(msg.sender, address(this), wethAmount, permit);
      WETH.transferFrom(msg.sender, address(this), wethAmount);
    }
    uint256 totalWethAmount = msg.value + wethAmount;
    _idToListing[id].collateralWethPerPoint =
      ((getLockedCollateralWethValue(id) + totalWethAmount) * 1e18) /
      _idToWethDebt[id];
  }

  function reclaimCollateral(
    uint256[] calldata ids
  ) external override nonReentrant {
    if (_settlementWethPerPointSetTime == 0) revert WethPerPointNotSet();
    for (uint256 i; i < ids.length; ++i) {
      uint256 id = ids[i];
      uint256 reclaimableWethForListing = getReclaimableCollateralWethValue(
        id
      );
      if (reclaimableWethForListing > 0) {
        _idToListing[id].collateralWethPerPoint = _settlementWethPerPoint;
        WETH.transfer(_idToListing[id].seller, reclaimableWethForListing);
      }
    }
  }

  function buy(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external payable override nonReentrant {
    if (_settlementWethPerPointSetTime > 0) revert WethPerPointAlreadySet();
    if (_idToCancelled[id]) revert ListingCancelled();
    uint256 wethSpent = _idToWethSpent[id];
    uint256 totalWethToSpend = msg.value + wethAmount;
    if (wethSpent + totalWethToSpend > getSaleWethValue(id))
      revert SaleWethValueExceeded();
    if (msg.value > 0) IWETH9(address(WETH)).deposit{value: msg.value}();
    if (wethAmount > 0) {
      _processWethPermit(msg.sender, address(this), wethAmount, permit);
      WETH.transferFrom(msg.sender, address(this), wethAmount);
    }
    _globalWethSpent += totalWethToSpend;
    _idToWethSpent[id] += totalWethToSpend;
    _idToWethDebt[id] += totalWethToSpend;
    _idToAccountToWethSpent[id][msg.sender] += totalWethToSpend;
    Listing memory listing = _idToListing[id];
    WETH.transfer(listing.seller, totalWethToSpend);
    uint256 collateralNeeded = (totalWethToSpend *
      listing.collateralWethPerPoint) / listing.saleWethPerPoint;
    WETH.transferFrom(listing.seller, address(this), collateralNeeded);
  }

  function redeem(uint256 id) external override nonReentrant {
    if (_settlementWethPerPointSetTime == 0) revert WethPerPointNotSet();
    if (_idToAccountToRedeemed[id][msg.sender]) revert AlreadyRedeemed();
    uint256 redeemableWeth = getRedeemableWeth(id, msg.sender);
    _idToAccountToRedeemed[id][msg.sender] = true;
    _idToWethDebt[id] -= _idToAccountToWethSpent[id][msg.sender];
    _idToWethRedeemed[id] += redeemableWeth;
    WETH.transfer(msg.sender, redeemableWeth);
  }

  function setMinSaleWethValue(uint256 wethValue) external override onlyOwner {
    _minSaleWethValue = wethValue;
  }

  function setMinCollateralRatio(uint256 ratio) external override onlyOwner {
    _minCollateralRatio = ratio;
  }

  function setMaxListingsPerSeller(
    uint256 maxListingsPerSeller
  ) external override onlyOwner {
    _maxListingsPerSeller = maxListingsPerSeller;
  }

  function setSettlementWethPerPoint(
    uint256 settlementWethPerPoint
  ) external override onlyOwner {
    if (_settlementWethPerPointSetTime > 0) revert WethPerPointAlreadySet();
    _settlementWethPerPointSetTime = block.timestamp;
    _settlementWethPerPoint = settlementWethPerPoint;
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

  function getSaleWethValue(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    return (listing.pointsForSale * listing.saleWethPerPoint) / 1e18;
  }

  function getCollateralWethValue(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    return (listing.pointsForSale * listing.collateralWethPerPoint) / 1e18;
  }

  function getCollateralRatio(
    uint256 id
  ) external view override returns (uint256) {
    return
      (getCollateralWethValue(id) * HUNDRED_PERCENT) / getSaleWethValue(id);
  }

  function getMinCollateralRatio() external view override returns (uint256) {
    return _minCollateralRatio;
  }

  function getListingCount(
    address seller
  ) external view override returns (uint256) {
    return _sellerToListingCount[seller];
  }

  function getContactUrl(
    address seller
  ) external view override returns (string memory) {
    return _sellerToContactUrl[seller];
  }

  function getVerificationUrl(
    address seller
  ) external view override returns (string memory) {
    return _sellerToVerificationUrl[seller];
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

  function getWethDebt(uint256 id) external view override returns (uint256) {
    return _idToWethDebt[id];
  }

  function getWethRedeemed(
    uint256 id
  ) external view override returns (uint256) {
    return _idToWethRedeemed[id];
  }

  function getSettlementWethPerPoint()
    external
    view
    override
    returns (uint256)
  {
    if (_settlementWethPerPointSetTime == 0) revert WethPerPointNotSet();
    return _settlementWethPerPoint;
  }

  function getSettlementWethPerPointSetTime()
    public
    view
    override
    returns (uint256)
  {
    return
      (_settlementWethPerPointSetTime == 0)
        ? type(uint256).max
        : _settlementWethPerPointSetTime;
  }

  function getRedeemableWeth(
    uint256 id,
    address buyer
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 wethSpent = _idToAccountToWethSpent[id][buyer];
    uint256 collateralWethValue = (wethSpent *
      listing.collateralWethPerPoint) / listing.saleWethPerPoint;
    uint256 settlementWethValue = (wethSpent * _settlementWethPerPoint) /
      listing.saleWethPerPoint;
    return _min(collateralWethValue, settlementWethValue);
  }

  function getReclaimableCollateralWethValue(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 wethDebt = _idToWethDebt[id];
    uint256 settlementWethValue = (wethDebt * _settlementWethPerPoint) /
      listing.saleWethPerPoint;
    uint256 lockedCollateralWethValue = getLockedCollateralWethValue(id);
    return
      (lockedCollateralWethValue > settlementWethValue)
        ? lockedCollateralWethValue - settlementWethValue
        : 0;
  }

  function getLockedCollateralWethValue(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    return
      (_idToWethDebt[id] * listing.collateralWethPerPoint) /
      listing.saleWethPerPoint;
  }

  function getMaxSpendableWeth(
    uint256 id
  ) external view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 remainingSaleWethValue = getSaleWethValue(id) - _idToWethSpent[id];
    uint256 remainingCollateralWethValue = getCollateralWethValue(id) -
      getLockedCollateralWethValue(id);
    uint256 balanceNeededForRemainingCollateral = (remainingCollateralWethValue >
        remainingSaleWethValue)
        ? remainingCollateralWethValue - remainingSaleWethValue
        : 0;
    uint256 maxCollateralWethValueFromBalance = _min(
      WETH.balanceOf(msg.sender),
      balanceNeededForRemainingCollateral
    );
    uint256 maxCollateralWethValueFromAllowance = _min(
      WETH.allowance(listing.seller, address(this)),
      remainingCollateralWethValue
    );
    uint256 maxSaleWethValueFromBalance = (maxCollateralWethValueFromBalance *
      listing.saleWethPerPoint) / listing.collateralWethPerPoint;
    uint256 maxSaleWethValueFromAllowance = (maxCollateralWethValueFromAllowance *
        listing.saleWethPerPoint) / listing.collateralWethPerPoint;
    return _min(maxSaleWethValueFromBalance, maxSaleWethValueFromAllowance);
  }

  function getAdditionalBalanceNeeded(
    uint256 id
  ) external view override returns (uint256) {
    uint256 remainingSaleWethValue = getSaleWethValue(id) - _idToWethSpent[id];
    uint256 remainingCollateralWethValue = getCollateralWethValue(id) -
      getLockedCollateralWethValue(id);
    uint256 collateralNeeded = (remainingSaleWethValue >=
      remainingCollateralWethValue)
      ? 0
      : remainingCollateralWethValue - remainingSaleWethValue;
    uint256 sellersBalance = WETH.balanceOf(_idToListing[id].seller);
    return (
      sellersBalance >= collateralNeeded
        ? 0
        : collateralNeeded - sellersBalance
    );
  }

  function getAdditionalAllowanceNeeded(
    uint256 id
  ) external view override returns (uint256) {
    uint256 remainingCollateralWethValue = getCollateralWethValue(id) -
      getLockedCollateralWethValue(id);
    uint256 sellersAllowance = WETH.allowance(
      _idToListing[id].seller,
      address(this)
    );
    return (
      sellersAllowance >= remainingCollateralWethValue
        ? 0
        : remainingCollateralWethValue - sellersAllowance
    );
  }

  function _processWethPermit(
    address owner,
    address spender,
    uint256 amount,
    Permit calldata permit
  ) internal {
    if (WETH.allowance(owner, spender) >= amount) return;
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

  function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}

