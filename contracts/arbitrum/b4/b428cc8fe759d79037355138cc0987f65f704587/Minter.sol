// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

import "./IMinter.sol";

contract Minter is IMinter, ERC20, Ownable {
  using SafeERC20 for ERC20;

  struct Investor {
    uint cap;
    uint deposited;
  }

  address public immutable DEPOSIT_TOKEN;

  uint public immutable MIN_INVESTMENT_AMOUNT;
  uint public constant EARLY_BACKERS_SUPPLY = 150_000 ether;
  uint public constant TEAM_SUPPLY = 150_000 ether;
  uint public constant SUPPLY_CAP = EARLY_BACKERS_SUPPLY + TEAM_SUPPLY;
  uint public totalRaised;

  bool public isActive = true;

  mapping(address => Investor) public investor;

  event Whitelisted(address indexed user, uint cap);
  event WhitelistRemoved(address indexed user);
  event RaiseClosed(uint totalRaised);
  event Deposit(address indexed user, uint depositAmount, uint mintedAmount);
  event FundsPulled(address indexed recipient, address indexed token, uint amount);

  constructor(DeployParams memory params) ERC20(params.name, params.symbol) {
    DEPOSIT_TOKEN = params.depositToken;
    MIN_INVESTMENT_AMOUNT = params.minInvestmentAmount;
    _mint(msg.sender, TEAM_SUPPLY);
  }

  function whitelistOrEditCap(address user, uint cap) external onlyOwner {
    _requireMinimumInvestmentAmount(cap);

    Investor storage inv = investor[user];
    require(inv.deposited <= cap, 'Minter: Cap must be higher than deposited amount');
    require(inv.cap != cap, 'Minter: Cap already set');

    inv.cap = cap;

    if (cap != 0) {
      emit Whitelisted(user, cap);
    } else {
      emit WhitelistRemoved(user);
    }
  }

  function closeRaise() external onlyOwner {
    _closeRaise();
    uint remainingToMint = SUPPLY_CAP - totalSupply();
    _mint(msg.sender, remainingToMint);
  }

  function deposit(uint amount) external {
    require(isActive, 'Minter: Raise is no longer active');

    Investor storage inv = investor[msg.sender];
    if (inv.deposited == 0) _requireMinimumInvestmentAmount(amount);

    require(inv.cap != 0, 'Minter: User not whitelisted');
    require(inv.deposited != inv.cap, 'Minter: Investor cap already reached');

    (uint depositAmount, uint mintAmount) = _validateDepositAmount(amount, inv.deposited, inv.cap);

    if (totalSupply() + mintAmount == SUPPLY_CAP) _closeRaise();

    ERC20(DEPOSIT_TOKEN).safeTransferFrom(msg.sender, address(this), depositAmount);
    inv.deposited += depositAmount;
    totalRaised += depositAmount;

    _mint(msg.sender, mintAmount);

    emit Deposit(msg.sender, depositAmount, mintAmount);
  }

  function pullFunds(address recipient, address token) external onlyOwner {
    uint amount = ERC20(token).balanceOf(address(this));
    ERC20(token).safeTransfer(recipient, amount);
    emit FundsPulled(recipient, token, amount);
  }

  function _closeRaise() internal {
    require(isActive, 'Minter: Raise already closed');
    isActive = false;
    emit RaiseClosed(totalRaised);
  }

  function _requireMinimumInvestmentAmount(uint _amount) internal view {
    require(_amount >= MIN_INVESTMENT_AMOUNT, 'Minter: Amount must be higher than minimum investment amount');
  }

  function _validateDepositAmount(
    uint _amount,
    uint _prevDeposited,
    uint _cap
  ) internal view returns (uint _validatedDepositAmount, uint _mintAmount) {
    // Checks to see if user has already deposited before and is not overflowing their cap
    // If cap is overflown only deposit up to the cap.
    _validatedDepositAmount = _validateMaximumAllowed(_amount, _prevDeposited, _cap);

    // Checks if user can mint all the tokens from the depositAmount without going over maximum supply
    uint cacheAmountToMint = (_validatedDepositAmount * 10 ** decimals()) / 10 ** ERC20(DEPOSIT_TOKEN).decimals();
    _mintAmount = _validateMaximumAllowed(cacheAmountToMint, totalSupply(), SUPPLY_CAP);

    // If user has gone over the maxSupply, recalculate the depositAmount
    _validatedDepositAmount = (cacheAmountToMint != _mintAmount)
      ? (_mintAmount * 10 ** ERC20(DEPOSIT_TOKEN).decimals()) / 10 ** decimals()
      : _validatedDepositAmount;
  }

  function _validateMaximumAllowed(
    uint _inputAmount,
    uint _currentAmount,
    uint _maximumAmount
  ) internal pure returns (uint _maximumAllowed) {
    _maximumAllowed = _inputAmount + _currentAmount > _maximumAmount ? _maximumAmount - _currentAmount : _inputAmount;
  }
}

