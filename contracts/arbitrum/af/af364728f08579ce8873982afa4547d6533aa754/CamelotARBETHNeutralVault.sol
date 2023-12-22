// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ICamelotManager.sol";
import "./ICamelotReader.sol";
import "./IChainlinkOracle.sol";
import "./IWETH.sol";
import "./ManagerAction.sol";
import "./VaultStrategy.sol";

contract CamelotARBETHNeutralVault is ERC20, Ownable, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // e.g. WETH
  IERC20 public immutable tokenA;
  // Token A decimals
  uint256 public immutable tokenADecimals;
  // e.g. USDCe
  IERC20 public immutable tokenB;
  // Token B decimals
  uint256 public immutable tokenBDecimals;
  // Vault config struct
  VaultConfig public vaultConfig;
  // Protocol treasury address
  address public treasury;
  // Timestamp of when last mgmt fee was collected
  uint256 public lastFeeCollected;
  // Manager contract
  ICamelotManager public manager;
  // Reader contract
  ICamelotReader public reader;

  /* ========== STRUCTS ========== */

  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
    // Target Token A debt ratio in 1e18
    uint256 tokenADebtRatio;
    // Target Token B debt ratio in 1e18
    uint256 tokenBDebtRatio;
    // Management fee per second in % in 1e18
    uint256 mgmtFeePerSecond;
    // Performance fee in % in 1e18
    uint256 perfFee;
    // Max capacity of vault
    uint256 maxCapacity;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant DUST_AMOUNT = 1e17;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;

  /* ========== EVENTS ========== */

  event Deposit(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event Withdraw(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event UpdateVaultConfig(VaultConfig _vaultConfig);
  event EmergencyShutdown(address indexed caller);
  event EmergencyResume(address indexed caller);

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
    * @param _name Name of vault
    * @param _symbol Symbol for contract
    * @param _tokenA TokenA address
    * @param _tokenB TokenB address
    * @param _vaultConfig VaultConfig struct details
    * @param _treasury Protocol treasury address
  */
  constructor (
    string memory _name,
    string memory _symbol,
    IERC20 _tokenA,
    IERC20 _tokenB,
    VaultConfig memory _vaultConfig,
    address _treasury
  ) ERC20(_name, _symbol) {
    require(address(_tokenA) != address(0), "Invalid address");
    require(address(_tokenB) != address(0), "Invalid address");
    tokenA = _tokenA;
    tokenB = _tokenB;
    vaultConfig = _vaultConfig;
    treasury = _treasury;
    lastFeeCollected = block.timestamp;
    tokenADecimals = ERC20(address(_tokenA)).decimals();
    tokenBDecimals = ERC20(address(_tokenB)).decimals();
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the value of each share token; obtained by total equity divided by share token supply
    * @return svTokenValue   Value of each share token in 1e18
  */
  function svTokenValue() public view returns (uint256) {
    uint256 equityValue = reader.equityValue(false);
    if (equityValue == 0 || totalSupply() == 0) return SAFE_MULTIPLIER;
    return equityValue * SAFE_MULTIPLIER / totalSupply();
  }

  /**
    * @return Amount of share pending for minting as a form of mgmt fee
  */
  function pendingMgmtFee() public view returns (uint256) {
    uint256 secondsFromLastCollection = block.timestamp - lastFeeCollected;
    return (totalSupply() * vaultConfig.mgmtFeePerSecond * secondsFromLastCollection) / SAFE_MULTIPLIER;
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
  function deposit(uint256 _amt, uint256 _minSharesAmt) external
   nonReentrant whenNotPaused {
    mintMgmtFee();

    tokenB.safeTransferFrom(msg.sender, address(manager), _amt);

    uint256 sharesToUser = _deposit(tokenB, _amt, _minSharesAmt);

    _mint(msg.sender, sharesToUser);

    emit Deposit(
      msg.sender,
      address(tokenB),
      _amt,
      sharesToUser
    );
  }

  /**
    * Deposits native asset into vault and mint svToken to user
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svToken to mint in 1e18
  */
  function depositNative(uint256 _amt, uint256 _minSharesAmt) payable external
   nonReentrant whenNotPaused {
    require(msg.value > 0, "msg.value is zero");
    require(_amt == msg.value, "Amt != msg.value");
    mintMgmtFee();

    IWETH(WETH).deposit{ value: msg.value }();
    IERC20(WETH).safeTransfer(address(manager), _amt);

    uint256 sharesToUser = _deposit(tokenB, _amt, _minSharesAmt);

    _mint(msg.sender, sharesToUser);

    emit Deposit(
      msg.sender,
      address(tokenB),
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
    _burnAndWork(_shareAmt);

    uint256 withdrawAmt = tokenB.balanceOf(address(this));
    require(withdrawAmt >= _minWithdrawAmt, "Assets received less than minimum");

    IERC20(tokenB).safeTransfer(msg.sender, withdrawAmt);

    emit Withdraw(
      msg.sender,
      address(tokenB),
      withdrawAmt,
      _shareAmt
    );
  }

  /**
    * Withdraws asset from vault, burns svToken from user
    * @param _shareAmt Amount of svTokens to burn in 1e18
    * @param _minWithdrawAmt Minimum amount of asset tokens to withdraw in token decimals
  */
  function withdrawNative(uint256 _shareAmt, uint256 _minWithdrawAmt)
  external nonReentrant whenNotPaused {
    _burnAndWork(_shareAmt);

    uint256 withdrawAmt = tokenB.balanceOf(address(this));
    require(withdrawAmt >= _minWithdrawAmt, "Assets received less than minimum");

    IWETH(WETH).withdraw(withdrawAmt);

    (bool success, ) = msg.sender.call{value: withdrawAmt}("");
    require(success, "Transfer failed.");

    emit Withdraw(
      msg.sender,
      address(tokenB),
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

    uint256 withdrawAmt = shareRatio * tokenB.balanceOf(address(this))
                          / SAFE_MULTIPLIER;

    IERC20(address(tokenB)).safeTransfer(msg.sender, withdrawAmt);

    emit Withdraw(
      msg.sender,
      address(tokenB),
      withdrawAmt,
      _shareAmt
    );
  }

  /**
    * Minting shares as a form of management fee to treasury address
  */
  function mintMgmtFee() public {
    _mint(treasury, pendingMgmtFee());
    lastFeeCollected = block.timestamp;
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
    uint256 equityBefore = reader.equityValue(true);
    uint256 depositValue = reader.tokenValue(address(_depositToken), _amt);

    require(_amt > 0, "Amt must be > 0");
    require(equityBefore + depositValue <= vaultConfig.maxCapacity, "Exceeded capacity");
    require(depositValue < reader.additionalCapacity(), "Insufficient lending liquidity");

    uint256 borrowTokenAAmt = depositValue
      * (vaultConfig.targetLeverage - 1e18)
      / SAFE_MULTIPLIER
      * vaultConfig.tokenADebtRatio
      / reader.tokenValue(address(tokenA), 10**(tokenADecimals))
      / (10 ** (18 - tokenADecimals));

    uint256 borrowTokenBAmt = depositValue
      * (vaultConfig.targetLeverage - 1e18)
      / SAFE_MULTIPLIER
      * vaultConfig.tokenBDebtRatio
      / reader.tokenValue(address(tokenB), 10**(tokenBDecimals))
      / (10 ** (18 - tokenBDecimals));

    ICamelotManager.WorkData memory data = ICamelotManager.WorkData(
      {
        token: address(tokenB),
        lpAmt: 0,
        borrowTokenAAmt: borrowTokenAAmt,
        borrowTokenBAmt: borrowTokenBAmt,
        repayTokenAAmt: 0,
        repayTokenBAmt: 0
      }
    );

    manager.work(
      ManagerAction.Deposit,  /* action */
      data
    );

    uint256 _equityChange = reader.equityValue(false) - equityBefore;

    // calculate shares to users
    uint256 sharesToUser = valueToShares(_equityChange, equityBefore);
    require(sharesToUser >= _minSharesAmt, "Shares received less than minimum");

    return sharesToUser;
  }

  /**
    * Internal withdraw function to burn svTokens, pass repay amts to manager,
    * transfer tokens back to user
    * @param _shareAmt Amount of svTokens to burn in 1e18
  */
  function _burnAndWork(uint256 _shareAmt) internal {
    // check to ensure shares withdrawn does not exceed user's balance
    require(_shareAmt > 0, "Quantity must be > 0");
    require(_shareAmt <= balanceOf(msg.sender), "Withdraw amt exceeds balance");

    mintMgmtFee();

    // to avoid leaving dust behind
    if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
      _shareAmt = balanceOf(msg.sender);
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();

    _burn(msg.sender, _shareAmt);

    // do calculations
    (uint256 tokenADebtAmt, uint256 tokenBDebtAmt) = reader.debtAmt();
    uint256 lpAmt = shareRatio * reader.lpAmt() / SAFE_MULTIPLIER;
    uint256 repayTokenAAmt = shareRatio * tokenADebtAmt / SAFE_MULTIPLIER;
    uint256 repayTokenBAmt = shareRatio * tokenBDebtAmt / SAFE_MULTIPLIER;

    ICamelotManager.WorkData memory data = ICamelotManager.WorkData(
      {
        token: address(tokenB),
        lpAmt: lpAmt,
        borrowTokenAAmt: 0,
        borrowTokenBAmt: 0,
        repayTokenAAmt: repayTokenAAmt,
        repayTokenBAmt: repayTokenBAmt
      }
    );

    manager.work(
      ManagerAction.Withdraw, /* action */
      data
    );
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Update vault config struct
    * @param _vaultConfig Vault config struct
  */
  function updateVaultConfig(VaultConfig memory _vaultConfig) external onlyOwner {
    vaultConfig = _vaultConfig;

    emit UpdateVaultConfig(_vaultConfig);
  }

  /**
    * Update addresses for manager, reader, and treasury
    * @param _type 1) manager, 2) reader, 3) treasury
    * @param _addr Address to update
  */
  function updateAddress(uint256 _type, address _addr) external onlyOwner {
    if (_type == 1) {
      manager = ICamelotManager(_addr);
    }

    if (_type == 2) {
      reader = ICamelotReader(_addr);
    }

    if (_type == 3) {
      treasury = _addr;
    }
  }

  /**
    * Approve or revoke address to be a keeper for this vault
    * @param _keeper Keeper address
    * @param _approval Boolean to approve keeper or not
  */
  function updateKeeper(address _keeper, bool _approval) external onlyOwner {
    require(_keeper != address(0), "Invalid address");
    keepers[_keeper] = _approval;
  }

  /**
    * Emergency shut down of vault that withdraws all assets, repay all debt
    * and pause all deposits and normal withdrawals
  */
  function emergencyShutdown() external onlyKeeper whenNotPaused {
    _pause();

    // calculate lp amount, repayToken amounts
    (uint256 tokenADebtAmt, uint256 tokenBDebtAmt) = reader.debtAmt();

    ICamelotManager.WorkData memory data = ICamelotManager.WorkData(
      {
        token: address(tokenB),
        lpAmt: reader.lpAmt(),
        borrowTokenAAmt: 0,
        borrowTokenBAmt: 0,
        repayTokenAAmt: tokenADebtAmt,
        repayTokenBAmt: tokenBDebtAmt
      }
    );

    // withdraw all LP amount, repay all debt and receive base tokens
    manager.work(
      ManagerAction.Withdraw /* action */,
      data
    );

    emit EmergencyShutdown(msg.sender);
  }

  /**
    * Emergency resumuption of vault that re-deposits all assets,
    * and unpauses deposits and normal withdrawals
  */
  function emergencyResume() external onlyKeeper whenPaused {
    _unpause();

    uint256 balance = tokenB.balanceOf(address(this));

    tokenB.safeTransfer(address(manager), tokenB.balanceOf(address(this)));

    _deposit(tokenB, balance, 0);

    emit EmergencyResume(msg.sender);
  }

  /**
    * Emergency pause and unpause function
  */
  function togglePause() external onlyKeeper {
    if (!paused()) {
      _pause();
    } else {
      _unpause();
    }
  }

  /* ========== FALLBACK FUNCTIONS ========== */
  /**
    * Fallback function to receive native token sent to this contract,
    * needed for receiving native token to contract when unwrapped
  */
  receive() external payable {
    require(msg.sender == WETH, "fallback function error");
  }
}

