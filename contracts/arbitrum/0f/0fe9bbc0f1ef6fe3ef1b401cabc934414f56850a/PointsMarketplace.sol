// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.7;

import {IERC20, IPointsMarketplace} from "./IPointsMarketplace.sol";
import {IWETH9} from "./IWETH9.sol";
import {SafeOwnableUpgradeable} from "./SafeOwnableUpgradeable.sol";
import {IERC20Permit} from "./draft-IERC20Permit.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

contract PointsMarketplace is
  IPointsMarketplace,
  ReentrancyGuardUpgradeable,
  SafeOwnableUpgradeable
{
  uint256 private _nextListingId;
  uint256 private _minSaleWeth;
  uint256 private _maxListingsPerSeller;
  uint256 private _globalSoldWeth;
  uint256 private _settlementWethPerPointSetTime;
  uint256 private _settlementWethPerPoint;

  mapping(uint256 => Listing) private _idToListing;
  mapping(uint256 => bool) private _idToCancelled;
  mapping(uint256 => bool) private _idToReclaimed;
  mapping(uint256 => uint256) private _idToSoldWeth;
  mapping(uint256 => uint256) private _idToRedeemedWeth;
  mapping(uint256 => uint256) private _idToDeliveredWeth;
  mapping(uint256 => mapping(address => uint256))
    private _idToAccountToSoldWeth;
  mapping(uint256 => mapping(address => uint256))
    private _idToAccountToRedeemedWeth;
  mapping(address => uint256) private _sellerToListingCount;

  IERC20 public constant override WETH =
    IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

  function initialize() public initializer {
    __ReentrancyGuard_init();
    __Ownable_init();
  }

  function createListing(
    uint256 pointsForSale,
    uint256 saleWethPerPoint,
    uint256 initialCollateralWethPerPoint,
    uint256 promisedCollateralWethPerPoint,
    Permit calldata permit
  ) external payable override nonReentrant {
    if (_settlementWethPerPointSetTime > 0)
      revert SettlementWethPerPointAlreadySet();
    uint256 saleWeth = (pointsForSale * saleWethPerPoint) / 1e18;
    if (saleWeth < _minSaleWeth) revert SaleWethBelowMin();
    if (promisedCollateralWethPerPoint < initialCollateralWethPerPoint)
      revert PromisedBelowInitialCollateralWethPerPoint();
    if (promisedCollateralWethPerPoint <= saleWethPerPoint)
      revert PromisedCollateralNotAboveSaleWethPerPoint();
    if (++_sellerToListingCount[msg.sender] > _maxListingsPerSeller)
      revert MaxListingsExceeded();
    _idToListing[_nextListingId++] = Listing(
      msg.sender,
      pointsForSale,
      saleWethPerPoint,
      initialCollateralWethPerPoint,
      promisedCollateralWethPerPoint
    );
    uint256 collateralWeth = (pointsForSale * initialCollateralWethPerPoint) /
      1e18;
    _processWethPermit(msg.sender, address(this), collateralWeth, permit);
    if (WETH.allowance(msg.sender, address(this)) < collateralWeth)
      revert InsufficientWethAllowance();
    if (msg.value > 0) {
      IWETH9(address(WETH)).deposit{value: msg.value}();
      WETH.transfer(msg.sender, msg.value);
    }
    if (collateralWeth > saleWeth) {
      uint256 collateralNeeded = collateralWeth - saleWeth;
      if (WETH.balanceOf(msg.sender) < collateralNeeded)
        revert InsufficientWethBalance();
    }
    emit ListingCreation(
      _nextListingId - 1,
      msg.sender,
      pointsForSale,
      saleWethPerPoint,
      initialCollateralWethPerPoint,
      promisedCollateralWethPerPoint
    );
  }

  function cancelListing(uint256 id) external override nonReentrant {
    if (_settlementWethPerPointSetTime > 0)
      revert SettlementWethPerPointAlreadySet();
    if (msg.sender != _idToListing[id].seller) revert MsgSenderIsNotSeller();
    _idToCancelled[id] = true;
    _sellerToListingCount[msg.sender]--;
    emit ListingCancellation(id);
  }

  function deliverCollateral(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external payable override nonReentrant {
    if (_settlementWethPerPointSetTime == 0)
      revert SettlementWethPerPointNotSet();
    if (msg.value > 0) IWETH9(address(WETH)).deposit{value: msg.value}();
    if (wethAmount > 0) {
      _processWethPermit(msg.sender, address(this), wethAmount, permit);
      WETH.transferFrom(msg.sender, address(this), wethAmount);
    }
    uint256 wethToDeliver = msg.value + wethAmount;
    if (wethToDeliver > getUndeliveredCollateralWeth(id))
      revert DeliveryExceedsUndeliveredCollateral();
    _idToDeliveredWeth[id] += wethToDeliver;
    emit CollateralDelivery(id, msg.sender, wethToDeliver);
  }

  function reclaimCollateral(
    uint256[] calldata ids
  ) external override nonReentrant {
    if (_settlementWethPerPointSetTime == 0)
      revert SettlementWethPerPointNotSet();
    for (uint256 i; i < ids.length; ++i) {
      uint256 id = ids[i];
      if (!_idToReclaimed[id]) {
        uint256 unreclaimedWethForListing = getUnreclaimedWeth(id);
        _idToReclaimed[id] = true;
        if (unreclaimedWethForListing > 0)
          WETH.transfer(_idToListing[id].seller, unreclaimedWethForListing);
        emit CollateralReclamation(id, msg.sender, unreclaimedWethForListing);
      }
    }
  }

  function buy(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external payable override nonReentrant {
    if (_settlementWethPerPointSetTime > 0)
      revert SettlementWethPerPointAlreadySet();
    if (_idToCancelled[id]) revert ListingCancelled();
    uint256 soldWeth = _idToSoldWeth[id];
    uint256 totalWethToSpend = msg.value + wethAmount;
    if (totalWethToSpend == 0) revert NoWethToSpend();
    if (soldWeth + totalWethToSpend > getSaleWeth(id))
      revert SaleWethExceeded();
    if (msg.value > 0) IWETH9(address(WETH)).deposit{value: msg.value}();
    if (wethAmount > 0) {
      _processWethPermit(msg.sender, address(this), wethAmount, permit);
      WETH.transferFrom(msg.sender, address(this), wethAmount);
    }
    _globalSoldWeth += totalWethToSpend;
    _idToSoldWeth[id] += totalWethToSpend;
    _idToAccountToSoldWeth[id][msg.sender] += totalWethToSpend;
    Listing memory listing = _idToListing[id];
    WETH.transfer(listing.seller, totalWethToSpend);
    uint256 collateralNeeded = (totalWethToSpend *
      listing.initialCollateralWethPerPoint) / listing.saleWethPerPoint;
    if (collateralNeeded > 0)
      WETH.transferFrom(listing.seller, address(this), collateralNeeded);
    emit Sale(id, msg.sender, totalWethToSpend);
  }

  function redeem(uint256 id, address buyer) external override nonReentrant {
    if (_settlementWethPerPointSetTime == 0)
      revert SettlementWethPerPointNotSet();
    uint256 unredeemedWeth = getUnredeemedWeth(id, buyer);
    if (unredeemedWeth > 0) {
      _idToRedeemedWeth[id] += unredeemedWeth;
      _idToAccountToRedeemedWeth[id][buyer] += unredeemedWeth;
      WETH.transfer(buyer, unredeemedWeth);
      emit Redemption(id, msg.sender, buyer, unredeemedWeth);
    }
  }

  function setMinSaleWeth(uint256 amount) external override onlyOwner {
    _minSaleWeth = amount;
    emit MinSaleWethChange(amount);
  }

  function setMaxListingsPerSeller(
    uint256 maxListingsPerSeller
  ) external override onlyOwner {
    _maxListingsPerSeller = maxListingsPerSeller;
    emit MaxListingsPerSellerChange(maxListingsPerSeller);
  }

  function setSettlementWethPerPoint(
    uint256 settlementWethPerPoint
  ) external override onlyOwner {
    if (_settlementWethPerPointSetTime > 0)
      revert SettlementWethPerPointAlreadySet();
    _settlementWethPerPointSetTime = block.timestamp;
    _settlementWethPerPoint = settlementWethPerPoint;
    emit SettlementWethPerPointChange(settlementWethPerPoint);
  }

  function getListing(
    uint256 id
  ) external view override returns (Listing memory) {
    return _idToListing[id];
  }

  function isCancelledListing(
    uint256 id
  ) external view override returns (bool) {
    return _idToCancelled[id];
  }

  function isReclaimedListing(
    uint256 id
  ) external view override returns (bool) {
    return _idToReclaimed[id];
  }

  function getHighestListingId() external view override returns (uint256) {
    return (_nextListingId == 0) ? 0 : _nextListingId - 1;
  }

  function getMinSaleWeth() external view override returns (uint256) {
    return _minSaleWeth;
  }

  function getListingCount(
    address seller
  ) external view override returns (uint256) {
    return _sellerToListingCount[seller];
  }

  function getMaxListingsPerSeller() external view override returns (uint256) {
    return _maxListingsPerSeller;
  }

  function getSoldWeth() external view override returns (uint256) {
    return _globalSoldWeth;
  }

  function getSoldWeth(uint256 id) external view override returns (uint256) {
    return _idToSoldWeth[id];
  }

  function getSoldWeth(
    uint256 id,
    address buyer
  ) external view override returns (uint256) {
    return _idToAccountToSoldWeth[id][buyer];
  }

  function getRedeemedWeth(
    uint256 id
  ) external view override returns (uint256) {
    return _idToRedeemedWeth[id];
  }

  function getRedeemedWeth(
    uint256 id,
    address buyer
  ) external view override returns (uint256) {
    return _idToAccountToRedeemedWeth[id][buyer];
  }

  function getDeliveredWeth(
    uint256 id
  ) external view override returns (uint256) {
    return _idToDeliveredWeth[id];
  }

  function getSettlementWethPerPoint()
    external
    view
    override
    returns (uint256)
  {
    if (_settlementWethPerPointSetTime == 0)
      revert SettlementWethPerPointNotSet();
    return _settlementWethPerPoint;
  }

  function getMaxUnredeemedWeth(
    uint256 id,
    address buyer
  ) external view override returns (uint256) {
    if (_settlementWethPerPointSetTime == 0) return 0;
    Listing memory listing = _idToListing[id];
    uint256 soldWethForBuyer = _idToAccountToSoldWeth[id][buyer];
    uint256 promisedCollateralForBuyer = (soldWethForBuyer *
      listing.promisedCollateralWethPerPoint) / listing.saleWethPerPoint;
    uint256 settlementCollateralForBuyer = (soldWethForBuyer *
      _settlementWethPerPoint) / listing.saleWethPerPoint;
    return
      _subOrZero(
        _min(promisedCollateralForBuyer, settlementCollateralForBuyer),
        _idToAccountToRedeemedWeth[id][buyer]
      );
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

  function getSaleWeth(uint256 id) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    return (listing.pointsForSale * listing.saleWethPerPoint) / 1e18;
  }

  function getTakenCollateralWeth(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    return
      (_idToSoldWeth[id] * listing.initialCollateralWethPerPoint) /
      listing.saleWethPerPoint;
  }

  function getTakenAndDeliveredCollateralWeth(
    uint256 id
  ) public view override returns (uint256) {
    return getTakenCollateralWeth(id) + _idToDeliveredWeth[id];
  }

  function getUnsoldWeth(uint256 id) public view override returns (uint256) {
    return getSaleWeth(id) - _idToSoldWeth[id];
  }

  function getUnredeemedWeth(
    uint256 id,
    address buyer
  ) public view override returns (uint256) {
    if (_settlementWethPerPointSetTime == 0) return 0;
    Listing memory listing = _idToListing[id];
    uint256 soldWethForBuyer = _idToAccountToSoldWeth[id][buyer];
    uint256 takenAndDeliveredCollateralForBuyer = (getTakenAndDeliveredCollateralWeth(
        id
      ) * soldWethForBuyer) / _idToSoldWeth[id];
    uint256 settlementCollateralForBuyer = (soldWethForBuyer *
      _settlementWethPerPoint) / listing.saleWethPerPoint;
    return
      _subOrZero(
        _min(
          takenAndDeliveredCollateralForBuyer,
          settlementCollateralForBuyer
        ),
        _idToAccountToRedeemedWeth[id][buyer]
      );
  }

  function getUnreclaimedWeth(
    uint256 id
  ) public view override returns (uint256) {
    if (_settlementWethPerPointSetTime == 0) return 0;
    if (_idToReclaimed[id]) return 0;
    Listing memory listing = _idToListing[id];
    uint256 soldWethForListing = _idToSoldWeth[id];
    uint256 promisedCollateralForSoldWeth = (soldWethForListing *
      listing.promisedCollateralWethPerPoint) / listing.saleWethPerPoint;
    uint256 settlementCollateralForSoldWeth = (soldWethForListing *
      _settlementWethPerPoint) / listing.saleWethPerPoint;
    return
      _subOrZero(
        getTakenAndDeliveredCollateralWeth(id),
        _min(promisedCollateralForSoldWeth, settlementCollateralForSoldWeth)
      );
  }

  function getUntakenCollateralWeth(
    uint256 id
  ) public view override returns (uint256) {
    Listing memory listing = _idToListing[id];
    uint256 maxInitialCollateralWeth = (listing.pointsForSale *
      listing.initialCollateralWethPerPoint) / 1e18;
    return maxInitialCollateralWeth - getTakenCollateralWeth(id);
  }

  function getUndeliveredCollateralWeth(
    uint256 id
  ) public view override returns (uint256) {
    if (_settlementWethPerPointSetTime == 0) return 0;
    Listing memory listing = _idToListing[id];
    uint256 soldWethForListing = _idToSoldWeth[id];
    uint256 promisedCollateralForSoldWeth = (soldWethForListing *
      listing.promisedCollateralWethPerPoint) / listing.saleWethPerPoint;
    uint256 settlementCollateralForSoldWeth = (soldWethForListing *
      _settlementWethPerPoint) / listing.saleWethPerPoint;
    return
      _subOrZero(
        _min(promisedCollateralForSoldWeth, settlementCollateralForSoldWeth),
        getTakenAndDeliveredCollateralWeth(id)
      );
  }

  function getMaxSpendableWeth(
    uint256 id
  ) external view override returns (uint256) {
    if (_settlementWethPerPointSetTime > 0) return 0;
    Listing memory listing = _idToListing[id];
    uint256 unsoldWeth = getUnsoldWeth(id);
    if (listing.initialCollateralWethPerPoint == 0) return unsoldWeth;
    uint256 untakenCollateralWeth = getUntakenCollateralWeth(id);
    uint256 balanceNeededForUntakenCollateral = _subOrZero(
      untakenCollateralWeth,
      unsoldWeth
    );
    uint256 maxCollateralWethFromBalance = _min(
      WETH.balanceOf(msg.sender),
      balanceNeededForUntakenCollateral
    );
    uint256 maxCollateralWethFromAllowance = _min(
      WETH.allowance(listing.seller, address(this)),
      untakenCollateralWeth
    );
    uint256 maxSaleWethFromBalance = (maxCollateralWethFromBalance *
      listing.saleWethPerPoint) / listing.initialCollateralWethPerPoint;
    uint256 maxSaleWethFromAllowance = (maxCollateralWethFromAllowance *
      listing.saleWethPerPoint) / listing.initialCollateralWethPerPoint;
    return _min(maxSaleWethFromBalance, maxSaleWethFromAllowance);
  }

  function getAdditionalBalanceNeeded(
    uint256 id
  ) external view override returns (uint256) {
    if (_settlementWethPerPointSetTime > 0) return 0;
    uint256 unsoldWeth = getUnsoldWeth(id);
    uint256 untakenCollateralWeth = getUntakenCollateralWeth(id);
    uint256 collateralNeeded = _subOrZero(untakenCollateralWeth, unsoldWeth);
    uint256 sellersBalance = WETH.balanceOf(_idToListing[id].seller);
    return _subOrZero(collateralNeeded, sellersBalance);
  }

  function getAdditionalAllowanceNeeded(
    uint256 id
  ) external view override returns (uint256) {
    if (_settlementWethPerPointSetTime > 0) return 0;
    uint256 untakenCollateralWeth = getUntakenCollateralWeth(id);
    uint256 sellersAllowance = WETH.allowance(
      _idToListing[id].seller,
      address(this)
    );
    return _subOrZero(untakenCollateralWeth, sellersAllowance);
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

  function _subOrZero(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? a - b : 0;
  }
}

