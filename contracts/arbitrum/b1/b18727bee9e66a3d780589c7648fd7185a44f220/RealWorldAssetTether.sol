// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20Upgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./ECDSA.sol";

import "./IOracleFeed.sol";

/// @title Real World Asset Tether
/// @author FluidFi & DeFi Bridge DAO - nic@fluidfi.ch, alexander@takasecurity.com
/// @notice A digital token representation of fully backed real world assets. 
contract RealWorldAssetTether is ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlEnumerableUpgradeable {

  //
  //
  /* ========== Constants ========== */
  //
  //
  
  /**
  * @dev administration roles
  */
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant WHITELISTER_ADMIN_ROLE = keccak256("WHITELISTER_ADMIN_ROLE");
  bytes32 public constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");
  bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
  bytes32 public constant REDEEM_ADMIN_ROLE = keccak256("REDEEM_ADMIN_ROLE");
  bytes32 public constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");
  
  /**
  * @dev 6 due to some limitations of CEXs
  */
  uint8 internal constant DECIMALS_VALUE = 6;

  /**
  * @dev used for fee calculation
  */
  uint constant PERC_BASE = 10000; // == 100.00%

  //
  //
  /* ========== Configurations ========== */
  //
  //

  bool public paused;

  /**
  * @dev provides the latest verified offchain asset balance of the 
  *      offchain treasury account aka Proof of Reserve
  */
  IOracleFeed public offchainTreasuryOracle;
  

  /**
  * @dev specifies the minimum amount that can be redeemed
  */
  uint256 public minRedeemAmount;

  /**
  * @dev offchain asset may have different decimals precision
  *      this needs to be considered during `redeem`
  */
  uint256 public dustDecimals;
  
  /**
  * @dev whitelisted addresses that can be minted to and redeemed from
  */
  mapping (address => bool) public whitelist;
  
  /**
  * @dev blacklisted addresses, these can not be whitelisted again
  */
  mapping (address => bool) public blacklist;

  /**
  * @dev offchain signer that provides signatures for addresses that are allowed to whitelist
  */
  address public whitelistSigner;

  /**
  * @dev token amounts burnt during redeem() are kept in pending state until the treasury oracle has been updated
  */
  mapping(address => uint256) pendingRedeems;
  uint256 public totalPendingRedeems;

  /**
  * @dev fees in reference to PERC_BASE, i.e. 100 = 1.00%, 10000 = 100%
  */
  uint256 public mintFee;
  uint256 public redeemFee;
  uint256 public bridgeFee;
  address public feeReceiver;

  //
  //
  /* ========== Events ========== */
  //
  //  
  
  // mint
  event Mint(address indexed to, uint256 amount, bytes32 indexed txID);
  
  // pausing
  event Paused();
  event Unpaused();
      
  // whitelisting/blacklisting
  event WhitelistAdded(address indexed account);
  event WhitelistRemoved(address indexed account);
  event NotWhitelisted(address indexed account);
  event WhitelistSignerUpdated(address indexed account);
  event BlacklistAdded(address indexed account);
  
  // oracles
  event UpdateOffchainTreasuryOracle(address oracleAddress);
  
  // processing mint transactions
  event TxAlreadyProcessed(bytes32 indexed txID);
  event TxAmountZero(bytes32 indexed txID);
  
  // redeem
  event Redeem(address indexed from, uint256 amount);
  event PendingRedeemReleased(address indexed account, uint256 amount, bytes32 indexed cefiTxID);
  event TxRedeemInvalidPendingAmount(bytes32 indexed txID);
  event MinRedeemAmountUpdated(uint256 minRedeemAmount);

  event DustDecimalsUpdated(uint256 dustDecimals);

  // fees 
  event MintFeeUpdated(uint256 mintFee);
  event RedeemFeeUpdated(uint256 redeemFee);
  event FeeReceiverUpdated(address indexed feeReceiver);

  /* ========== Initializer ========== */

  function initialize(
    string calldata _name, 
    string calldata _symbol, 
    address _offchainTreasuryOracle,
    address _whitelistSigner
  ) public initializer {
    require(_offchainTreasuryOracle != address(0), "_offchainTreasuryOracle is 0x0");
    
    ERC20Upgradeable.__ERC20_init(_name, _symbol);
    ERC20PermitUpgradeable.__ERC20Permit_init(_name);
    AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();

    // can (re)assign any of the roles
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    
    _setupRole(PAUSER_ROLE, msg.sender);
    _setupRole(REDEEM_ADMIN_ROLE, msg.sender);
    _setupRole(FEE_ADMIN_ROLE, msg.sender);

    offchainTreasuryOracle = IOracleFeed(_offchainTreasuryOracle);
    whitelistSigner = _whitelistSigner;
        
    minRedeemAmount = 1*10**DECIMALS_VALUE;
    dustDecimals = DECIMALS_VALUE - 2;
    mintFee = 0;
    redeemFee = 0;

    feeReceiver = msg.sender;
  }
  
  //
  //
  /* ========== ERC20 ========== */
  //
  //
  
  function decimals() public pure override returns (uint8) {
    return DECIMALS_VALUE;
  }
  
  //
  //
  /* ========== Core functions: mint / redeem  ========== */
  //
  //
  
  /**
  * @dev called from the OffchainTreasury contract to mint after a CeFi tx has validated the mint
  */
  function mint(address _recipient, uint _amount, bytes32 _ceFiTxID) external virtual whenNotPaused returns (bool success) {
    require(msg.sender == address(offchainTreasuryOracle), "caller is not treasury");
    
    if (!whitelist[_recipient]) { // also catches recipient being 0x0
      emit NotWhitelisted(_recipient);
      return false;
    }

    require(
      (totalSupply() + totalPendingRedeems + _amount) <= offchainTreasuryOracle.getLatestAnswer(),
      "totalSupply cannot be greater than offchain total supply"
    );
  
    uint256 _fee = _amount * mintFee / PERC_BASE;

    if(_fee > 0) {
      _mint(feeReceiver, _fee);
    }
    _mint(_recipient, _amount-_fee);
    
    emit Mint(_recipient, _amount, _ceFiTxID);
    
    return true;
  }

  /**
  * @dev called by any (whitelisted) user to burn tokens and receive offchain assets in his offchain account
  */
  function redeem(uint256 _amount) external whenNotPaused {
    require(whitelist[msg.sender], "only allowed for whitelisted address");

    uint256 _fee = _amount * redeemFee / PERC_BASE;

    // gets rid of the dust, e.g.: 1.123456 => 1.120000
    uint256 _amountWithoutDust = ((_amount-_fee)/10**dustDecimals)*(10**dustDecimals);
    require(_amountWithoutDust >= minRedeemAmount, "cannot redeem less than minRedeemAmount");

    if(_fee > 0) {
      _transfer(msg.sender, feeReceiver, _fee);
    }
    
    pendingRedeems[msg.sender] += _amountWithoutDust;
    totalPendingRedeems += _amountWithoutDust;

    _burn(msg.sender, _amountWithoutDust);
    
    emit Redeem(msg.sender, _amountWithoutDust);
  }

  /**
  * @dev called from the OffchainTreasuryOracle after the redeemed amount has been moved out of the 
  *      offchain treasury account and the oracle has been updated.
  */
  function releasePendingRedeem(address _account, uint256 _amount, bytes32 _ceFiTxID) external whenNotPaused returns (bool success) {
    require(msg.sender == address(offchainTreasuryOracle), "caller is not treasury");

    if (pendingRedeems[_account] < _amount) {
      emit TxRedeemInvalidPendingAmount(_ceFiTxID);
      return false;
    } 
    
    pendingRedeems[_account] -= _amount;
    totalPendingRedeems -= _amount;

    emit PendingRedeemReleased(_account, _amount, _ceFiTxID);
    
    return true;
  }

  //
  //
  /* ========== Pausing ========== */
  //
  //
  
  modifier whenNotPaused() {
      require(!paused, "paused");
      _;
  }

  modifier whenPaused() {
      require(paused, "not paused");
      _;
  }

  function pause() external whenNotPaused onlyRole(PAUSER_ROLE) {
      paused = true;
      emit Paused();
  }

  function unpause() external whenPaused onlyRole(PAUSER_ROLE) {
      paused = false;
      emit Unpaused();
  }
  
  //
  //
  /* ========== Whitelist ========== */
  //
  //
  
  /**
  * @dev called by annyone to whitelist themselves. If an account has been previously removed
  *      from the whitelist (i.e. blacklisted), then that account can not whitelist again.
  */
  function addToWhitelist(address _account, bytes calldata _signature) public {
    require(_account != address(0), "zero address not allowed to be whitelisted");
    require(!whitelist[_account], "address already whitelisted");
    require(!blacklist[_account], "address is blacklisted");
    require(ECDSA.recover(_hashSignedData(_account), _signature) == whitelistSigner, "invalid signature");
    whitelist[_account] = true;
    emit WhitelistAdded(_account);
  }

  function batchAddToWhitelist(address[] calldata _accounts, bytes[] calldata _signatures) external {
    require(_accounts.length == _signatures.length, "invalid arguments: same number of addresses and signatures required");
    for (uint256 i = 0; i < _accounts.length; i++) {
      addToWhitelist(_accounts[i], _signatures[i]);
    }
  }

  /**
  * @dev called by the whitelister to remove an account from the whitelist and blacklist it.
  *      If the account is not currently whitelisted then it is only added to the blacklist.
  */
  function removeFromWhitelist(address _account) external onlyRole(WHITELISTER_ROLE) {
    require(!blacklist[_account], "already removed from whitelist");
    if (whitelist[_account]) {
      whitelist[_account] = false;
      emit WhitelistRemoved(_account);
    }
    blacklist[_account] = true;
    emit BlacklistAdded(_account);
  }

  function updateWhitelistSigner(address _whitelistSigner) external onlyRole(WHITELISTER_ADMIN_ROLE) {
    require(_whitelistSigner != address(0), "zero address cannot be whitelistSigner");
    require(_whitelistSigner != whitelistSigner, "_whitelistSigner equals current");
    whitelistSigner = _whitelistSigner;
    emit WhitelistSignerUpdated(whitelistSigner);
  }

  function _hashSignedData(address _address) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(
      "\x19Ethereum Signed Message:\n32", 
      keccak256(abi.encodePacked(_address))
    ));
  }
  
  //
  //
  /* ========== Managing oracle ========== */
  //
  //
  
  function updateOffchainTreasury(address _newOracleAddress) external onlyRole(ORACLE_UPDATER_ROLE) {
    require(_newOracleAddress != address(0), "_newOracleAddress is 0x0");
    require(_newOracleAddress != address(offchainTreasuryOracle), "_newOracleAddress equals current");
    offchainTreasuryOracle = IOracleFeed(_newOracleAddress);
    emit UpdateOffchainTreasuryOracle(_newOracleAddress);
  }

  //
  //
  /* ========== Managing redeem ========== */
  //
  //
  
  function updateMinRedeemAmount(uint256 _minRedeemAmount) external onlyRole(REDEEM_ADMIN_ROLE) {
    require(_minRedeemAmount != minRedeemAmount, "_minRedeemAmount equals current");
    minRedeemAmount = _minRedeemAmount;
    emit MinRedeemAmountUpdated(minRedeemAmount);
  }

  function updateDustDecimals(uint256 _dustDecimals) external onlyRole(REDEEM_ADMIN_ROLE) {
    require(_dustDecimals != dustDecimals, "_dustDecimals equals current");
    require(_dustDecimals <= DECIMALS_VALUE, "_dustDecimals too big");
    dustDecimals = _dustDecimals;
    emit DustDecimalsUpdated(dustDecimals);
  }
  
  //
  //
  /* ========== Managing fees ========== */
  //
  //
  
  function updateMintFee(uint256 _mintFee) external onlyRole(FEE_ADMIN_ROLE) {
    require(_mintFee != mintFee, "_mintFee equals current");
    require(_mintFee <= PERC_BASE, "_mintFee exceeds 100%");
    mintFee = _mintFee;
    emit MintFeeUpdated(mintFee);
  }
  function updateRedeemFee(uint256 _redeemFee) external onlyRole(FEE_ADMIN_ROLE) {
    require(_redeemFee != redeemFee, "_redeemFee equals current");
    require(_redeemFee <= PERC_BASE, "_redeemFee exceeds 100%");
    redeemFee = _redeemFee;
    emit RedeemFeeUpdated(redeemFee);
  }
  function updateFeeReceiver(address _feeReceiver) external onlyRole(FEE_ADMIN_ROLE) {
    require(_feeReceiver != address(0), "_feeReceiver is 0x0");
    require(_feeReceiver != feeReceiver, "_feeReceiver equals current");
    feeReceiver = _feeReceiver;
    emit FeeReceiverUpdated(feeReceiver);
  }
}
