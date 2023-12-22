// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ICamelotYieldFarmManager.sol";
import "./ICamelotYieldFarmReader.sol";
import "./IChainlinkOracle.sol";
import "./IWETH.sol";
import "./ManagerAction.sol";
import "./VaultStrategy.sol";

contract CamelotLongETHUSDCYieldFarmVault is ERC20, Ownable, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Vault's strategy enum; 0 - Neutral, 1 - Long, 2 - Short
  VaultStrategy public immutable strategy;
  // e.g. WETH
  IERC20 public immutable tokenA;
  // e.g. USDC
  IERC20 public immutable tokenB;
  // Chainlink contract
  IChainlinkOracle public immutable chainlinkOracle;
  // Vault config struct
  VaultConfig public vaultConfig;
  // Max capacity of vault
  uint256 public maxCapacity;
  // Management fee per second in % in 1e18
  uint256 public mgmtFeePerSecond;
  // Performance fee in % in 1e18
  uint256 public perfFee;
  // Protocol treasury address
  address public treasury;
  // Timestamp of when last mgmt fee was collected
  uint256 public lastFeeCollected;
  // Manager contract
  ICamelotYieldFarmManager public manager;
  // Reader contract
  ICamelotYieldFarmReader public reader;

  /* ========== STRUCTS ========== */

  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
    // Target Token A debt ratio in 1e18
    uint256 tokenADebtRatio;
    // Target Token B debt ratio in 1e18
    uint256 tokenBDebtRatio;
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
    * @param _name Name of vault e.g. 3x Long AVAX-USDC Trader Joe
    * @param _symbol Symbol for contract e.g. 3L-AVAXUSDC-TJ
    * @param _strategy Vault strategy enum
    * @param _tokenA TokenA address
    * @param _tokenB TokenB address
    * @param _chainlinkOracle Chainlink oracle address
    * @param _vaultConfig VaultConfig struct details
    * @param _maxCapacity Max capacity of vault
    * @param _mgmtFeePerSecond Management fee per second in % in 1e18
    * @param _perfFee Performance fee in % in 1e18
    * @param _treasury Protocol treasury address
  */
  constructor (
    string memory _name,
    string memory _symbol,
    VaultStrategy _strategy,
    IERC20 _tokenA,
    IERC20 _tokenB,
    IChainlinkOracle _chainlinkOracle,
    VaultConfig memory _vaultConfig,
    uint256 _maxCapacity,
    uint256 _mgmtFeePerSecond,
    uint256 _perfFee,
    address _treasury
  ) ERC20(_name, _symbol) {
    require(address(_tokenA) != address(0), "Invalid address");
    require(address(_tokenB) != address(0), "Invalid address");
    require(address(_chainlinkOracle) != address(0), "Invalid address");

    strategy = _strategy;
    tokenA = _tokenA;
    tokenB = _tokenB;
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
    * @return Amount of share pending for minting as a form of mgmt fee
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
  function valueToShares(uint256 _value, uint256 _currentEquity) public view
    returns (uint256) {
    uint256 _sharesSupply = totalSupply() + pendingMgmtFee();
    if (_sharesSupply == 0) return _value;
    return _value * _sharesSupply / _currentEquity;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Deposits asset into vault and mint svToken to user
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svToken to mint in 1e18
  */
  function deposit(uint256 _amt, uint256 _minSharesAmt) external payable
   nonReentrant whenNotPaused {
    require(_amt == msg.value, "Amt != msg.value");

    _mintMgmtFee();

    IWETH(address(tokenA)).deposit{ value: msg.value }();

    tokenA.safeTransfer(address(manager), _amt);

    uint256 sharesToUser = _deposit(tokenA, _amt, _minSharesAmt);

    emit Deposit(
      msg.sender,
      address(tokenA),
      _amt,
      sharesToUser
    );
  }

  /**
    * Withdraws asset from vault, burns svToken from user
    * @param _shareAmt Amount of svTokens to burn in 1e18
    * @param _minWithdrawAmt Minimum amount of asset tokens to withdraw in token decimals
  */
  function withdraw(uint256 _shareAmt, uint256 _minWithdrawAmt)
  external nonReentrant whenNotPaused {
    // check to ensure shares withdrawn does not exceed user's balance
    require(_shareAmt > 0, "Quantity must be > 0");
    require(_shareAmt <= balanceOf(msg.sender), "Withdraw amt exceeds balance");

    _mintMgmtFee();
    _burnAndWork(_shareAmt);

    uint256 withdrawAmt = tokenA.balanceOf(address(this));
    require(withdrawAmt >= _minWithdrawAmt, "Assets received less than minimum");

    _withdraw(address(tokenA), withdrawAmt);

    emit Withdraw(
      msg.sender,
      address(tokenA),
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
    if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
      _shareAmt = balanceOf(msg.sender);
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();

    _burn(msg.sender, _shareAmt);

    uint256 withdrawAmt = shareRatio * tokenA.balanceOf(address(this))
                          / SAFE_MULTIPLIER;

    _withdraw(address(tokenA), withdrawAmt);

    emit Withdraw(
      msg.sender,
      address(tokenA),
      withdrawAmt,
      _shareAmt
    );
  }

  /**
    * Get manager to compound rewards from staked lp tokens
    @param _data Called by Keeper, see below:
    * lpTokeRewards = new address[](1)
    * lpTokeRewards[0] = address of lp token reward i.e. WETH-USDC LP
    * Possible for future additional LP token rewards
    * data = abi.encode(dividendsAddress, lpTokenRewards)
  */
  function compound(bytes calldata _data) public {
    manager.compound(_data);

    emit Compound(address(this));
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Internal deposit function to pass borrow amts to manager,
    * then mint svTokens back to user based on equity value change
    * @param _depositToken Token deposited
    * @param _amt Amount of asset deposited in token decimals
    * @param _minSharesAmt Minimum amount of shares to mint in 1e18
    * @return sharesToUser Amt of shares minted to user in 1e18
  */
  function _deposit(IERC20 _depositToken, uint256 _amt, uint256 _minSharesAmt)
    internal returns (uint256) {
    uint256 equityBefore = reader.equityValue();
    uint256 depositValue = reader.tokenValue(address(_depositToken), _amt);

    require(_amt > 0, "Amt must be > 0");
    require(equityBefore + depositValue <= maxCapacity, "Exceeded capacity");

    uint256 borrowTokenAAmt = depositValue
      * (vaultConfig.targetLeverage - 1e18)
      / SAFE_MULTIPLIER
      * vaultConfig.tokenADebtRatio
      / chainlinkOracle.consultIn18Decimals(address(tokenA));

    uint256 borrowTokenBAmt = depositValue
      * (vaultConfig.targetLeverage - 1e18)
      / SAFE_MULTIPLIER
      * vaultConfig.tokenBDebtRatio
      / chainlinkOracle.consultIn18Decimals(address(tokenB))
      / 1e12;

    manager.work(
      ManagerAction.Deposit,  /* action */
      0,  /* lpAmt */
      borrowTokenAAmt, /* borrowTokenAAmt */
      borrowTokenBAmt, /* borrowTokenBAmt */
      0, /* repayTokenAAmt */
      0  /* repayTokenBAmt */
    );

    uint256 _equityChange = reader.equityValue() - equityBefore;

    // calculate shares to users
    uint256 sharesToUser = valueToShares(_equityChange, equityBefore);
    require(sharesToUser >= _minSharesAmt, "Shares received less than minimum");

    _mint(msg.sender, sharesToUser);

    return sharesToUser;
  }

  /**
    * Internal withdraw function to burn svTokens, pass repay amts to manager,
    * transfer tokens back to user
    * @param _shareAmt Amount of svTokens to burn in 1e18
  */
  function _burnAndWork(uint256 _shareAmt) internal {
    // to avoid leaving dust behind
    if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
      _shareAmt = balanceOf(msg.sender);
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();

    _burn(msg.sender, _shareAmt);

    // do calculations
    (uint256 tokenADebtAmt, uint256 tokenBDebtAmt) = manager.debtInfo();
    uint256 lpAmt = shareRatio * manager.lpTokenAmt() / SAFE_MULTIPLIER;
    uint256 repayTokenAAmt = shareRatio * tokenADebtAmt / SAFE_MULTIPLIER;
    uint256 repayTokenBAmt = shareRatio * tokenBDebtAmt / SAFE_MULTIPLIER;

    manager.work(
      ManagerAction.Withdraw, /* action */
      lpAmt, /* lpAmt */
      0, /* borrowTokenAAmt */
      0, /* borrowTokenBAmt */
      repayTokenAAmt, /* repayTokenAAmt */
      repayTokenBAmt /* repayTokenBAmt */
    );
  }

  /**
    * Follow-on function from withdraw(), called after manager does work();
    * withdraws balance of tokenA/B to user
    * @param _token Withdraw token address
    * @param _withdrawAmt Withdraw amt in 1e18
  */
  function _withdraw(
    address _token,
    uint256 _withdrawAmt
  ) internal {
    IWETH(_token).withdraw(_withdrawAmt);
    (bool success, ) = msg.sender.call{value: _withdrawAmt}("");
    require(success, "Transfer failed.");
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
  */
  function updateVaultConfig(
    VaultConfig memory _vaultConfig
    ) external onlyOwner {
    vaultConfig = _vaultConfig;

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
  function updateReader(ICamelotYieldFarmReader _reader) external onlyOwner {
    // require(address(_reader) != address(0), "Invalid address");
    reader = _reader;
    // emit UpdateReader(_reader);
  }

  /**
    * Update vault's manager contract
    * @param _manager Manager address
  */
  function updateManager(ICamelotYieldFarmManager _manager) external onlyOwner {
    // require(address(_manager) != address(0), "Invalid address");
    manager = _manager;
    // emit UpdateManager(_manager);
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
    * @param _borrowTokenAAmt Amt of tokens to borrow in 1e18
    * @param _borrowTokenBAmt Amt of tokens to borrow in 1e18
    * @param _repayTokenAAmt Amt of tokens to repay in 1e18
    * @param _repayTokenBAmt Amt of tokens to repay in 1e18
  */
  function rebalance(
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAAmt,
    uint256 _borrowTokenBAmt,
    uint256 _repayTokenAAmt,
    uint256 _repayTokenBAmt
  ) public onlyKeeper whenNotPaused {
    _mintMgmtFee();

    uint256 svTokenValueBefore = svTokenValue();

    manager.work(
      _action,
      _lpAmt,
      _borrowTokenAAmt,
      _borrowTokenBAmt,
      _repayTokenAAmt,
      _repayTokenBAmt
    );

    emit Rebalance(svTokenValueBefore, svTokenValue());
  }

  /**
   * Allocate xGrail to desired plugin
   * @param _data Calculated by Keeper. See below
   * For allocation to yield booster:
   * usageData = abi.encode(nftPoolAddress, nftPositionId)
   * data = abi.encode(yieldBoosterAddress, xGrailAmountToAllocate, usageData)
   * For allocation to dividends pulgin (note usageData is empty):
    * data = abi.encode(dividendsAddress, xGrailAmountToAllocate, usageData)
  */
  function allocate(bytes calldata _data) external onlyKeeper whenNotPaused {
    manager.allocate(_data);
  }

  /**
   * Deallocate xGrail to desired plugin
   * @param _data Calculated by Keeper. See below
   * For deallocation from yield booster:
   * usageData = abi.encode(nftPoolAddress, nftPositionId)
   * data = abi.encode(yieldBoosterAddress, xGrailAmountToDeallocate, usageData)
   * For deallocation from dividends pulgin (note usageData is empty):
    * data = abi.encode(dividendsAddress, xGrailAmountToDeallocate, usageData)
  */
  function deallocate(bytes calldata _data) external onlyKeeper whenNotPaused {
    manager.deallocate(_data);
  }

  /**
    * Emergency shut down of vault that withdraws all assets, repay all debt
    * and pause all deposits and normal withdrawals
  */
  function emergencyShutDown() external onlyOwner {
    _pause();

    // calculate lp amount, repayToken amounts
    (uint256 tokenADebtAmt, uint256 tokenBDebtAmt) = manager.debtInfo();

    // withdraw all LP amount, repay all debt and receive base tokens
    manager.work(
      ManagerAction.Withdraw /* action */,
      manager.lpTokenAmt() /* lpAmt */,
      0, /* borrowTokenAAmt */
      0, /* borrowTokenBAmt */
      tokenADebtAmt, /* repayTokenAAmt */
      tokenBDebtAmt /* repayTokenBAmt */
    );
  }

  /* ========== FALLBACK FUNCTIONS ========== */

  /**
    * Fallback function to receive native token sent to this contract,
    * needed for receiving native token to contract when unwrapped
  */
  receive() external payable {}
}

