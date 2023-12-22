// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ILevelARBLongSLLPManager.sol";
import "./ILevelARBLongSLLPReader.sol";
import "./IWETH.sol";
import "./ISLLP.sol";
import "./ManagerAction.sol";
import "./Errors.sol";

contract LevelARBLongSLLPVault is ERC20, Ownable, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Manager contract
  ILevelARBLongSLLPManager public manager;
  // Reader contract
  ILevelARBLongSLLPReader public reader;
  // Vault config struct
  VaultConfig public vaultConfig;
  // Protocol treasury address
  address public treasury;
  // Timestamp of when last mgmt fee was collected
  uint256 public lastFeeCollected;
  // Last deposited block number
  uint256 public lastDepositBlock;

  /* ========== STRUCTS ========== */

  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
    // Management fee per second in % in 1e18
    uint256 mgmtFeePerSecond;
    // Performance fee in % in 1e18
    uint256 perfFee;
    // Max capacity of vault in 1e18
    uint256 maxCapacity;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant DUST_AMOUNT = 1e17;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
  address public constant SLLP = 0x5573405636F4b895E511C9C54aAfbefa0E7Ee458;

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;
  // Mapping of approved tokens
  mapping(address => bool) public tokens;

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
  */
  function onlyKeeper() private view {
    if (!keepers[msg.sender]) revert Errors.OnlyKeeperAllowed();
  }

  /* ========== EVENTS ========== */

  event Deposit(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event Withdraw(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event UpdateVaultConfig(VaultConfig vaultConfig);

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _name Name of vault e.g. 3x Long SLLP LVL
    * @param _symbol Symbol for contract e.g. 3L-SLLP-LVL
    * @param _vaultConfig Vault config details
    * @param _treasury Protocol treasury address
  */
  constructor(
    string memory _name,
    string memory _symbol,
    VaultConfig memory _vaultConfig,
    address _treasury
  ) ERC20(_name, _symbol) {
    tokens[WETH] = true;
    tokens[WBTC] = true;
    tokens[USDT] = true;
    tokens[SLLP] = true;

    vaultConfig = _vaultConfig;
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
    return (totalSupply() * vaultConfig.mgmtFeePerSecond * secondsFromLastCollection) / SAFE_MULTIPLIER;
  }

  /**
    * Used by checkAndMint(); Conversion of equity value to svToken shares
    * @param _value Equity value change after deposit in 1e18
    * @param _currentEquity Current equity value of vault in 1e18
    * @return sharesAmt Shares amt in 1e18
  */
  function valueToShares(uint256 _value, uint256 _currentEquity) public view returns (uint256) {
    uint256 _sharesSupply = totalSupply() + pendingMgmtFee();
    if (_sharesSupply == 0 || _currentEquity == 0) return _value;
    return _value * _sharesSupply / _currentEquity;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Deposits asset into vault and mint svToken to user
    * @param _token Address of token to deposit
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svTokens to mint in 1e18
   */
  function deposit(address _token, uint256 _amt, uint256 _minSharesAmt) external nonReentrant whenNotPaused {
    if (_amt <= 0) revert Errors.EmptyDepositAmount();
    if (!tokens[_token]) revert Errors.InvalidDepositToken();

    mintMgmtFee();

    // Getting sllpPrice is gas intensive, so we only do it once
    uint256 sllpPrice = reader.sllpPrice(false);
    uint256 depositValue;

    if (_token != SLLP) {
      depositValue = reader.tokenValue(_token, _amt);
      IERC20(_token).safeTransferFrom(msg.sender, address(manager), _amt);
    } else {
      depositValue = _amt * sllpPrice / SAFE_MULTIPLIER;
      (bool success) = ISLLP(SLLP).transferFrom(msg.sender, address(manager), _amt);
      require(success, "Transfer SLLP failed");
    }

    uint256 sharesToUser = _deposit(_token, _amt, _minSharesAmt, sllpPrice, depositValue);

    _mint(msg.sender, sharesToUser);
  }

  /**
    * Deposits native asset into vault and mint svToken to user
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svTokens to mint in 1e18
   */
  function depositNative(uint256 _amt, uint256 _minSharesAmt) payable external nonReentrant whenNotPaused {
    if (msg.value <= 0) revert Errors.EmptyDepositAmount();
    if (_amt != msg.value) revert Errors.InvalidNativeDepositAmountValue();

    mintMgmtFee();

    uint256 sllpPrice = reader.sllpPrice(false);
    uint256 depositValue = reader.tokenValue(WETH, _amt);

    IWETH(WETH).deposit{ value: msg.value }();
    IERC20(WETH).safeTransfer(address(manager), _amt);

    uint256 sharesToUser = _deposit(WETH, _amt, _minSharesAmt, sllpPrice, depositValue);

    _mint(msg.sender, sharesToUser);
  }

  /**
    * Withdraws asset from vault, burns svToken from user
    * @param _token Token to withdraw in
    * @param _shareAmt Amount of svTokens to burn in 1e18
    * @param _minWithdrawAmt Minimum amount of asset tokens to withdraw in token decimals
  */
  function withdraw(address _token, uint256 _shareAmt, uint256 _minWithdrawAmt) external nonReentrant whenNotPaused {
    if (!tokens[_token]) revert Errors.InvalidWithdrawToken();

    _burnAndWork(_token, _shareAmt);

    uint256 withdrawAmt;
    if (_token != SLLP) {
      withdrawAmt = IERC20(_token).balanceOf(address(this));
      IERC20(_token).safeTransfer(msg.sender, withdrawAmt);
    } else {
      withdrawAmt = ISLLP(SLLP).balanceOf(address(this));
      (bool success) = ISLLP(SLLP).transfer(msg.sender, withdrawAmt);
      require(success, "Transfer SLLP failed");
    }

    if (withdrawAmt < _minWithdrawAmt) revert Errors.InsufficientAssetsReceived();

    emit Withdraw(
      msg.sender,
      _token,
      withdrawAmt,
      _shareAmt
    );
  }

  /**
    * Withdraws native asset from vault, burns svToken from user
    * @param _shareAmt Amount of svTokens to burn in 1e18
    * @param _minWithdrawAmt Minimum amount of asset tokens to withdraw in token decimals
  */
  function withdrawNative(uint256 _shareAmt, uint256 _minWithdrawAmt) external nonReentrant whenNotPaused() {
    _burnAndWork(WETH, _shareAmt);

    uint256 withdrawAmt = IERC20(WETH).balanceOf(address(this));
    if (withdrawAmt < _minWithdrawAmt) revert Errors.InsufficientAssetsReceived();

    IWETH(WETH).withdraw(withdrawAmt);

    (bool success, ) = msg.sender.call{value: withdrawAmt}("");
    require(success, "Transfer failed.");

    emit Withdraw(
      msg.sender,
      WETH,
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
    if (_shareAmt <= 0) revert Errors.EmptyWithdrawAmount();
    if (_shareAmt > balanceOf(msg.sender)) revert Errors.InsufficientWithdrawBalance();

    // to avoid leaving dust behind
    unchecked {
      if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
        _shareAmt = balanceOf(msg.sender);
      }
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();

    _burn(msg.sender, _shareAmt);

    uint256 withdrawAmt = shareRatio * IERC20(USDT).balanceOf(address(this)) / SAFE_MULTIPLIER;

    IERC20(USDT).safeTransfer(msg.sender, withdrawAmt);

    emit Withdraw(
      msg.sender,
      USDT,
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

  function _deposit(
    address _token,
    uint256 _amt,
    uint256 _minSharesAmt,
    uint256 _sllpPrice,
    uint256 _depositValue
  ) internal returns (uint256) {
    uint256 equityBefore = reader.assetValueWithPrice(_sllpPrice) - reader.debtValue();

    if (_depositValue <= DUST_AMOUNT) revert Errors.InsufficientDepositAmount();
    if ((equityBefore + _depositValue) > vaultConfig.maxCapacity) revert Errors.InsufficientCapacity();
    if (_depositValue >= reader.additionalCapacity()) revert Errors.InsufficientLendingLiquidity();

    // calculate amt of USDT to borrow
    uint256 borrowTokenAmt = _depositValue
      * (vaultConfig.targetLeverage - 1e18)
      / reader.tokenValue(USDT, 1e6)
      / 10**(18 - 6);

    ILevelARBLongSLLPManager.WorkData memory data = ILevelARBLongSLLPManager.WorkData(
      {
        token: _token,
        lpAmt: 0,
        borrowUSDTAmt: borrowTokenAmt,
        repayUSDTAmt: 0
      }
    );

    manager.work(
      ManagerAction.Deposit, /* action */
      data
    );

    // calculate shares to users
    uint256 sharesToUser = valueToShares(
      (reader.assetValueWithPrice(_sllpPrice) - reader.debtValue()) - equityBefore, // equityChange
      equityBefore
    );
    if (sharesToUser < _minSharesAmt) revert Errors.InsufficientSharesMinted();

    lastDepositBlock = block.number;

    emit Deposit(
      msg.sender,
      _token,
      _amt,
      sharesToUser
    );

    return sharesToUser;
  }

  /**
    * Internal withdraw function to burn svTokens, pass repay amts to manager
    * @param _shareAmt Amount of svTokens to burn in 1e18
  */
  function _burnAndWork(address _token, uint256 _shareAmt) internal {
    if (block.number == lastDepositBlock) revert Errors.WithdrawNotAllowedInSameDepositBlock();
    if (_shareAmt <= 0) revert Errors.EmptyWithdrawAmount();
    if (_shareAmt > balanceOf(msg.sender)) revert Errors.InsufficientWithdrawBalance();

    mintMgmtFee();

    // to avoid leaving dust behind
    unchecked {
      if (balanceOf(msg.sender) - _shareAmt < DUST_AMOUNT) {
        _shareAmt = balanceOf(msg.sender);
      }
    }

    // share ratio calculation must be before burn()
    uint256 shareRatio = _shareAmt * SAFE_MULTIPLIER / totalSupply();
    _burn(msg.sender, _shareAmt);

    ILevelARBLongSLLPManager.WorkData memory data = ILevelARBLongSLLPManager.WorkData(
      {
        token: _token,
        lpAmt: shareRatio * manager.lpAmt() / SAFE_MULTIPLIER,
        borrowUSDTAmt: 0,
        repayUSDTAmt: shareRatio * manager.debtAmt() / SAFE_MULTIPLIER
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
      manager = ILevelARBLongSLLPManager(_addr);
    }

    if (_type == 2) {
      reader = ILevelARBLongSLLPReader(_addr);
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
    keepers[_keeper] = _approval;
  }

  /**
    * Emergency shut down of vault that withdraws all assets, repay all debt
    * and pause all deposits and normal withdrawals
  */
  function emergencyShutDown() external whenNotPaused {
    onlyKeeper();

    uint256 debtUSDT = manager.debtAmt();

    ILevelARBLongSLLPManager.WorkData memory data = ILevelARBLongSLLPManager.WorkData(
      {
        token: USDT,
        lpAmt: manager.lpAmt(),
        borrowUSDTAmt: 0,
        repayUSDTAmt: debtUSDT
      }
    );
    // Unstake and transfer LVL rewards to owner
    manager.unstakeAndTransferLVL();

    // withdraw all LP amount, repay all debt and receive base tokens
    manager.work(
      ManagerAction.Withdraw, /* action */
      data
    );
  }

  /**
    * Emergency resumuption of vault that re-deposits all assets,
    * and unpauses deposits and normal withdrawals
  */
  function emergencyResume() external whenPaused {
    onlyKeeper();

    _unpause();

    uint256 balance = IERC20(USDT).balanceOf(address(this));
    uint256 sllpPrice = reader.sllpPrice(false);
    uint256 depositValue = reader.tokenValue(USDT, balance);

    IERC20(USDT).safeTransfer(address(manager), balance);

    _deposit(USDT, balance, 0, sllpPrice, depositValue);
  }

  /**
    * Emergency pause and unpause function
  */
  function togglePause() external {
    onlyKeeper();

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

