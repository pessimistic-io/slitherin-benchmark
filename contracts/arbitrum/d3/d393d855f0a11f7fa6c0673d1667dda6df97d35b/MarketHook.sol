// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IHook} from "./IHook.sol";
import {IPrePOMarket} from "./IPrePOMarket.sol";
import {IAccountList, AccountListCaller} from "./AccountListCaller.sol";
import {AllowedMsgSenders} from "./AllowedMsgSenders.sol";
import {SafeOwnable} from "./SafeOwnable.sol";
import {ITokenSender, TokenSenderCaller} from "./TokenSenderCaller.sol";
import {TreasuryCaller} from "./TreasuryCaller.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract MarketHook is
  IHook,
  AccountListCaller,
  ReentrancyGuard,
  SafeOwnable,
  TokenSenderCaller,
  TreasuryCaller
{
  function hook(
    address funder,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee,
    bytes calldata
  ) external virtual override nonReentrant {
    if (address(_accountList) != address(0) && _accountList.isIncluded(funder))
      return;
    uint256 fee = amountBeforeFee - amountAfterFee;
    if (fee == 0) return;
    IPrePOMarket(msg.sender).getCollateral().transferFrom(
      msg.sender,
      _treasury,
      fee
    );
    if (address(_tokenSender) == address(0)) return;
    uint256 scaledFee = (fee * _accountToAmountMultiplier[msg.sender]) /
      PERCENT_UNIT;
    if (scaledFee == 0) return;
    _tokenSender.send(recipient, scaledFee);
  }

  function hook(
    address funder,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee
  ) external virtual override nonReentrant {
    if (address(_accountList) != address(0) && _accountList.isIncluded(funder))
      return;
    uint256 fee = amountBeforeFee - amountAfterFee;
    if (fee == 0) return;
    IPrePOMarket(msg.sender).getCollateral().transferFrom(
      msg.sender,
      _treasury,
      fee
    );
    if (address(_tokenSender) == address(0)) return;
    uint256 scaledFee = (fee * _accountToAmountMultiplier[msg.sender]) /
      PERCENT_UNIT;
    if (scaledFee == 0) return;
    _tokenSender.send(recipient, scaledFee);
  }

  function setAccountList(IAccountList accountList)
    public
    virtual
    override
    onlyOwner
  {
    super.setAccountList(accountList);
  }

  function setTreasury(address _treasury) public override onlyOwner {
    super.setTreasury(_treasury);
  }

  function setAmountMultiplier(address account, uint256 amountMultiplier)
    public
    override
    onlyOwner
  {
    super.setAmountMultiplier(account, amountMultiplier);
  }

  function setTokenSender(ITokenSender tokenSender) public override onlyOwner {
    super.setTokenSender(tokenSender);
  }
}

