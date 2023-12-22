//  SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {WithdrawLoanHelper} from "./WithdrawHelper.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {ICToken} from "./compound_ICToken.sol";
import {IVault} from "./IFlashLoan.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {GLPHelper} from "./GLPHelper.sol";
import {SafeMath} from "./SafeMath.sol";
import {CTokenHelper} from "./CTokenHelper.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IVault, IFlashLoanRecipient} from "./IFlashLoan.sol";

contract WithdrawLever is WithdrawLoanHelper, ReentrancyGuard, IFlashLoanRecipient {
  using PriceHelper for IERC20;
  using SafeMath for uint;
  using GLPHelper for IERC20;
  using CTokenHelper for ICToken;

  uint public constant feeBase = 1e18;
  

  constructor(
    address _vault,
    address payable _feeRecipient,
    uint _withdrawFee
  ) {
    vault = IVault(_vault);
    feeRecipient = _feeRecipient;
    require(_withdrawFee < 1e18, "Error: Invalid fee");
    withdrawFee = _withdrawFee;
  }

  function setFees(uint _withdrawFee) external onlyOwner {
    require(_withdrawFee < 1e18, "Error: Invalid fee");
    withdrawFee = _withdrawFee;
  }

  function setFeeRecipient(address payable _feeRecipient) external onlyOwner {
    feeRecipient = _feeRecipient;
  }

  function getFeeAmount(uint256 baseAmount, uint fee) internal pure returns (uint256) {
    return baseAmount.mul(fee).div(feeBase);
  }

  function withdraw(
    ICToken redeemMarket,
    uint redeemAmount,
    ICToken[] memory repayMarkets,
    uint[] memory repayAmounts
  ) public nonReentrant {
    WithdrawParams memory params = WithdrawParams({
      account: msg.sender,
      redeemMarket: redeemMarket,
      redeemAmount: redeemAmount,
      repayMarkets: repayMarkets,
      repayAmounts: repayAmounts,
      maxSlippage: 10000 // default to .5%
    });
    withdrawInternal(params);
  }


  function withdraw(
    ICToken redeemMarket,
    uint redeemAmount,
    ICToken[] memory repayMarkets,
    uint[] memory repayAmounts,
    uint24 maxSlippage
  ) public nonReentrant {
    WithdrawParams memory params = WithdrawParams({
      account: msg.sender,
      redeemMarket: redeemMarket,
      redeemAmount: redeemAmount,
      repayMarkets: repayMarkets,
      repayAmounts: repayAmounts,
      maxSlippage: maxSlippage
    });
    withdrawInternal(params);
  }

  function withdrawInternal(
    WithdrawParams memory params
  ) internal {
    validateSequencer();
    IERC20[] memory tokens = new IERC20[](params.repayMarkets.length);
    for(uint i =0; i < params.repayMarkets.length; i++) {
      tokens[i] = params.repayMarkets[i].underlying();
    }

    uint256[] memory amounts = params.repayAmounts;

    setPendingWithdraw(params.account, params);

    makeFlashLoan(
      tokens,
      amounts,
      params.account
    );
  }

  function makeFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    address account
  ) internal {
    // debugLoan(tokens, amounts, data);
    vault.flashLoan(this, tokens, amounts, abi.encode(account));
  }

  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external onlyVault {
    address _account = abi.decode(userData, (address));
    // executions set pending for msg.sender in PositionHelper
    WithdrawParams memory data = getPendingWithdraw(_account);

    require(
      data.account != address(0) && data.account == _account,
      'Invalid Account'
    );

    // make the withdraw (includes tranfers to vault, feeReceiver, and user)
    leveragedWithdraw(tokens, amounts, feeAmounts, data);

    // Finally, delete the pending execution and set isPending(_account) to false
    removePendingWithdraw(_account);
  }

  modifier onlyVault() {
    require(msg.sender == address(vault), 'Only vault can call this');
    _;
  }
}

