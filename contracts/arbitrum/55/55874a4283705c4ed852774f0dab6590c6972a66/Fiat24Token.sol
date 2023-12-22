// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./Fiat24Account.sol";

contract Fiat24Token is ERC20PausableUpgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public ChfRate;
    uint256 public LimitWalkin;
    uint256 internal WithdrawCharge;
    uint256 private constant MINIMALCOMMISIONFEE = 10;
    Fiat24Account fiat24account;

    function __Fiat24Token_init_(address fiat24accountProxyAddress,
                               string memory name_,
                               string memory symbol_,
                               uint256 limitWalkin,
                               uint256 chfRate,
                               uint256 withdrawCharge) internal initializer {
      __Context_init_unchained();
      __AccessControl_init_unchained();
      __ERC20_init_unchained(name_, symbol_);
      _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
      _setupRole(OPERATOR_ROLE, _msgSender());
      fiat24account = Fiat24Account(fiat24accountProxyAddress);
      LimitWalkin = limitWalkin;
      ChfRate = chfRate;
      WithdrawCharge = withdrawCharge;
  }

  function mint(uint256 amount) public {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24Token: Not an operator");
    _mint(fiat24account.ownerOf(9101), amount);
  }

  function burn(uint256 amount) public {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24Token: Not an operator");
    _burn(fiat24account.ownerOf(9104), amount);
  }

  function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
    if(recipient == fiat24account.ownerOf(9102)) {
      _transfer(_msgSender(), recipient, amount.sub(WithdrawCharge, "Fiat24Token: Withdraw charge exceeds withdraw amount"));
      _transfer(_msgSender(), fiat24account.ownerOf(9202), WithdrawCharge);
    } else {
      if(fiat24account.balanceOf(recipient) > 0 && fiat24account.isMerchant(fiat24account.historicOwnership(recipient))) {
          uint256 commissionFee = amount.mul(fiat24account.merchantRate(fiat24account.historicOwnership(recipient))).div(10000);
          if(commissionFee >= MINIMALCOMMISIONFEE) {
            _transfer(_msgSender(), recipient, amount.sub(commissionFee, "Fiat24Token: Commission fee exceeds payment amount"));
            _transfer(_msgSender(), fiat24account.ownerOf(9201), commissionFee);
          } else {
            _transfer(_msgSender(), recipient, amount);
          }
      } else {
        _transfer(_msgSender(), recipient, amount);
      }
    }
    return true;
  }

  function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
    if(recipient == fiat24account.ownerOf(9102)) {
      _transfer(sender, recipient, amount.sub(WithdrawCharge, "Fiat24Token: Withdraw charge exceeds withdraw amount"));
      _transfer(sender, fiat24account.ownerOf(9202), WithdrawCharge);
    } else {
      if(fiat24account.balanceOf(recipient) > 0 && fiat24account.isMerchant(fiat24account.historicOwnership(recipient))) {
          uint256 commissionFee = amount.mul(fiat24account.merchantRate(fiat24account.historicOwnership(recipient))).div(10000);
          if(commissionFee >= MINIMALCOMMISIONFEE) {
            _transfer(sender, recipient, amount.sub(commissionFee, "Fiat24Token: Commission fee exceeds payment amount"));
            _transfer(sender, fiat24account.ownerOf(9201), commissionFee);
          } else {
            _transfer(sender, recipient, amount);
          }
      } else {
        _transfer(sender, recipient, amount);
      }
    }

    uint256 currentAllowance = allowance(sender, _msgSender());
    require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }

    return true;
  }

  function transferByAccountId(uint256 recipientAccountId, uint256 amount) public returns(bool){
    return transfer(fiat24account.ownerOf(recipientAccountId), amount);
  }

  function balanceOfByAccountId(uint256 accountId) public view returns(uint256) {
    return balanceOf(fiat24account.ownerOf(accountId));
  }

  function tokenTransferAllowed(address from, address to, uint256 amount) public view returns(bool){
    require(!fiat24account.paused(), "Fiat24Token: All account transfers are paused");
    require(!paused(), "Fiat24Token: All account transfers of this currency are paused");
    if(from != address(0) && to != address(0)){
      if(balanceOf(from) < amount) {
          return false;
      }
      uint256 toAmount = amount + balanceOf(to);
      Fiat24Account.Status fromClientStatus;
      uint256 accountIdFrom = fiat24account.historicOwnership(from);
      if(accountIdFrom != 0) {
        fromClientStatus = fiat24account.status(accountIdFrom);
      } else if(from != address(0) && fiat24account.balanceOf(from) > 0) {
        fromClientStatus = Fiat24Account.Status.Tourist;
        accountIdFrom = fiat24account.tokenOfOwnerByIndex(from, 0);
      } else {
        fromClientStatus = Fiat24Account.Status.Na;
      }
      Fiat24Account.Status toClientStatus;
      uint256 accountIdTo = fiat24account.historicOwnership(to);
      if(accountIdTo != 0) {
        toClientStatus = fiat24account.status(accountIdTo);
      } else if(to != address(0) && fiat24account.balanceOf(to) > 0) {
        toClientStatus = Fiat24Account.Status.Tourist;
        accountIdTo = fiat24account.tokenOfOwnerByIndex(to, 0);
      } else {
        toClientStatus = Fiat24Account.Status.Na;
      }
      uint256 amountInChf = convertToChf(amount);
      bool fromLimitCheck = fiat24account.checkLimit(accountIdFrom, amountInChf);
      bool toLimitCheck = fiat24account.checkLimit(accountIdTo, amountInChf);
      return ((fromClientStatus == Fiat24Account.Status.Live || fromClientStatus == Fiat24Account.Status.Tourist) &&
            (toClientStatus == Fiat24Account.Status.Live || toClientStatus == Fiat24Account.Status.Tourist || toClientStatus == Fiat24Account.Status.SoftBlocked) &&
            fromLimitCheck && toLimitCheck) ||
            ((fromClientStatus == Fiat24Account.Status.Live || fromClientStatus == Fiat24Account.Status.Tourist) &&
            fromLimitCheck &&
            (toClientStatus == Fiat24Account.Status.Na && toAmount <= LimitWalkin));
    }
    return false;
  }

  function convertToChf(uint256 amount) public view returns(uint256) {
    return amount.mul(ChfRate).div(1000);
  }

  function convertFromChf(uint256 amount) public view returns(uint256) {
    return amount.mul(1000).div(ChfRate);
  }

  function setWithdrawCharge(uint256 withdrawCharge) public {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24Token: Not an operator");
    WithdrawCharge = withdrawCharge;
  }

  function sendToSundry(address from, uint256 amount) public {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24Token: Not an operator");
    _transfer(from, fiat24account.ownerOf(9103), amount);
  }

  function setWalkinLimit(uint256 newLimitWalkin) external {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24Account: Not an operator");
    LimitWalkin = newLimitWalkin;
  }

  function decimals() public view virtual override returns (uint8) {
    return 2;
  }

  function pause() public {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Fiat24Token: Not an admin");
    _pause();
  }

  function unpause() public {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Fiat24Token: Not an admin");
    _unpause();
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    require(!fiat24account.paused(), "Fiat24Token: all account transfers are paused");
    require(!paused(), "Fiat24Token: all account transfers of this currency are paused");
    if(from != address(0) && to != address(0) && to != fiat24account.ownerOf(9103) && from != fiat24account.ownerOf(9103)){
      require(tokenTransferAllowed(from, to, amount), "Fiat24Token: Transfer not allowed for various reason");
    }
    super._beforeTokenTransfer(from, to, amount);
  }

  function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    if(from != address(0) && to != address(0) && to != fiat24account.ownerOf(9103) && from != fiat24account.ownerOf(9103)){
      uint256 accountIdFrom = fiat24account.historicOwnership(from);
      if(accountIdFrom == 0 && fiat24account.balanceOf(from) > 0) {
        accountIdFrom = fiat24account.tokenOfOwnerByIndex(from, 0);
      }
      uint256 accountIdTo = fiat24account.historicOwnership(to);
      if(accountIdTo == 0 && fiat24account.balanceOf(to) > 0) {
        accountIdTo = fiat24account.tokenOfOwnerByIndex(to, 0);
      }
      fiat24account.updateLimit(accountIdFrom, convertToChf(amount));
      fiat24account.updateLimit(accountIdTo, convertToChf(amount));
    }
    super._afterTokenTransfer(from, to, amount);
  }
}

