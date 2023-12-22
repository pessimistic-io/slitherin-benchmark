// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./ERC20Upgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";

interface IFLUID {
  function onWrap(address to_, uint256 amount_) external;
}

/// @title Registered Fluid Shares
/// @author Fluid Finance SA
/// @notice Registered equity shares in the Fluid Finance SA
contract rFLUID is ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlEnumerableUpgradeable {

  address public constant WRAPPED_TOKENS = address(0x000000000000000000000000000000000000FFff);

  bytes32 public constant TOKEN_UPDATER_ROLE = keccak256("TOKEN_UPDATER_ROLE");
  bytes32 public constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");

  uint8 internal constant DECIMALS_VALUE = 0;

  mapping (address => bool) public whitelist;
    
  IFLUID public FLUID;
  
  event SetFLUID(address FLUID);
  event RegisteredRFLUID(address indexed account, uint256 amount);
  event UnregisteredRFLUID(address indexed account, uint256 amount);
  event WhitelistAdded(address indexed account);
  event WhitelistRemoved(address indexed account);
  event NotWhitelisted(address indexed account);
  
  modifier onlyFLUID {
    require(msg.sender == address(FLUID), 'caller is not FLUID');
    _;
  }
  
  function initialize(
    string calldata name_, 
    string calldata symbol_,
    address admin_,
    address tokenUpdater_,
    address whitelister_,
    uint256 initialSupply_,
    address initialSupplyRecipient_
  ) public initializer {
    require(admin_ != address(0), "admin_ is address zero");
    require(tokenUpdater_ != address(0), "tokenUpdater_ is address zero");
    require(whitelister_ != address(0), "whitelister_ is address zero");
    require(initialSupply_ > 0, "initialSupply_ is zero");
    require(initialSupplyRecipient_ != address(0), "initialSupplyRecipient_ is address zero");
    
    ERC20Upgradeable.__ERC20_init(name_, symbol_);
    ERC20PermitUpgradeable.__ERC20Permit_init(name_);
    AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, admin_);
    _setupRole(TOKEN_UPDATER_ROLE, tokenUpdater_);
    _setupRole(WHITELISTER_ROLE, whitelister_);
    
    whitelist[initialSupplyRecipient_] = true;
    emit WhitelistAdded(initialSupplyRecipient_);
    
    _mint(initialSupplyRecipient_, initialSupply_);
  }
  
  function setFLUID(address FLUID_) external onlyRole(TOKEN_UPDATER_ROLE) {
    require(address(FLUID) == address(0), "FLUID already set");
    require(FLUID_ != address(0), "FLUID_ is 0x0");
    FLUID = IFLUID(FLUID_);
    emit SetFLUID(FLUID_);
  }
  
  function _beforeTokenTransfer(
    address from_,
    address to_,
    uint256 amount_
  ) internal override {
    if (from_ != address(0) && from_ != WRAPPED_TOKENS) {
      require(whitelist[from_], "sender not whitelisted");
    }
    if (to_ != address(0) && to_ != WRAPPED_TOKENS) {
      require(whitelist[to_], "recipient not whitelisted");
    }
      
    super._beforeTokenTransfer(from_, to_, amount_);
  }
  
  function onRegister(
    address recipient_,
    uint256 amount_
  ) external onlyFLUID {
    require(amount_ > 0, "cannot register zero");
    _transfer(WRAPPED_TOKENS, recipient_, amount_);
    emit RegisteredRFLUID(recipient_, amount_);
  }
  
  // turn rFLUID into FLUID
  function wrap(uint256 amount_) external {
    require(address(FLUID) != address(0), 'FLUID not set');
    require(amount_ > 0, "cannot wrap zero tokens");
    require(balanceOf(msg.sender) >= amount_, 'not enough tokens');
    _transfer(msg.sender, WRAPPED_TOKENS, amount_);
    // FLUID has 18 decimals so we need to convert to 18 decimals
    FLUID.onWrap(msg.sender, amount_ * 1e18);    
    emit UnregisteredRFLUID(msg.sender, amount_);
  }
  
  function decimals() public pure override returns (uint8) {
    return DECIMALS_VALUE;
  }
  
  function addToWhitelist(address _account) public onlyRole(WHITELISTER_ROLE) {
    require(_account != address(0), "cannot whitelist address zero");
    require(!whitelist[_account], "already whitelisted");
    whitelist[_account] = true;
    emit WhitelistAdded(_account);
  }

  function batchAddToWhitelist(address[] calldata _accounts) external onlyRole(WHITELISTER_ROLE) {
    for (uint256 i = 0; i < _accounts.length; i++) {
      addToWhitelist(_accounts[i]);
    }
  }

  function removeFromWhitelist(address _account) external onlyRole(WHITELISTER_ROLE) {
    require(whitelist[_account], "not in whitelist");
    whitelist[_account] = false;
    emit WhitelistRemoved(_account);
  }
}
