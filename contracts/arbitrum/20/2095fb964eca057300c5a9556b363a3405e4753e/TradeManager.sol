// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./Strings.sol";
import "./ReentrancyGuard.sol";

import "./TradeOwner.sol";

contract TradeManager is TradeOwner, ReentrancyGuard {
  using SafeMath  for uint256;
  using SafeERC20 for IERC20;

  enum Status { Unfilled, Filled, Cancelled }

  //events ===========
  event eventCreateNewTrade(
    bytes32 tradeId,
    address user0,
    address token0,
    uint256 token0Amount,
    address[] acceptedTokens,
    uint256[] acceptedAmounts,
    uint8 status,
    uint256 fillCount,
    uint256 token0AmountRemaining,
    address refer
  );

  event eventFillTrade(
    bytes32 tradeId,
    address user0,
    uint8 status,
    uint256 fillCount,
    address filler,
    uint256 token0FillAmount,
    address acceptedToken,
    uint256 acceptedTokenAmountSent
  );

  event eventUpdateAcceptedTokens(
    bytes32 tradeId,
    address user0,
    address[] acceptedTokens,
    uint256[] acceptedAmounts
  );

  event eventCancelTrade(
    bytes32 tradeId,
    address user0,
    address token0,
    uint256 token0Amount,
    uint256 status,
    uint256 fillCount,
    uint256 refundAmount
  );

  struct Filler {
    bool isExist;
    address user;
    address acceptedToken;
    uint256 acceptedTokenAmountSent;
    uint256 token0FillAmount;
  }

  struct TradeCommissions {
    uint256 token0Commission;
    uint256 acceptedTokenCommission;
    uint256 referToken0Commission;
    uint256 referAcceptedTokenCommission;
  }

  struct FillAcceptedObj {
    uint256 acceptedAmount;
    uint256 acceptedTokenAmountSent;
  }

  struct Trade {
    bool    isExist;
    address user0;
    address token0;
    uint256 token0Amount;
    address[] acceptedTokens;
    uint256[] acceptedAmounts;
    Status status;
    uint256 fillCount;
    uint256 token0AmountRemaining;
    address refer;
  }

  mapping(string => Trade)   internal trades;
  mapping(string => Filler)  internal fills;

  constructor() {}

  modifier onlyUser() {
    require(_msgSender() != owner());
    _;
  }

  receive() external payable { }

  fallback() external payable { }

  function createNewTrade(
    bytes32 tradeId,
    address token0,
    uint256 token0Amount,
    address[] memory acceptedTokens,
    uint256[] memory acceptedAmounts,
    address refer
  ) external onlyUser payable nonReentrant {

    require(contractEnabled == true);
    require(token0Amount > 0);
    require(acceptedTokens.length == acceptedAmounts.length);
    require(_validAcceptedTokens(token0, acceptedTokens) == true);
    require(_validAcceptedAmounts(acceptedAmounts) == true);

    string memory tradeKey = _returnTradeKey(tradeId, _msgSender());
    require(trades[tradeKey].isExist != true);

    Trade memory newTrade;
    newTrade.isExist = true;
    newTrade.user0 = _msgSender();
    newTrade.token0 = token0;
    newTrade.token0Amount = token0Amount;
    newTrade.acceptedTokens = acceptedTokens;
    newTrade.acceptedAmounts = acceptedAmounts;
    newTrade.status = Status.Unfilled;
    newTrade.fillCount = 0;
    newTrade.token0AmountRemaining = token0Amount;

    if (token0 == address(0)) {
      require(msg.value >= token0Amount);
    } else {
      // check for tax tokens where amount received != transfer amount
      uint256 balanceBefore = IERC20(token0).balanceOf(address(this));
      IERC20(token0).safeTransferFrom(_msgSender(), address(this), token0Amount);
      uint256 balanceAfter = IERC20(token0).balanceOf(address(this));
      newTrade.token0Amount = balanceAfter.sub(balanceBefore);
      newTrade.token0AmountRemaining = balanceAfter.sub(balanceBefore);
    }

    if (refer != address(0) && referEnabled) {
      newTrade.refer = refer;
    }

    trades[tradeKey] = newTrade;

    emit eventCreateNewTrade(
      tradeId,
      newTrade.user0,
      newTrade.token0,
      newTrade.token0Amount,
      newTrade.acceptedTokens,
      newTrade.acceptedAmounts,
      uint8(newTrade.status),
      newTrade.fillCount,
      newTrade.token0AmountRemaining,
      newTrade.refer
    );
  }

  function fillTrade(
    bytes32 tradeId,
    address user0,
    address acceptedToken,
    uint256 token0FillAmount
  ) external onlyUser payable nonReentrant {

    require(contractEnabled == true);
    string memory tradeKey = _returnTradeKey(tradeId, user0);
    require(trades[tradeKey].isExist);
    require(trades[tradeKey].user0 != _msgSender());
    require(trades[tradeKey].status == Status.Unfilled);
    require(_tokenIsAccepted(acceptedToken, trades[tradeKey].acceptedTokens) == true);

    require(token0FillAmount <= trades[tradeKey].token0AmountRemaining);

    FillAcceptedObj memory fillAcceptedObj;
    fillAcceptedObj.acceptedAmount = _getAcceptedAmount(acceptedToken, trades[tradeKey].acceptedTokens, trades[tradeKey].acceptedAmounts);
    fillAcceptedObj.acceptedTokenAmountSent = fillAcceptedObj.acceptedAmount.mul(token0FillAmount).div(trades[tradeKey].token0Amount);

    // filler must deposit funds
    if (acceptedToken == address(0)) {
      require(msg.value >= fillAcceptedObj.acceptedTokenAmountSent);
    } else {
      // check for tax tokens where amount received != transfer amount
      uint256 balanceBefore = IERC20(acceptedToken).balanceOf(address(this));
      IERC20(acceptedToken).safeTransferFrom(_msgSender(), address(this), fillAcceptedObj.acceptedTokenAmountSent);
      uint256 balanceAfter = IERC20(acceptedToken).balanceOf(address(this));
      fillAcceptedObj.acceptedTokenAmountSent = balanceAfter.sub(balanceBefore);
    }

    string memory fillKey = _returnFillKey(tradeId, trades[tradeKey].fillCount.add(1));
    require(fills[fillKey].isExist != true);

    Filler memory newFiller;
    newFiller.isExist = true;
    newFiller.user = _msgSender();
    newFiller.acceptedToken = acceptedToken;
    newFiller.acceptedTokenAmountSent = fillAcceptedObj.acceptedTokenAmountSent;
    newFiller.token0FillAmount = token0FillAmount;
    fills[fillKey] = newFiller;

    trades[tradeKey].fillCount = trades[tradeKey].fillCount.add(1);
    trades[tradeKey].token0AmountRemaining = trades[tradeKey].token0AmountRemaining.sub(token0FillAmount);

    if (trades[tradeKey].token0AmountRemaining == 0) {
      trades[tradeKey].status = Status.Filled;
    }

    uint256 feeToUse = defaultFee;
    string memory pairKey = _appendAddresses(trades[tradeKey].token0, acceptedToken);
    if (pairs[pairKey].isExist == true) {
      feeToUse = pairs[pairKey].fee;
    }

    TradeCommissions memory tradeCommissions;
    tradeCommissions.token0Commission = token0FillAmount.mul(feeToUse).div(feeDivider);
    tradeCommissions.acceptedTokenCommission = fillAcceptedObj.acceptedTokenAmountSent.mul(feeToUse).div(feeDivider);
    tradeCommissions.referToken0Commission = tradeCommissions.token0Commission.mul(referFee).div(feeDivider);
    tradeCommissions.referAcceptedTokenCommission = tradeCommissions.acceptedTokenCommission.mul(referFee).div(feeDivider);

    if (trades[tradeKey].refer != address(0) && referEnabled) {

      // send to msg sender
      if (trades[tradeKey].token0 == address(0)) {
        payable(_msgSender()).transfer(token0FillAmount.sub(tradeCommissions.token0Commission));
        payable(commissionAddress).transfer(tradeCommissions.token0Commission.sub(tradeCommissions.referToken0Commission));
        payable(trades[tradeKey].refer).transfer(tradeCommissions.referToken0Commission);
      } else {
        IERC20(trades[tradeKey].token0).safeTransfer(_msgSender(), token0FillAmount.sub(tradeCommissions.token0Commission));
        IERC20(trades[tradeKey].token0).safeTransfer(commissionAddress, tradeCommissions.token0Commission.sub(tradeCommissions.referToken0Commission));
        IERC20(trades[tradeKey].token0).safeTransfer(trades[tradeKey].refer, tradeCommissions.referToken0Commission);
      }

      // send to trade owner
      if (acceptedToken == address(0)) {
        payable(trades[tradeKey].user0).transfer(fillAcceptedObj.acceptedTokenAmountSent.sub(tradeCommissions.acceptedTokenCommission));
        payable(commissionAddress).transfer(tradeCommissions.acceptedTokenCommission.sub(tradeCommissions.referAcceptedTokenCommission));
        payable(trades[tradeKey].refer).transfer(tradeCommissions.referAcceptedTokenCommission);
      } else {
        IERC20(acceptedToken).safeTransfer(trades[tradeKey].user0, fillAcceptedObj.acceptedTokenAmountSent.sub(tradeCommissions.acceptedTokenCommission));
        IERC20(acceptedToken).safeTransfer(commissionAddress, tradeCommissions.acceptedTokenCommission.sub(tradeCommissions.referAcceptedTokenCommission));
        IERC20(acceptedToken).safeTransfer(trades[tradeKey].refer, tradeCommissions.referAcceptedTokenCommission);
      }

    } else {
      // send to msg sender
      if (trades[tradeKey].token0 == address(0)) {
        payable(_msgSender()).transfer(token0FillAmount.sub(tradeCommissions.token0Commission));
        payable(commissionAddress).transfer(tradeCommissions.token0Commission);
      } else {
        IERC20(trades[tradeKey].token0).safeTransfer(_msgSender(), token0FillAmount.sub(tradeCommissions.token0Commission));
        IERC20(trades[tradeKey].token0).safeTransfer(commissionAddress, tradeCommissions.token0Commission);
      }

      // send to trade owner
      if (acceptedToken == address(0)) {
        payable(trades[tradeKey].user0).transfer(fillAcceptedObj.acceptedTokenAmountSent.sub(tradeCommissions.acceptedTokenCommission));
        payable(commissionAddress).transfer(tradeCommissions.acceptedTokenCommission);
      } else {
        IERC20(acceptedToken).safeTransfer(trades[tradeKey].user0, fillAcceptedObj.acceptedTokenAmountSent.sub(tradeCommissions.acceptedTokenCommission));
        IERC20(acceptedToken).safeTransfer(commissionAddress, tradeCommissions.acceptedTokenCommission);
      }
    }

    emit eventFillTrade(
      tradeId,
      trades[tradeKey].user0,
      uint8(trades[tradeKey].status),
      trades[tradeKey].fillCount,
      _msgSender(),
      token0FillAmount,
      acceptedToken,
      fillAcceptedObj.acceptedTokenAmountSent
    );
  }

  function updateAcceptedTokens(
    bytes32 tradeId,
    address[] memory acceptedTokens,
    uint256[] memory acceptedAmounts
  ) external onlyUser nonReentrant {

    require(contractEnabled == true);
    string memory tradeKey = _returnTradeKey(tradeId, _msgSender());
    require(trades[tradeKey].isExist);
    require(trades[tradeKey].user0 == _msgSender());
    require(trades[tradeKey].status == Status.Unfilled);
    require(acceptedTokens.length == acceptedAmounts.length);
    require(_validAcceptedTokens(trades[tradeKey].token0, acceptedTokens) == true);
    require(_validAcceptedAmounts(acceptedAmounts) == true);

    trades[tradeKey].acceptedTokens = acceptedTokens;
    trades[tradeKey].acceptedAmounts = acceptedAmounts;

    emit eventUpdateAcceptedTokens(
      tradeId,
      trades[tradeKey].user0,
      acceptedTokens,
      acceptedAmounts
    );
  }

  function cancelTrade(
    bytes32 tradeId
  ) external onlyUser payable nonReentrant {

    require(contractEnabled == true);
    string memory tradeKey = _returnTradeKey(tradeId, _msgSender());
    require(trades[tradeKey].isExist);
    require(trades[tradeKey].status == Status.Unfilled);
    require(trades[tradeKey].user0 == _msgSender());

    trades[tradeKey].status = Status.Cancelled;

    if (trades[tradeKey].token0 == address(0)) {
      payable(_msgSender()).transfer(trades[tradeKey].token0AmountRemaining);
    } else {
      require(IERC20(trades[tradeKey].token0).balanceOf(address(this)) >= trades[tradeKey].token0AmountRemaining);
      IERC20(trades[tradeKey].token0).safeTransfer(address(_msgSender()), trades[tradeKey].token0AmountRemaining);
    }

    uint256 refundAmount = trades[tradeKey].token0AmountRemaining;
    trades[tradeKey].token0AmountRemaining = 0;

    emit eventCancelTrade(
      tradeId,
      trades[tradeKey].user0,
      trades[tradeKey].token0,
      trades[tradeKey].token0Amount,
      uint8(trades[tradeKey].status),
      trades[tradeKey].fillCount,
      refundAmount
    );
  }

  function _tokenIsAccepted(address acceptedToken, address[] memory acceptedTokens) internal pure returns (bool) {
    uint256 arrayLength = acceptedTokens.length;
    for (uint i = 0; i < arrayLength; i++) {
      if (acceptedTokens[i] == acceptedToken) {
        return true;
      }
    }
    return false;
  }

  function _validAcceptedTokens(address token0, address[] memory acceptedTokens) internal view returns (bool) {
    uint256 arrayLength = acceptedTokens.length;
    if (arrayLength < 1 || arrayLength > maxAcceptedTokens) {
      return false;
    }
    for (uint i = 0; i < arrayLength; i++) {
      if (acceptedTokens[i] == token0) {
        return false;
      }
    }
    return true;
  }

  function _validAcceptedAmounts(uint256[] memory acceptedAmounts) internal pure returns (bool) {
    uint256 arrayLength = acceptedAmounts.length;
    for (uint i = 0; i < arrayLength; i++) {
      if (acceptedAmounts[i] == 0) {
        return false;
      }
    }
    return true;
  }

  function _getAcceptedAmount(address acceptedToken, address[] memory acceptedTokens, uint256[] memory acceptedAmounts) internal pure returns (uint256) {
    uint arrayLength = acceptedTokens.length;
    for (uint i = 0; i < arrayLength; i++) {
      if (acceptedTokens[i] == acceptedToken) {
        return acceptedAmounts[i];
      }
    }
    return 0;
  }

  function _returnFillKey(bytes32 tradeId, uint256 fillCount) internal pure returns (string memory) {
    return string(abi.encodePacked(tradeId, '||', fillCount));
  }

  function _returnTradeKey(bytes32 tradeId, address user0) internal pure returns (string memory) {
    return string(abi.encodePacked(tradeId, '||', user0));
  }

  function getTrade(bytes32 tradeId, address user0) public view returns (Trade memory trade) {
    string memory tradeKey = _returnTradeKey(tradeId, user0);
    return trades[tradeKey];
  }

  function getFill(bytes32 tradeId, uint256 fillCount) public view returns (Filler memory fill) {
    string memory fillKey = _returnFillKey(tradeId, fillCount);
    return fills[fillKey];
  }

  function getRequiredAcceptedAmount(
    bytes32 tradeId,
    address user0,
    address acceptedToken,
    uint256 token0FillAmount
  ) public view returns (uint256 acceptedTokenAmountSent) {

    string memory tradeKey = _returnTradeKey(tradeId, user0);
    require(trades[tradeKey].isExist);

    uint256 acceptedAmount = _getAcceptedAmount(acceptedToken, trades[tradeKey].acceptedTokens, trades[tradeKey].acceptedAmounts);
    return acceptedAmount.mul(token0FillAmount).div(trades[tradeKey].token0Amount);
  }
}

