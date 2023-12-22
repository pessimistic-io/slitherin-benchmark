// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IXGrailToken.sol";

contract VestingWallet is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => uint256) public beneficiariesShare;
  EnumerableSet.AddressSet private _beneficiariesWallet;

  IERC20 public immutable grailToken;
  IXGrailToken public immutable xgrailToken;
  address public reserveWallet;

  bool public inXgrail;

  uint256 public constant MAX_TOTAL_SHARE = 10000;
  uint256 public totalShare;

  uint256 public released;

  bool public nonRevocable;

  uint256 public constant START_TIME = 1670457600;
  uint256 public constant DURATION = 3 * 365 days; // 3 years

  constructor (IERC20 grailToken_, IXGrailToken xgrailToken_, bool inXgrail_, address reserveWallet_){
    grailToken = grailToken_;
    xgrailToken = xgrailToken_;
    inXgrail = inXgrail_;
    reserveWallet = reserveWallet_;

    if(inXgrail_) {
      grailToken_.approve(address(xgrailToken_), type(uint256).max);
    }
  }

  event Released(uint256 releasedAmount);
  event RevokeVesting();

  function nbBeneficiaries() external view returns (uint256){
    return _beneficiariesWallet.length();
  }

  function beneficiary(uint256 index) external view returns (address){
    return _beneficiariesWallet.at(index);
  }

  function releasable() public view returns (uint256){
    if (block.timestamp < START_TIME) return 0;
    uint256 _balance = grailToken.balanceOf(address(this));
    if (block.timestamp > START_TIME.add(DURATION)) return _balance;

    return _balance.add(released).mul(block.timestamp.sub(START_TIME)).div(DURATION).sub(released);
  }

  function release() external {
    _release();
  }

  function updateBeneficiary(address wallet, uint256 newShare) external onlyOwner {
    _release();

    totalShare = totalShare.sub(beneficiariesShare[wallet]).add(newShare);
    require(totalShare <= MAX_TOTAL_SHARE, "allocation too high");
    beneficiariesShare[wallet] = newShare;
    if (newShare == 0) _beneficiariesWallet.remove(wallet);
    else _beneficiariesWallet.add(wallet);
  }

  function updateReserveWallet(address newReserveWallet) external onlyOwner {
    reserveWallet = newReserveWallet;
  }


  function setToNonRevocable() external onlyOwner {
    nonRevocable = true;
  }

  function revoke() external onlyOwner {
    require(!nonRevocable, "revoke not allowed");
    uint256 _balance = grailToken.balanceOf(address(this));
    grailToken.transfer(owner(), _balance);
    emit RevokeVesting();
  }

  function _release() internal {
    uint256 nbBeneficiaries_ = _beneficiariesWallet.length();
    uint256 releasable_ = releasable();

    uint256 remaining = releasable_;
    for (uint256 i = 0; i < nbBeneficiaries_; ++i) {
      address wallet = _beneficiariesWallet.at(i);
      uint256 beneficiaryShare = beneficiariesShare[wallet];
      uint256 beneficiaryAmount = releasable_.mul(beneficiaryShare).div(MAX_TOTAL_SHARE);
      remaining = remaining.sub(beneficiaryAmount);
      if(inXgrail && beneficiaryAmount > 0) xgrailToken.convertTo(beneficiaryAmount, wallet);
      else if(!inXgrail) grailToken.safeTransfer(wallet, beneficiaryAmount);
    }

    if (remaining > 0) {
      xgrailToken.convertTo(remaining, reserveWallet);
    }
    released = released.add(releasable_);
    emit Released(releasable_);
  }
}
