// SPDX-License-Identifier: NONE
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Math.sol";
import "./IFixedRateMarket.sol";
import "./IQAdmin.sol";
import "./IQToken.sol";
import "./CustomErrors.sol";
import "./Utils.sol";

contract QToken is Initializable, ERC20Upgradeable, IQToken {
  
  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[50] __gap;
  
  /// @notice Contract storing all global Qoda parameters
  IQAdmin private _qAdmin;
  
  /// @notice Contract where trade execution is done and where current token contract belongs to
  IFixedRateMarket private _fixedRateMarket;
  
  /// @notice Storage for qTokens redeemed so far by a user
  /// account => qTokensRedeemed
  mapping(address => uint) private _tokensRedeemed;

  /// @notice Tokens redeemed across all users so far
  uint private _tokensRedeemedTotal;
  
  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;
  
  /// @notice Same as _status in `@openzeppelin/contracts/security/ReentrancyGuard.sol`
  /// Reconstruct here instead of inheritance is to avoid storage slot sequence problem 
  /// during contract upgrade, as well as saving contract size with use of custom error
  uint256 private _status;
  
  /// @notice Constructor for upgradeable contracts
  /// @param qAdminAddr_ Address of the `QAdmin` contract
  /// @param fixedRateMarketAddr_ Address of market where this qToken contract belongs to
  /// @param name_ Name of the market's ERC20 token
  /// @param symbol_ Symbol of the market's ERC20 token
  function initialize(
                      address qAdminAddr_,
                      address fixedRateMarketAddr_,
                      string memory name_,
                      string memory symbol_
                      ) public initializer {
    __ERC20_init(name_, symbol_);
    _qAdmin = IQAdmin(qAdminAddr_);
    _fixedRateMarket = IFixedRateMarket(fixedRateMarketAddr_);
  }
  
  modifier onlyMarket() {
    if (!_qAdmin.hasRole(_qAdmin.MARKET_ROLE(), msg.sender)) {
      revert CustomErrors.QTK_OnlyMarket();
    }
    _;
  }
  
  /// @notice Modifier which checks that contract and specified operation is not paused
  modifier whenNotPaused(uint operationId) {
    if (_qAdmin.isPaused(address(this), operationId)) {
      revert CustomErrors.QTK_OperationPaused(operationId);
    }
    _;
  }
  
  /// @notice Logic copied from `@openzeppelin/contracts/security/ReentrancyGuard.sol`
  /// Reconstruct here instead of inheritance is to avoid storage slot sequence problem during
  /// contract upgrade
  modifier nonReentrant() {
    // On the first call to nonReentrant, _notEntered will be true
    if (_status == _ENTERED) {
      revert CustomErrors.QTK_ReentrancyDetected();
    }

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;

    _;

    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }
  
  /** USER INTERFACE **/
  
  /// @notice This function allows net lenders to redeem qTokens for the
  /// underlying token. Redemptions may only be permitted after loan maturity
  /// plus `_maturityGracePeriod`. The public interface redeems specified amount
  /// of qToken from existing balance.
  /// @param amount Amount of qTokens to redeem
  /// @return uint Amount of qTokens redeemed
  function redeemQTokensByRatio(uint amount) external nonReentrant whenNotPaused(801) returns(uint) {
    return _redeemQTokensByRatio(amount, false);
  }

  /// @notice This function allows net lenders to redeem qTokens for the
  /// underlying token. Redemptions may only be permitted after loan maturity
  /// plus `_maturityGracePeriod`. The public interface redeems the entire qToken
  /// balance.
  /// @return uint Amount of qTokens redeemed
  function redeemAllQTokensByRatio() external nonReentrant whenNotPaused(801) returns(uint) {
    return _redeemQTokensByRatio(_redeemableQTokens(msg.sender), false);
  }
  
  /// @notice This function allows net lenders to redeem qTokens for ETH.
  /// Redemptions may only be permitted after loan maturity plus 
  /// `_maturityGracePeriod`. The public interface redeems specified amount
  /// of qToken from existing balance.
  /// @param amount Amount of qTokens to redeem
  /// @return uint Amount of qTokens redeemed
  function redeemQTokensByRatioWithETH(uint amount) external nonReentrant whenNotPaused(801) returns(uint) {
    if (address(_fixedRateMarket.underlyingToken()) != _qAdmin.WETH()) {
      revert CustomErrors.QTK_EthOperationNotPermitted();
    }
    return _redeemQTokensByRatio(amount, true);
  }
  
  /// @notice This function allows net lenders to redeem qTokens for ETH.
  /// Redemptions may only be permitted after loan maturity plus
  /// `_maturityGracePeriod`. The public interface redeems the entire qToken
  /// balance.
  /// @return uint Amount of qTokens redeemed
  function redeemAllQTokensByRatioWithETH() external nonReentrant whenNotPaused(801) returns(uint) {
    if (address(_fixedRateMarket.underlyingToken()) != _qAdmin.WETH()) {
      revert CustomErrors.QTK_EthOperationNotPermitted();
    }
    return _redeemQTokensByRatio(_redeemableQTokens(msg.sender), true);
  }
  
  /** VIEW FUNCTIONS **/
  
  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address) {
    return address(_qAdmin);
  }
  
  /// @notice Gets the address of the `FixedRateMarket` contract
  /// @return address Address of `FixedRateMarket` contract
  function fixedRateMarket() external view returns(address) {
    return address(_fixedRateMarket);
  }
  
  /// @notice Get the address of the ERC20 token which the loan will be denominated
  /// @return IERC20
  function underlyingToken() external view returns(IERC20) {
    return _fixedRateMarket.underlyingToken();
  }
  
  /// @notice Get amount of qTokens user can redeem based on current loan repayment ratio
  /// @return uint amount of qTokens user can redeem
  function redeemableQTokens() external view returns(uint) {
    return _redeemableQTokens(msg.sender);
  }

  /// @notice Get amount of qTokens user can redeem based on current loan repayment ratio
  /// @param account Account to query
  /// @return uint amount of qTokens user can redeem
  function redeemableQTokens(address account) external view returns(uint) {
    return _redeemableQTokens(account);
  }
  
  /// @notice Gets the current `redemptionRatio` where owned qTokens can be redeemed up to
  /// @return uint redemption ratio, capped and scaled by 1e18
  function redemptionRatio() external view returns(uint) {
    return _redeemableQTokensByRatio(_qAdmin.MANTISSA_DEFAULT());
  }
  
  /// @notice Tokens redeemed from message sender so far
  /// @return uint Token redeemed by message sender
  function tokensRedeemed() external view returns(uint) {
    return _tokensRedeemed[msg.sender];
  }
  
  /// @notice Tokens redeemed from given account so far
  /// @param account Account to query
  /// @return uint Token redeemed by given account
  function tokensRedeemed(address account) external view returns(uint) {
    return _tokensRedeemed[account];
  }

  /// @notice Tokens redeemed across all users so far
  function tokensRedeemedTotal() external view returns(uint) {
    return _tokensRedeemedTotal;
  }
  
  /** INTERNAL FUNCTIONS **/

  /// @notice Internal function for lender to redeem qTokens after maturity
  /// please see `redeemQTokensByRatio()` for parameter and return value description
  /// @param amount Amount of qTokens to redeem
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint Amount of qTokens redeemed
  function _redeemQTokensByRatio(uint amount, bool isPaidInETH) internal returns(uint) {
    // Redeem is not possible if targeted redeemable amount is zero  
    if (amount <= 0) {
      revert CustomErrors.QTK_ZeroRedeemAmount();
    }
    
    // Enforce maturity + grace period before allowing redemptions
    if (block.timestamp <= _fixedRateMarket.maturity() + _qAdmin.maturityGracePeriod()) {
      revert CustomErrors.QTK_CannotRedeemEarly();
    }

    // Amount to redeem must not exceed loan repayment ratio
    if (amount > _redeemableQTokens(msg.sender)) {
      revert CustomErrors.QTK_AmountExceedsRedeemable();
    }

    // Burn the qToken balance
    _burn(msg.sender, amount);

    // Increase redeemed amount
    _tokensRedeemed[msg.sender] += amount;
    _tokensRedeemedTotal += amount;

    // Release the underlying token back to the lender
    _fixedRateMarket._transferTokenOrETH(msg.sender, amount, false, isPaidInETH);
    
    // Update liquidity emissions upon market maturity (approximated by token redeem time)
    _fixedRateMarket._updateLiquidityEmissionsOnRedeem(0, 0);
    _fixedRateMarket._updateLiquidityEmissionsOnRedeem(1, 0);

    // Emit the event
    emit RedeemQTokens(msg.sender, amount);

    return amount;
  }
  
  /** INTERNAL VIEW FUNCTIONS **/

  /// @notice Get amount of qTokens user can redeem based on current loan repayment ratio
  /// @param userAddress Address of the account to check
  /// @return uint amount of qTokens user can redeem
  function _redeemableQTokens(address userAddress) internal view returns(uint) {
    uint held = balanceOf(userAddress);
    if (held <= 0) {
      return 0;
    }
    uint redeemed = _tokensRedeemed[userAddress];
    uint redeemable = _redeemableQTokensByRatio(held + redeemed);
    return redeemable > redeemed ? redeemable - redeemed : 0;
  }
  
  /// @notice Gets the current `redemptionRatio` where owned qTokens can be redeemed up to
  /// @param amount amount of qToken for ratio to be applied to
  /// @return uint redeemable qToken with `redemptionRatio` applied, capped by amount inputted
  function _redeemableQTokensByRatio(uint amount) internal view returns(uint) {
    IERC20 _underlying = _fixedRateMarket.underlyingToken();
    uint repaidTotal = _underlying.balanceOf(address(_fixedRateMarket)) + _tokensRedeemedTotal; // escrow + redeemed qTokens
    uint loanTotal = totalSupply() + _tokensRedeemedTotal; // redeemed tokens are also part of all minted qTokens
    uint ratio = repaidTotal * amount / loanTotal;
    return Math.min(ratio, amount);
  }
  
  /** ERC20 Implementation **/
  
  /// @notice Creates `amount` tokens and assigns them to `account`, increasing the total supply.
  /// @param account Account to receive qToken
  /// @param amount Amount of qToken to mint
  function mint(address account, uint256 amount) external onlyMarket whenNotPaused(803) {
    _mint(account, amount);
  }
  
  /// @notice Destroys `amount` tokens from `account`, reducing the total supply
  /// @param account Account to receive qToken
  /// @param amount Amount of qToken to mint
  function burn(address account, uint256 amount) external onlyMarket whenNotPaused(804) {
    _burn(account, amount);
  }

  /// @notice Number of decimal places of the qToken should match the number
  /// of decimal places of the underlying token
  /// @return uint8 Number of decimal places
  function decimals() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns(uint8) {
    return IERC20Metadata(address(_fixedRateMarket.underlyingToken())).decimals();
  }

  /// @notice This hook requires users trying to transfer their qTokens to only
  /// be able to transfer tokens in excess of their current borrows. This is to
  /// protect the protocol from users gaming the collateral management system
  /// by borrowing off of the qToken and then immediately transferring out the
  /// qToken to another address, leaving the borrowing account uncollateralized
  /// @param from Address of the sender
  /// @param to Address of the receiver
  /// @param amount Amount of tokens to send
  function _beforeTokenTransfer(
                                address from,
                                address to,
                                uint256 amount
                                ) internal virtual override {

    // Call parent hook first
    super._beforeTokenTransfer(from, to, amount);

    // Ignore hook for 0x000... address (e.g. _mint, _burn functions)
    if(from == address(0) || to == address(0)){
      return;
    }
    
    uint accountBorrow = _fixedRateMarket.accountBorrows(from);

    // Transfers rejected if borrows exceed lends
    if (balanceOf(from) <= accountBorrow) {
      revert CustomErrors.QTK_BorrowsMoreThanLends();
    }

    // Safe from underflow after previous require statement
    if (amount > balanceOf(from) - accountBorrow) {
      revert CustomErrors.QTK_AmountExceedsBorrows();
    }

  }

  /// @notice This hook requires users to automatically repay any borrows their
  /// accounts may still have after receiving the qTokens
  /// @param from Address of the sender
  /// @param to Address of the receiver
  /// @param amount Amount of tokens to send
  function _afterTokenTransfer(
                                address from,
                                address to,
                                uint256 amount
                                ) internal virtual override {

    // Call parent hook first
    super._afterTokenTransfer(from, to, amount);

    // Ignore hook for 0x000... address (e.g. _mint, _burn functions)
    if(from == address(0) || to == address(0)){
      return;
    }

    _fixedRateMarket._repayBorrowInQToken(to, amount);
  }
  
  /// @notice Transfer allows qToken to be transferred from one address to another, but if is called after maturity,
  /// redeemable amount will be subjected to current loan repayment ratio
  /// @param to Address of the receiver
  /// @param amount Amount of qTokens to send
  /// @return true if the transfer is successful
  function transfer(address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20Upgradeable) whenNotPaused(802) returns (bool) {
    return _transferFrom(msg.sender, to, amount);
  }

  /// @notice TransferFrom allows spender to transfer qToken to another account in users' behalf,
  /// but if is called after maturity, redeemable amount will be subjected to current loan repayment ratio
  /// @param from Address of the qToken owner
  /// @param to Address of the receiver
  /// @param amount Amount of qTokens to send
  /// @return true if the transfer is successful
  function transferFrom(address from, address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20Upgradeable) whenNotPaused(802) returns (bool) {
    return _transferFrom(from, to, amount);
  }

  /// @notice Internal function for spender to transfer qToken to another account in users' behalf,
  /// please see `transferFrom()` for parameter and return value description
  function _transferFrom(address from, address to, uint256 amount) internal returns (bool) {
    // After maturity, amount to redeem must not exceed loan repayment ratio
    uint maturity = _fixedRateMarket.maturity();
    if (block.timestamp > maturity) {
      if (block.timestamp <= maturity + _qAdmin.maturityGracePeriod()) {
        revert CustomErrors.QTK_CannotRedeemEarly();
      }
      uint redeemableTokens = _redeemableQTokens(from);
      if (amount > redeemableTokens) {
        revert CustomErrors.QTK_AmountExceedsRedeemable();
      }

      // qToken transferred away is considered the same as redeemed by the user
      // redeemed token in total does not change because qToken transferred still exist in the contract
      _tokensRedeemed[from] += amount;
    }
    if (from == msg.sender) {
      return super.transfer(to, amount);
    }
    return super.transferFrom(from, to, amount);
  }
  
  function approve(address spender, uint256 amount) public virtual override(ERC20Upgradeable, IERC20Upgradeable) whenNotPaused(802) returns (bool) {
    return super.approve(spender, amount);
  }

  function increaseAllowance(address spender, uint256 addedValue) public virtual override(ERC20Upgradeable) whenNotPaused(802) returns (bool) {
    return super.increaseAllowance(spender, addedValue);
  }

  function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override(ERC20Upgradeable) whenNotPaused(802) returns (bool) {
    return super.decreaseAllowance(spender, subtractedValue);
  }

}
