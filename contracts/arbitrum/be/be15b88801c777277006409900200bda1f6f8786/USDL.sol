// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IUSDL.sol";

import "./UFragments.sol";
import "./Vault.sol";

import "./IERC20.sol";
import "./ExponentialNoError.sol";
import "./PausableUpgradeable.sol";

/// @title USDL token contract
/// @notice handles all minting/burning of usdl
/// @dev extends UFragments
contract USDL is Initializable, PausableUpgradeable, UFragments, IUSDL, ExponentialNoError {
  IERC20 public _reserve;
  IVaultController public _VaultController;

  address public _pauser;

  /// @notice checks if _msgSender() is VaultController
  modifier onlyVaultController() {
    require(_msgSender() == address(_VaultController), "only VaultController");
    _;
  }

  /// @notice checks if _msgSender() is pauser
  modifier onlyPauser() {
    require(_msgSender() == address(_pauser), "only pauser");
    _;
  }

  /// @notice any function with this modifier will call the pay_interest() function before any function logic is called
  modifier paysInterest() {
    _VaultController.calculateInterest();
    _;
  }

  /// @notice initializer for contract
  /// @param reserveAddr the address of USDC
  /// @dev consider adding decimals?
  function initialize(address reserveAddr) public override initializer {
    __UFragments_init("USDL Token", "USDL");
    __Pausable_init();
    _reserve = IERC20(reserveAddr);
  }

  ///@notice sets the pauser for both USDL and VaultController
  ///@notice the pauser is a separate role from the owner
  function setPauser(address pauser_) external override onlyOwner {
    _pauser = pauser_;
  }

  /// @notice pause contract, pauser only
  function pause() external override onlyPauser {
    _pause();
  }

  /// @notice unpause contract, pauser only
  function unpause() external override onlyPauser {
    _unpause();
  }

  ///@notice gets the pauser for both USDL and VaultController
  function pauser() public view returns (address) {
    return _pauser;
  }

  ///@notice gets the owner of the USDL contract
  function owner() public view override(IUSDL, OwnableUpgradeable) returns (address) {
    return super.owner();
  }

  /// @notice getter for name
  /// @return name of token
  function name() public view override(IERC20Metadata, ERC20Detailed) returns (string memory) {
    return super.name();
  }

  /// @notice getter for symbol
  /// @return symbol for token
  function symbol() public view override(IERC20Metadata, ERC20Detailed) returns (string memory) {
    return super.symbol();
  }

  /// @notice getter for decimals
  /// @return decimals for token
  function decimals() public view override(IERC20Metadata, ERC20Detailed) returns (uint8) {
    return super.decimals();
  }

  /// @notice getter for address of the reserve currency, or usdc
  /// @return decimals for of reserve currency
  function reserveAddress() public view override returns (address) {
    return address(_reserve);
  }

  /// @notice get the VaultController addr
  /// @return vaultcontroller addr
  function getVaultController() public view override returns (address) {
    return address(_VaultController);
  }

  /// @notice set the VaultController addr so that vault_master may mint/burn USDL without restriction
  /// @param vault_master_address address of vault master
  function setVaultController(address vault_master_address) external override onlyOwner {
    _VaultController = IVaultController(vault_master_address);
  }

  /// @notice deposit USDC to mint USDL
  /// @dev caller should obtain 1e12 USDL for each USDC
  /// the calculations for deposit mimic the calculations done by mint in the ampleforth contract, simply with the usdc transfer
  /// "fragments" are the units that we see, so 1000 fragments == 1000 USDL
  /// "gons" are the internal accounting unit, used to keep scale.
  /// we use the variable _gonsPerFragment in order to convert between the two
  /// try dimensional analysis when doing the math in order to verify units are correct
  /// @param usdc_amount amount of USDC to deposit
  function deposit(uint256 usdc_amount) external override {
    _deposit(usdc_amount, _msgSender());
  }

  function depositTo(uint256 usdc_amount, address target) external override {
    _deposit(usdc_amount, target);
  }

  function _deposit(uint256 usdc_amount, address target) internal paysInterest whenNotPaused {
    // scale the usdc_amount to the usdl decimal amount, aka 1e18. since usdc is 6 decimals, we multiply by 1e12
    uint256 amount = usdc_amount * 1e12;
    require(amount > 0, "Cannot deposit 0");
    // check allowance and ensure transfer success
    uint256 allowance = _reserve.allowance(target, address(this));
    require(allowance >= usdc_amount, "Insufficient Allowance");
    require(_reserve.transferFrom(target, address(this), usdc_amount), "transfer failed");
    // the gonbalances of the sender is in gons, therefore we must multiply the deposit amount, which is in fragments, by gonsperfragment
    _gonBalances[target] = _gonBalances[target] + amount * _gonsPerFragment;
    // total supply is in fragments, and so we add amount
    _totalSupply = _totalSupply + amount;
    // and totalgons of course is in gons, and so we multiply amount by gonsperfragment to get the amount of gons we must add to totalGons
    _totalGons = _totalGons + amount * _gonsPerFragment;

    emit Transfer(address(0), target, amount);
    emit Deposit(target, amount);
  }

  /// @notice withdraw USDC by burning USDL
  /// caller should obtain 1 USDC for every 1e12 USDL
  /// @param usdc_amount amount of USDC to withdraw
  function withdraw(uint256 usdc_amount) external override {
    _withdraw(usdc_amount, _msgSender());
  }

  ///@notice withdraw USDC to a specific address by burning USDL from the caller
  /// target should obtain 1 USDC for every 1e12 USDL burned from the caller
  /// @param usdc_amount amount of USDC to withdraw
  /// @param target address to receive the USDC
  function withdrawTo(uint256 usdc_amount, address target) external override {
    _withdraw(usdc_amount, target);
  }

  ///@notice business logic to withdraw USDC and burn USDL from the caller
  function _withdraw(uint256 usdc_amount, address target) internal paysInterest whenNotPaused {
    // scale the usdc_amount to the USDL decimal amount, aka 1e18
    uint256 amount = usdc_amount * 1e12;
    // check balances all around
    require(amount <= this.balanceOf(_msgSender()), "insufficient funds");
    require(amount > 0, "Cannot withdraw 0");
    uint256 balance = _reserve.balanceOf(address(this));
    require(balance >= usdc_amount, "Insufficient Reserve in Bank");
    // ensure transfer success
    require(_reserve.transfer(target, usdc_amount), "transfer failed");
    // modify the gonbalances of the sender, subtracting the amount of gons, therefore amount*gonsperfragment
    _gonBalances[_msgSender()] = _gonBalances[_msgSender()] - amount * _gonsPerFragment;
    // modify totalSupply and totalGons
    _totalSupply = _totalSupply - amount;
    _totalGons = _totalGons - amount * _gonsPerFragment;
    // emit both a Withdraw and transfer event
    emit Transfer(target, address(0), amount);
    emit Withdraw(target, amount);
  }

  /// @notice withdraw USDC by burning USDL
  /// caller should obtain 1 USDC for every 1e12 USDL
  /// this function is effectively just withdraw, but we calculate the amount for the sender
  function withdrawAll() external override {
    _withdrawAll(_msgSender());
  }

  /// @notice withdraw USDC by burning USDL
  /// @param target should obtain 1 USDC for every 1e12 USDL burned from caller
  /// this function is effectively just withdraw, but we calculate the amount for the target
  function withdrawAllTo(address target) external override {
    _withdrawAll(target);
  }

  /// @notice business logic for withdrawAll
  /// @param target should obtain 1 USDC for every 1e12 USDL burned from caller
  /// this function is effectively just withdraw, but we calculate the amount for the target
  function _withdrawAll(address target) internal paysInterest whenNotPaused {
    uint256 reserve = _reserve.balanceOf(address(this));
    require(reserve != 0, "Reserve is empty");
    uint256 usdc_amount = (this.balanceOf(_msgSender())) / 1e12;
    //user's USDL value is more than reserve
    if (usdc_amount > reserve) {
      usdc_amount = reserve;
    }
    uint256 amount = usdc_amount * 1e12;
    require(_reserve.transfer(target, usdc_amount), "transfer failed");
    // see comments in the withdraw function for an explaination of this math
    _gonBalances[_msgSender()] = _gonBalances[_msgSender()] - (amount * _gonsPerFragment);
    _totalSupply = _totalSupply - amount;
    _totalGons = _totalGons - (amount * _gonsPerFragment);
    // emit both a Withdraw and transfer event
    emit Transfer(target, address(0), amount);
    emit Withdraw(target, amount);
  }

  /// @notice admin function to mint USDL
  /// @param usdc_amount the amount of USDL to mint, denominated in USDC
  function mint(uint256 usdc_amount) external override paysInterest onlyOwner {
    require(usdc_amount != 0, "Cannot mint 0");
    uint256 amount = usdc_amount * 1e12;
    // see comments in the deposit function for an explaination of this math
    _gonBalances[_msgSender()] = _gonBalances[_msgSender()] + amount * _gonsPerFragment;
    _totalSupply = _totalSupply + amount;
    _totalGons = _totalGons + amount * _gonsPerFragment;
    // emit both a mint and transfer event
    emit Transfer(address(0), _msgSender(), amount);
    emit Mint(_msgSender(), amount);
  }

  /// @notice admin function to burn USDL
  /// @param usdc_amount the amount of USDL to burn, denominated in USDC
  function burn(uint256 usdc_amount) external override paysInterest onlyOwner {
    require(usdc_amount != 0, "Cannot burn 0");
    uint256 amount = usdc_amount * 1e12;
    // see comments in the deposit function for an explaination of this math
    _gonBalances[_msgSender()] = _gonBalances[_msgSender()] - amount * _gonsPerFragment;
    _totalSupply = _totalSupply - amount;
    _totalGons = _totalGons - amount * _gonsPerFragment;
    // emit both a mint and transfer event
    emit Transfer(_msgSender(), address(0), amount);
    emit Burn(_msgSender(), amount);
  }

  /// @notice donates usdc to the protocol reserve
  /// @param usdc_amount the amount of USDC to donate
  function donate(uint256 usdc_amount) external override paysInterest whenNotPaused {
    uint256 amount = usdc_amount * 1e12;
    require(amount > 0, "Cannot deposit 0");
    uint256 allowance = _reserve.allowance(_msgSender(), address(this));
    require(allowance >= usdc_amount, "Insufficient Allowance");
    require(_reserve.transferFrom(_msgSender(), address(this), usdc_amount), "transfer failed");
    _donation(amount);
  }

  /// @notice donates any USDC held by this contract to the USDL holders
  /// @notice accounts for any USDC that may have been sent here accidently
  /// @notice without this, any USDC sent to the contract could mess up the reserve ratio
  function donateReserve() external override onlyOwner whenNotPaused {
    uint256 totalUSDC = (_reserve.balanceOf(address(this))) * 1e12;
    uint256 totalLiability = truncate(_VaultController.totalBaseLiability() * _VaultController.interestFactor());
    require((totalUSDC + totalLiability) > _totalSupply, "No extra reserve");

    _donation((totalUSDC + totalLiability) - _totalSupply);
  }

  /// @notice function for the vaultController to mint
  /// @param target whom to mint the USDL to
  /// @param amount the amount of USDL to mint
  function vaultControllerMint(address target, uint256 amount) external override onlyVaultController {
    // see comments in the deposit function for an explaination of this math
    _gonBalances[target] = _gonBalances[target] + amount * _gonsPerFragment;
    _totalSupply = _totalSupply + amount;
    _totalGons = _totalGons + amount * _gonsPerFragment;
    emit Transfer(address(0), target, amount);
    emit Mint(target, amount);
  }

  /// @notice function for the vaultController to burn
  /// @param target whom to burn the USDL from
  /// @param amount the amount of USDL to burn
  function vaultControllerBurn(address target, uint256 amount) external override onlyVaultController {
    require(_gonBalances[target] > (amount * _gonsPerFragment), "USDL: not enough balance");
    // see comments in the withdraw function for an explaination of this math
    _gonBalances[target] = _gonBalances[target] - amount * _gonsPerFragment;
    _totalSupply = _totalSupply - amount;
    _totalGons = _totalGons - amount * _gonsPerFragment;
    emit Transfer(target, address(0), amount);
    emit Burn(target, amount);
  }

  /// @notice Allows VaultController to send USDC from the reserve
  /// @param target whom to burn the USDL from
  /// @param usdc_amount the amount of USDC to send
  function vaultControllerTransfer(address target, uint256 usdc_amount) external override onlyVaultController {
    // ensure transfer success
    require(_reserve.transfer(target, usdc_amount), "transfer failed");
  }

  /// @notice function for the vaultController to scale all USDL balances
  /// @param amount amount of USDL (e18) to donate
  function vaultControllerDonate(uint256 amount) external override onlyVaultController {
    _donation(amount);
  }

  /// @notice function for distributing the donation to all USDL holders
  /// @param amount amount of USDL to donate
  function _donation(uint256 amount) internal {
    _totalSupply = _totalSupply + amount;
    if (_totalSupply > MAX_SUPPLY) {
      _totalSupply = MAX_SUPPLY;
    }
    _gonsPerFragment = _totalGons / _totalSupply;
    emit Donation(_msgSender(), amount, _totalSupply);
  }

  /// @notice get reserve ratio
  /// @return e18_reserve_ratio USDL reserve ratio
  function reserveRatio() external view override returns (uint192 e18_reserve_ratio) {
    e18_reserve_ratio = safeu192(((_reserve.balanceOf(address(this)) * expScale) / _totalSupply) * 1e12);
  }
}

