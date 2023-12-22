// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IGMXPerpetualDEXLongManager.sol";
import "./IGMXPerpetualDEXLongReader.sol";
import "./IChainlinkOracle.sol";
import "./ManagerAction.sol";

contract GMXPerpetualDEXLongVault is ERC20, Ownable, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Manager contract
  IGMXPerpetualDEXLongManager public manager;
  // Reader contract
  IGMXPerpetualDEXLongReader public reader;
  // Chainlink contract
  IChainlinkOracle public immutable chainlinkOracle;
  // Vault config struct
  VaultConfig public vaultConfig;
  // Management fee per second in % in 1e18
  uint256 public mgmtFeePerSecond;
  // Performance fee in % in 1e18
  uint256 public perfFee;
  // Protocol treasury address
  address public treasury;
  // Timestamp of when last mgmt fee was collected
  uint256 public lastFeeCollected;
  // Max capacity of vault
  uint256 public maxCapacity;
  // Deposit token
  IERC20 public immutable token;

  /* ========== STRUCTS ========== */

  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant DUST_AMOUNT = 1e17;

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;

  /* ========== EVENTS ========== */

  event Deposit(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event Withdraw(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event Rebalance(uint256 svTokenValueBefore, uint256 svTokenValueAfter);
  event Compound(address vault);
  event UpdateVaultConfig(VaultConfig _vaultConfig);
  event UpdateMgmtFeePerSecond(uint256 _mgmtFeePerSecond);
  event UpdateMaxCapacity(uint256 _maxCapacity);
  event UpdatePerfFee(uint256 _perfFee);
  event UpdateKeeper(address _keeper, bool _status);
  event UpdateManager(IGMXPerpetualDEXLongManager _manager);
  event UpdateReader(IGMXPerpetualDEXLongReader _reader);

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
  */
  modifier onlyKeeper() {
    require(keepers[msg.sender], "Keeper not approved");
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _name Name of vault e.g. 3X Long GLP GMX
    * @param _symbol Symbol for contract e.g. 3L-GLP-GMX
    * @param _token Deposit token
    * @param _chainlinkOracle Chainlink oracle
    * @param _vaultConfig Vault config details
    * @param _maxCapacity Max capacity of vault in 1e18
    * @param _mgmtFeePerSecond Management fee per second in % in 1e18
    * @param _perfFee Performance fee in % in 1e18
    * @param _treasury Protocol treasury address
  */
  constructor (
    string memory _name,
    string memory _symbol,
    IERC20 _token,
    IChainlinkOracle _chainlinkOracle,
    VaultConfig memory _vaultConfig,
    uint256 _maxCapacity,
    uint256 _mgmtFeePerSecond,
    uint256 _perfFee,
    address _treasury
  ) ERC20(_name, _symbol) {
    require(address(_token) != address(0), "Invalid address");
    require(address(_chainlinkOracle) != address(0), "Invalid address");

    token = _token;
    chainlinkOracle = _chainlinkOracle;
    vaultConfig = _vaultConfig;
    maxCapacity = _maxCapacity;
    mgmtFeePerSecond = _mgmtFeePerSecond;
    perfFee = _perfFee;
    treasury = _treasury;
    lastFeeCollected = block.timestamp;
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the value of each share token; obtained by total equity divided by share token supply
    * @return svTokenValue   Value of each share token in 1e18
  */
  function svTokenValue() public view returns (uint256) {
    uint256 equityValue = reader.equityValue();
    if (equityValue == 0 || totalSupply() == 0) return SAFE_MULTIPLIER;
    return equityValue * SAFE_MULTIPLIER / totalSupply();
  }

  /**
    * @return Fee of share pending for minting as a form of mgmt fee
  */
  function pendingMgmtFee() public view returns (uint256) {
    uint256 secondsFromLastCollection = block.timestamp - lastFeeCollected;
    return (totalSupply() * mgmtFeePerSecond * secondsFromLastCollection) / SAFE_MULTIPLIER;
  }

  /**
    * Used by checkAndMint(); Conversion of equity value to svToken shares
    * @param _value Equity value change after deposit in 1e18
    * @param _currentEquity Current equity value of vault in 1e18
    * @return sharesAmt Shares amt in 1e18
  */
  function valueToShares(uint256 _value, uint256 _currentEquity) public view returns (uint256) {
    uint256 _sharesSupply = totalSupply() + pendingMgmtFee();
    if (_sharesSupply == 0) return _value;
    return _value * _sharesSupply / _currentEquity;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Deposits asset into vault and mint svToken to user
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svTokens to mint in 1e18
   */
  function deposit(uint256 _amt, uint256 _minSharesAmt) external nonReentrant whenNotPaused {
    _mintMgmtFee();

    token.safeTransferFrom(msg.sender, address(manager), _amt);

    uint256 sharesToUser = _deposit(_amt, _minSharesAmt);

    emit Deposit(
      msg.sender,
      address(token),
      _amt,
      sharesToUser
    );
  }

  /**
    * Withdraws asset from vault, burns svToken from user
    * @param _shareAmt Amount of svTokens to burn in 1e18
    * @param _minWithdrawAmt Minimum amount of asset tokens to withdraw in token decimals
  */
  function withdraw(uint256 _shareAmt, uint256 _minWithdrawAmt) external nonReentrant whenNotPaused {
    require(_shareAmt > 0, "Quantity must be > 0");
    require(_shareAmt <= balanceOf(msg.sender), "Withdraw amt exceeds balance");

    _mintMgmtFee();
    _burnAndWork(_shareAmt);

    uint256 withdrawAmt = token.balanceOf(address(this));
    require(withdrawAmt >= _minWithdrawAmt, "Assets received less than minimum");

    _withdraw(address(token), withdrawAmt);

    emit Withdraw(
      msg.sender,
      address(token),
      withdrawAmt,
      _shareAmt
    );
  }

  /**
    * Emergency withdraw function, enabled only when vault is paused, burns svToken from user
    * @param _shareAmt Amount of svTokens to burn in 1e18
  */
  function emergencyWithdraw(uint256 _shareAmt) external nonReentrant whenPaused {
    // check to ensure shares withdrawn does not exceed user's balance
    require(_shareAmt > 0, "Quantity must be > 0");
    require(_shareAmt <= balanceOf(msg.sender), "Withdraw amt exceeds balance");

    // to avoid leaving dust behind
    unchecked {
      if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
        _shareAmt = balanceOf(msg.sender);
      }
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();

    _burn(msg.sender, _shareAmt);

    uint256 withdrawAmt = shareRatio * token.balanceOf(address(this)) / SAFE_MULTIPLIER;

    _withdraw(address(token), withdrawAmt);

    emit Withdraw(
      msg.sender,
      address(token),
      withdrawAmt,
      _shareAmt
    );
  }

  /**
    * Get manager to compound rewards from staked lp tokens
    * @param _rewardTrackers Array of token addresses for rewards
  */
  function compound(address[] memory _rewardTrackers) public {
    manager.compound(_rewardTrackers);

    emit Compound(address(this));
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Internal deposit function to pass borrow amts to manager, then mint svTokens back to user based on equity value change
    * @param _amt Amount of asset deposited in token decimals
    * @param _minSharesAmt Minimum amount of svTokens to mint in 1e18
    * @return sharesToUser Amt of shares minted to user in 1e18
  */
  function _deposit(uint256 _amt, uint256 _minSharesAmt) internal returns (uint256) {
    uint256 glpPrice = reader.glpPrice();
    uint256 depositValue = reader.tokenValue(address(token), _amt);
    uint256 equityBefore = reader.assetValueWithPrice(glpPrice) - reader.debtValue();

    require(_amt > 0, "Amt must be > 0");
    require(equityBefore + depositValue <= maxCapacity, "Exceeded capacity");

    uint256 borrowTokenAmt = _amt
      * (vaultConfig.targetLeverage - 1e18)
      / SAFE_MULTIPLIER;

    manager.work(
      ManagerAction.Deposit, /* action */
      0,  /* lpAmt */
      borrowTokenAmt, /* borrowTokenAmt */
      0 /* repayTokenAAmt */
    );

    uint256 _equityChange = (reader.assetValueWithPrice(glpPrice) - reader.debtValue()) - equityBefore;
    // calculate shares to users
    uint256 sharesToUser = valueToShares(_equityChange, equityBefore);

    require(sharesToUser >= _minSharesAmt, "Shares received less than minimum");

    _mint(msg.sender, sharesToUser);

    return sharesToUser;
  }

  /**
    * Internal withdraw function to burn svTokens, pass repay amts to manager, transfer tokens back to user
    * @param _shareAmt Amount of svTokens to burn in 1e18
  */
  function _burnAndWork(uint256 _shareAmt) internal {
    // to avoid leaving dust behind
    unchecked {
      if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
        _shareAmt = balanceOf(msg.sender);
      }
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();

    _burn(msg.sender, _shareAmt);

    // do calculations
    uint256 tokenDebtAmt = manager.debtInfo();
    uint256 lpAmt = shareRatio * manager.lpTokenAmt() / SAFE_MULTIPLIER;
    uint256 repayTokenAAmt = shareRatio * tokenDebtAmt / SAFE_MULTIPLIER;

    manager.work(
      ManagerAction.Withdraw, /* action */
      lpAmt, /* lpAmt */
      0, /* borrowTokenAmt */
      repayTokenAAmt /* repayTokenAAmt */
    );
  }

  /**
    * Follow-on function from _withdraw(), called after manager does work(); withdraws balance of tokens to user
    * @param _token Token address
    * @param _withdrawAmt Withdraw amt in 1e18
  */
  function _withdraw(
    address _token,
    uint256 _withdrawAmt
  ) internal {
    IERC20(_token).safeTransfer(msg.sender, _withdrawAmt);
  }

  /**
    * Minting shares as a form of management fee to treasury address
  */
  function _mintMgmtFee() internal {
    _mint(treasury, pendingMgmtFee());
    lastFeeCollected = block.timestamp;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Update vault config struct
    * @param _vaultConfig Vault config struct
    * @param _action Manager action enum
    * @param _lpAmt Amount of lp tokens to deposit/withdraw
    * @param _borrowTokenAmt Amount of borrow token to borrow
    * @param _repayTokenAmt Amount of borrow token to repay
  */
  function updateVaultConfig(
    VaultConfig memory _vaultConfig,
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAmt,
    uint256 _repayTokenAmt
  ) external onlyOwner {
    vaultConfig = _vaultConfig;

    rebalance(_action, _lpAmt, _borrowTokenAmt, _repayTokenAmt);
    emit UpdateVaultConfig(_vaultConfig);
  }

  /**
    * Update management fee per second of vault
    * @param _mgmtFeePerSecond Management fee in 1e18
  */
  function updateMgmtFeePerSecond(uint256 _mgmtFeePerSecond) external onlyOwner {
    mgmtFeePerSecond = _mgmtFeePerSecond;
    emit UpdateMgmtFeePerSecond(_mgmtFeePerSecond);
  }

  /**
    * Update performance fee of vault
    * @param _perfFee Performance fee in 1e18
  */
  function updatePerfFee(uint256 _perfFee) external onlyOwner {
    perfFee = _perfFee;
    emit UpdatePerfFee(_perfFee);
  }

  /**
    * Update vault's reader contract
    * @param _reader Reader address
  */
  function updateReader(IGMXPerpetualDEXLongReader _reader) external onlyOwner {
    require(address(_reader) != address(0), "Invalid address");
    reader = _reader;
    emit UpdateReader(_reader);
  }

  /**
    * Update vault's manager contract
    * @param _manager Manager address
  */
  function updateManager(IGMXPerpetualDEXLongManager _manager) external onlyOwner {
    require(address(_manager) != address(0), "Invalid address");
    manager = _manager;
    emit UpdateManager(_manager);
  }

  /**
    * Approve or revoke address to be a keeper for this vault
    * @param _keeper Keeper address
    * @param _approval Boolean to approve keeper or not
  */
  function updateKeeper(address _keeper, bool _approval) external onlyOwner {
    require(_keeper != address(0), "Invalid address");
    keepers[_keeper] = _approval;
    emit UpdateKeeper(_keeper, _approval);
  }

  /**
    * Update treasury address
    * @param _treasury Treasury address
  */
  function updateTreasury(address _treasury) external onlyOwner {
    require(_treasury != address(0), "Invalid address");
    treasury = _treasury;
  }

  /**
    * Update max capacity value
    * @param _maxCapacity Capacity value in 1e18
  */
  function updateMaxCapacity(uint256 _maxCapacity) external onlyOwner {
    maxCapacity = _maxCapacity;
    emit UpdateMaxCapacity(_maxCapacity);
  }

  /**
    * Called by keepers if rebalance conditions are triggered
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _lpAmt Amt of LP tokens to sell for repay in 1e18
    * @param _borrowTokenAmt Amt of tokens to borrow in 1e18
    * @param _repayTokenAmt Amt of tokens to repay in 1e18
  */
  function rebalance(
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAmt,
    uint256 _repayTokenAmt
  ) public onlyKeeper whenNotPaused {
    _mintMgmtFee();

    uint256 svTokenValueBefore = svTokenValue();

    manager.work(
      _action,
      _lpAmt,
      _borrowTokenAmt,
      _repayTokenAmt
    );

    emit Rebalance(svTokenValueBefore, svTokenValue());
  }

  /**
    * Emergency shut down of vault that withdraws all assets, repay all debt
    * and pause all deposits and normal withdrawals
  */
  function emergencyShutDown() external onlyOwner whenNotPaused {
    _pause();

    uint256 tokenDebtAmt = manager.debtInfo();

    // withdraw all LP amount, repay all debt and receive base tokens
    manager.work(
      ManagerAction.Withdraw, /* action */
      manager.lpTokenAmt(), /* lpAmt */
      0, /* borrowTokenAmt */
      tokenDebtAmt /* repayTokenAAmt */
    );
  }
}

