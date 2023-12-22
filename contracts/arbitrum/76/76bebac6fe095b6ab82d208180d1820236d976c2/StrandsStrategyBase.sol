// SPDX-License-Identifier: MIT
// ShortGammaStrategy.sol v1.0
pragma solidity ^0.8.16;

// standard strategy interface
import "./IStrandsStrategy.sol";

// Libraries
import {Vault} from "./Vault.sol";
import "./libraries_Math.sol";
//import {IERC20} from "openzeppelin-contracts-4.4.1/token/ERC20/IERC20.sol";
import {IERC20Decimals} from "./IERC20Decimals.sol";
import {StrandsVault} from "./StrandsVault.sol";
import {OneClicks} from "./OneClicks.sol";

import {ConvertDecimals} from "./ConvertDecimals.sol";
import {OptionToken} from "./OptionToken.sol";
import {LyraRegistry} from "./LyraRegistry.sol";
import {OptionMarket} from "./OptionMarket.sol";
import {DecimalMath} from "./DecimalMath.sol";
import {SignedDecimalMath} from "./SignedDecimalMath.sol";
import {BaseExchangeAdapter} from "./BaseExchangeAdapter.sol";
import {OwnableAdmins} from "./OwnableAdmins.sol";
import {console} from "./console.sol";
import {StrandsUtils} from "./StrandsUtils.sol";

abstract contract StrandsStrategyBase is OwnableAdmins,IStrandsStrategy {
  //using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct StrategyDetail {
    uint minTimeToExpiry; // minimum board expiry
    uint maxTimeToExpiry; // maximum board expiry
    uint maxDeltaGap; // max diff between targetStraddleDelta and strike delta we trade
    uint maxVol; //max vol to do trade
    uint minTradeInterval; // min seconds between StrandsLyraVault.trade() calls
    uint minDeltaToHedge;  //min delta to make hedge worth it
    uint maxTradeUtilization;
    uint timeBetweenRoundEndAndExpiry;
    uint bidAskSpread;
  }

  struct PositionsInfo{
    uint putUnitPrice;
    uint callUnitPrice;
    uint putCollateral;
    uint callCollateral;
    int putUnitDelta;
    int callUnitDelta;
    int putAmount;
    int callAmount;
    int totalDelta;
    int wTotalDelta; //weighted by average size of positions
  }

  StrategyDetail public strategyDetail;
  StrandsVault public immutable vault;
  string public underlier;
  IERC20Decimals quoteAsset;
  OneClicks public oneClicks;
  OptionToken optionToken;
  address lyraRegistry;
  uint lastTradeTimestamp;
  uint lastHedgeTimestamp;
  uint lastHedgeSpot;
  uint public activeStrikeId;
  uint public boardId;

  modifier onlyVault() {
    require(msg.sender == address(vault), "only Vault");
    _;
  }

  constructor(StrandsVault _vault, string memory _underlier, address _oneClicksAddress, address _lyraRegistry) {
    vault = _vault;
    underlier=_underlier;
    lyraRegistry=_lyraRegistry;
    setOneClicks(_oneClicksAddress);
  }

  function doTrade(uint strikeId) public virtual returns (int,uint[] memory);

  function deltaHedge(uint hedgeType) public virtual returns (int,uint[] memory);

  function setStrategyDetail(StrategyDetail memory _strategyDetail) external onlyAdmins {
    strategyDetail = _strategyDetail;
  }

  function setBoard(uint _boardId) public onlyVault returns (uint roundEnds) {
    OptionMarket.OptionBoard memory _board = oneClicks.underlierToMarket(underlier).getOptionBoard(_boardId);
    require(_isValidExpiry(_board.expiry), "invalid board");
    activeStrikeId=0;
    boardId=_boardId;
    console.log("setBoard() boardId=%s expiry=%s",_board.id,_board.expiry);
    return _board.expiry - strategyDetail.timeBetweenRoundEndAndExpiry;
  }

  function hasOpenPosition() public view returns (bool) {
    OptionToken.OptionPosition[] memory ownerPositions = optionToken.getOwnerPositions(address(this));
    console.log("has %s open positions",ownerPositions.length);
    for (uint i=0; i<ownerPositions.length;i++) {
      if (ownerPositions[i].state==OptionToken.PositionState.ACTIVE && ownerPositions[i].amount>0) return true;
    }
    return false;
  }

  function _getAllPositionsDelta() internal view returns (PositionsInfo memory p) {
    OptionToken.OptionPosition[] memory ownerPositions = optionToken.getOwnerPositions(address(this));
      
    console.log('activeStrikeId=',activeStrikeId);
    if (activeStrikeId==0) return p;

    (p.callUnitPrice, p.putUnitPrice) = oneClicks.getOptionPrices(underlier,activeStrikeId);
    (p.callUnitDelta, p.putUnitDelta) = oneClicks.getDeltas(underlier,activeStrikeId);
    
    for (uint i=0; i<ownerPositions.length;i++) {
      if (StrandsUtils.isThisCall(ownerPositions[i].optionType)) {
        if (StrandsUtils.isThisLong(ownerPositions[i].optionType)) {
          p.callAmount = int(ownerPositions[i].amount);
        } else {
          p.callAmount = -1*int(ownerPositions[i].amount);
          p.callCollateral=ownerPositions[i].collateral;
        }
        console.log("positionId=%s isCall=1 isLong=%s amount=%s/100",ownerPositions[i].positionId,
          StrandsUtils.isThisLong(ownerPositions[i].optionType),ownerPositions[i].amount/10**16);
      } else {
        if (StrandsUtils.isThisLong(ownerPositions[i].optionType)) {
          p.putAmount = int(ownerPositions[i].amount);
        } else {
          p.putAmount = -1*int(ownerPositions[i].amount);
          p.putCollateral=ownerPositions[i].collateral;
        }
        console.log("positionId=%s isCall=0 isLong=%s amount=%s/100",ownerPositions[i].positionId,
            StrandsUtils.isThisLong(ownerPositions[i].optionType),ownerPositions[i].amount/10**16);
      }
    }
    p.totalDelta = _calculateTotalDelta(activeStrikeId,p.callAmount, p.putAmount);
    p.wTotalDelta = p.totalDelta.divideDecimal((p.callAmount+p.putAmount)/2);
    console.log("weightedTotalDelta=%s/100", _abs(p.wTotalDelta)/10**16);
  }

  function _calculateTotalDelta(uint strikeId, int callAmount, int putAmount) internal view returns(int totalDelta) {
    (int strikeCallDelta, int strikePutDelta) = oneClicks.getDeltas(underlier,strikeId);
    totalDelta=callAmount.multiplyDecimal(strikeCallDelta)+putAmount.multiplyDecimal(strikePutDelta);
    console.log("totalDelta=%s/100 isPositive=%s",_abs(totalDelta)/10**16,_isPositive(totalDelta));
  }

  function _isPositive(int signedInt) internal pure returns (bool) {
    if (signedInt<0) {return false;} else {return true;}
  }

  /**
   * @dev close all outstanding positions regardless of collat and send funds back to vault
   */
  function emergencyCloseAll() public onlyVault returns (int balChange) {
    oneClicks.closeAllPositionsByUnderlier(underlier);
    balChange=int(quoteAsset.balanceOf(address(this)));
    returnFundsToVault();
  }

  function returnFundsToVault() public onlyVault {
    uint quoteBal = quoteAsset.balanceOf(address(this));
      // send quote balance directly
    require(quoteAsset.transfer(address(vault), quoteBal), "failed to return funds from strategy");
    if (!hasOpenPosition()) activeStrikeId=0;
  }

  function setOneClicks(address _oneClicksAddress) public onlyAdmins{
    if (address(oneClicks) != address(0)) {
      quoteAsset.approve(address(oneClicks), 0);
      optionToken.setApprovalForAll(address(oneClicks), false);
    }
    oneClicks=OneClicks(_oneClicksAddress);
    quoteAsset = oneClicks.quoteAsset();
    quoteAsset.approve(address(_oneClicksAddress), type(uint).max);
    optionToken = OptionToken(LyraRegistry(lyraRegistry).getMarketAddresses(
      oneClicks.underlierToMarket(underlier)).optionToken);
    optionToken.setApprovalForAll(address(oneClicks), true);
  }

  function _isValidExpiry(uint expiry) public view returns (bool isValid) {
    uint secondsToExpiry = _getSecondsToExpiry(expiry);
    isValid = (secondsToExpiry >= strategyDetail.minTimeToExpiry && secondsToExpiry <= strategyDetail.maxTimeToExpiry);
  }

  function isValidStrike(uint strikeId) public view returns (bool isValid) {
    (, OptionMarket.OptionBoard memory board1) = oneClicks.underlierToMarket(underlier).getStrikeAndBoard(strikeId);
    if (boardId != board1.id) {
      console.log("wrong board id");
      return false;
    }
    (int callDelta,) = oneClicks.getDeltas(underlier,strikeId);
    uint deltaGap = _abs(0.5*10**18 - callDelta);
    console.log("deltaGap=%s/100",deltaGap/10**16);
    console.log("strategyDetail.maxDeltaGap=%s/100",strategyDetail.maxDeltaGap/10**16);
    return deltaGap < strategyDetail.maxDeltaGap;
  }

  function _getSecondsToExpiry(uint expiry) internal view returns (uint) {
    require(block.timestamp <= expiry, "timestamp expired");
    return expiry - block.timestamp;
  }

  function _getSpot() internal view returns (uint) {
    return oneClicks.exchangeAdapter().getSpotPriceForMarket(address(oneClicks.underlierToMarket(underlier))
      ,BaseExchangeAdapter.PriceType.REFERENCE);
  }

  function _abs(int val) internal pure returns (uint) {
    return val >= 0 ? uint(val) : uint(-val);
  }

}

