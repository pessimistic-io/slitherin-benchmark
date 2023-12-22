// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./ERC20Upgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";

interface IrFLUID {
  function onRegister(address to_, uint256 amount_) external;
}

/// @title Wrapped Fluid Shares
/// @author Fluid Finance SA
/// @notice Wrapped registered equity shares in the Fluid Finance SA
contract FLUID is ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlEnumerableUpgradeable {

  bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");
  
  bytes32 public constant TOKENSALE_ROLE = keccak256("TOKENSALE_ROLE");
  
  uint8 internal constant DECIMALS_VALUE = 18;

  address public sellContract;

  uint256 public timelock;
  
  IrFLUID public rFLUID;
  
  event UnwrappedFLUID(address indexed account, uint256 amount);
  event WrappedFLUID(address indexed account, uint256 amount);

  event SellContractUpdated(address indexed account, address sellcontract);
  event TimelockUpdated(address indexed account, uint256 timelock);
  
  modifier onlyRFLUID {
    require(msg.sender == address(rFLUID), 'caller is not rFLUID');
    _;
  }
  
  function initialize(
    string calldata name_, 
    string calldata symbol_,
    uint256 timelock_,
    address admin_,
    address rFLUID_
  ) public initializer {
    require(timelock_ > block.timestamp, "timelock_ in the past");
    require(admin_ != address(0), "admin_ is address zero");
    require(rFLUID_ != address(0), "rFLUID_ is address zero");
    
    ERC20Upgradeable.__ERC20_init(name_, symbol_);
    ERC20PermitUpgradeable.__ERC20Permit_init(name_);
    AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();

    // can (re)assign any of the roles
    _setupRole(DEFAULT_ADMIN_ROLE, admin_);
    
    rFLUID = IrFLUID(rFLUID_);
    
    timelock = timelock_;

    sellContract = address(0x0000000000000000000000000000000000000001); // placeholder thats not address(0)
  }
  
  function _beforeTokenTransfer(
    address from_,
    address to_,
    uint256 amount_
  ) internal override {
    if (block.timestamp < timelock) {
      if (
        !hasRole(DEFAULT_ADMIN_ROLE, from_) &&
        !hasRole(AIRDROP_ROLE, from_) &&
        !hasRole(TOKENSALE_ROLE, from_) &&
        msg.sender != address(rFLUID) &&
        to_ != sellContract
      ) {
        revert('tokens still locked');    
      }
    }
      
    super._beforeTokenTransfer(from_, to_, amount_);
  }
      
  function onWrap(
    address recipient_,
    uint256 amount_
  ) external onlyRFLUID {
    require(recipient_ != address(0), "cannot wrap to address zero");
    require(amount_ > 0, "cannot wrap zero tokens");
    // rFLUID has 0 decimals, FLUID has 18 decimals, but that is already 
    // taken care of in rFLUID.wrap
    _mint(recipient_, amount_);
    emit WrappedFLUID(recipient_, amount_);
  }
  
  function register(
    uint256 amount_
  ) external {
    require(amount_ > 0, "cannot register zero tokens");
    // rFLUID has 0 decimals, FLUID has 18 decimals, we disallow
    // trying to register fractions of FLUID tokens
    require(amount_ % 1e18 == 0, "can only register whole tokens");
    require(balanceOf(msg.sender) >= amount_, 'not enough tokens');
    _burn(msg.sender, amount_);
    rFLUID.onRegister(msg.sender, amount_ / 1e18);
    emit UnwrappedFLUID(msg.sender, amount_);
  }
  
  function batchTransfer(
    address[] calldata recipients_, 
    uint256[] calldata amounts_
  ) external {
    require(recipients_.length == amounts_.length, "recipients count differs from amounts");
    require(recipients_.length > 0, "batch is empty");
    for(uint256 i = 0; i < recipients_.length; i++) {
      _transfer(msg.sender, recipients_[i], amounts_[i]);
    }
  }
    
  function decimals() public pure override returns (uint8) {
    return DECIMALS_VALUE;
  }

  function updateTimelock(uint256 timelock_) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 'only admin');
     
    // once timelocked passed, it cannot be re-locked
    require(block.timestamp < timelock, 'timelock no longer updateable');

    timelock = timelock_;
    emit TimelockUpdated(msg.sender, timelock);
  }

  function setSellContract(address sellContract_) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 'only admin');

    sellContract = sellContract_;
    emit SellContractUpdated(msg.sender, sellContract);
  }
}
