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
import "./IWETH.sol";
import "./IStakedGLP.sol";
import "./ManagerAction.sol";

contract GMXPerpetualDEXLongARBVault is ERC20, Ownable, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Manager contract
  IGMXPerpetualDEXLongManager public manager;
  // Reader contract
  IGMXPerpetualDEXLongReader public reader;
  // Vault config struct
  VaultConfig public vaultConfig;
  // Protocol treasury address
  address public treasury;
  // Timestamp of when last mgmt fee was collected
  uint256 public lastFeeCollected;

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
  uint256 public constant USDC_DECIMALS = 6;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
  address public constant STAKED_GLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
  */
  modifier onlyKeeper() {
    require(keepers[msg.sender], "Keeper not approved");
    _;
  }

  /* ========== EVENTS ========== */

  event Deposit(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event Withdraw(address indexed user, address asset, uint256 assetAmt, uint256 sharesAmt);
  event UpdateVaultConfig(VaultConfig _vaultConfig);

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _name Name of vault e.g. 3x Long GLP GMX
    * @param _symbol Symbol for contract e.g. 3L-GLP-GMX
    * @param _vaultConfig Vault config details
    * @param _treasury Protocol treasury address
  */
  constructor (
    string memory _name,
    string memory _symbol,
    VaultConfig memory _vaultConfig,
    address _treasury
  ) ERC20(_name, _symbol) {
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
    if (_sharesSupply == 0) return _value;
    return _value * _sharesSupply / _currentEquity;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Deposits asset into vault and mint svToken to user
    * @param _token Address of token to deposit
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svTokens to mint in 1e18
   */
  function deposit(address _token, uint256 _amt, uint256 _minSharesAmt) external nonReentrant whenNotPaused onlyOwner {
    require(_amt > 0, "Amt must be > 0");
    require(
      _token == USDC || _token == STAKED_GLP || _token == WETH || _token == WBTC,
      "Invalid token"
    );

    mintMgmtFee();

    // Getting glpPrice is gas intensive, so we only do it once
    uint256 glpPrice = reader.glpPrice(false);
    uint256 depositValue;
    uint256 equityBefore;

    if (_token != STAKED_GLP) {
      depositValue = reader.tokenValue(_token, _amt);
      // Don't use reader.equityValue() here to avoid computing glpPrice twice
      equityBefore = reader.assetValueWithPrice(glpPrice) - reader.debtValue();
      IERC20(_token).safeTransferFrom(msg.sender, address(manager), _amt);
    } else {
      depositValue = _amt * glpPrice / SAFE_MULTIPLIER;
      // equityBefore must be checked before transfer of GLP so as to not include GLP deposit value
      equityBefore = reader.assetValueWithPrice(glpPrice) - reader.debtValue();
      (bool success) = IStakedGLP(STAKED_GLP).transferFrom(msg.sender, address(manager), _amt);
      require(success, "Transfer sGLP failed");
    }

    _deposit(_token, _amt, _minSharesAmt, glpPrice, depositValue, equityBefore);
  }

  /**
    * Deposits native asset into vault and mint svToken to user
    * @param _amt Amount of asset tokens to deposit in token decimals
    * @param _minSharesAmt Minimum amount of svTokens to mint in 1e18
   */
  function depositETH(uint256 _amt, uint256 _minSharesAmt) payable external nonReentrant whenNotPaused onlyOwner {
    require(msg.value > 0, "msg.value is zero");
    require(_amt == msg.value, "Amt != msg.value");

    mintMgmtFee();

    uint256 glpPrice = reader.glpPrice(false);
    uint256 depositValue = reader.tokenValue(WETH, _amt);
    uint256 equityBefore = reader.assetValueWithPrice(glpPrice) - reader.debtValue();

    IWETH(WETH).deposit{ value: msg.value }();
    IERC20(WETH).safeTransfer(address(manager), _amt);

    _deposit(WETH, _amt, _minSharesAmt, glpPrice, depositValue, equityBefore);
  }

  /**
    * Withdraws asset from vault, burns svToken from user
    * @param _token Token to withdraw in
    * @param _shareAmt Amount of svTokens to burn in 1e18
    * @param _minWithdrawAmt Minimum amount of asset tokens to withdraw in token decimals
  */
  function withdraw(address _token, uint256 _shareAmt, uint256 _minWithdrawAmt) external nonReentrant whenNotPaused {
    require(
      _token == USDC || _token == STAKED_GLP || _token == WETH || _token == WBTC,
      "Invalid token"
    );

    _burnAndWork(_token, _shareAmt);

    uint256 withdrawAmt;
    if (_token != STAKED_GLP) {
      withdrawAmt = IERC20(_token).balanceOf(address(this));
      IERC20(_token).safeTransfer(msg.sender, withdrawAmt);
    } else {
      withdrawAmt = IStakedGLP(STAKED_GLP).balanceOf(address(this));
      (bool success) = IStakedGLP(STAKED_GLP).transfer(msg.sender, withdrawAmt);
      require(success, "Transfer sGLP failed");
    }

    require(withdrawAmt >= _minWithdrawAmt, "Assets received less than minimum");

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
  function withdrawETH(uint256 _shareAmt, uint256 _minWithdrawAmt) external nonReentrant whenNotPaused() {
    _burnAndWork(WETH, _shareAmt);

    uint256 withdrawAmt = IERC20(WETH).balanceOf(address(this));
    require(withdrawAmt >= _minWithdrawAmt, "Assets received less than minimum");

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

    uint256 withdrawAmt = shareRatio * IERC20(USDC).balanceOf(address(this)) / SAFE_MULTIPLIER;

    IERC20(USDC).safeTransfer(msg.sender, withdrawAmt);

    emit Withdraw(
      msg.sender,
      USDC,
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
    uint256 _glpPrice,
    uint256 _depositValue,
    uint256 _equityBefore
  ) internal {
    require(_depositValue >= DUST_AMOUNT, "Deposit value too low");
    require(_equityBefore + _depositValue <= vaultConfig.maxCapacity, "Exceeded capacity");
    require(_depositValue < reader.additionalCapacity(), "Insufficient lending liquidity");

    // calculate amt of USDC to borrow
    uint256 borrowTokenAmt = _depositValue
      * (vaultConfig.targetLeverage - 1e18)
      / reader.tokenValue(USDC, 10**USDC_DECIMALS)
      / 10**(18 - USDC_DECIMALS); // account for usdc decimals

    IGMXPerpetualDEXLongManager.WorkData memory data = IGMXPerpetualDEXLongManager.WorkData(
      {
        token: _token,
        lpAmt: 0,
        borrowUSDCAmt: borrowTokenAmt,
        repayUSDCAmt: 0
      }
    );

    manager.work(
      ManagerAction.Deposit, /* action */
      data
    );

    uint256 _equityChange = (reader.assetValueWithPrice(_glpPrice) - reader.debtValue()) - _equityBefore;

    // calculate shares to users
    uint256 sharesToUser = valueToShares(_equityChange, _equityBefore);
    require(sharesToUser >= _minSharesAmt, "Shares received less than minimum");

    _mint(msg.sender, sharesToUser);

    emit Deposit(
      msg.sender,
      _token,
      _amt,
      sharesToUser
    );
  }

  /**
    * Internal withdraw function to burn svTokens, pass repay amts to manager
    * @param _shareAmt Amount of svTokens to burn in 1e18
  */
  function _burnAndWork(address _token, uint256 _shareAmt) internal {
    require(_shareAmt > 0, "Quantity must be > 0");
    require(_shareAmt <= balanceOf(msg.sender), "Withdraw amt exceeds balance");

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

    uint256 debtUSDC = manager.debtAmt();

    IGMXPerpetualDEXLongManager.WorkData memory data = IGMXPerpetualDEXLongManager.WorkData(
      {
        token: _token,
        lpAmt: shareRatio * manager.lpAmt() / SAFE_MULTIPLIER,
        borrowUSDCAmt: 0,
        repayUSDCAmt: shareRatio * debtUSDC / SAFE_MULTIPLIER
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
      manager = IGMXPerpetualDEXLongManager(_addr);
    }

    if (_type == 2) {
      reader = IGMXPerpetualDEXLongReader(_addr);
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
  function emergencyShutDown() external onlyOwner whenNotPaused {
    _pause();

    uint256 debtUSDC = manager.debtAmt();

    IGMXPerpetualDEXLongManager.WorkData memory data = IGMXPerpetualDEXLongManager.WorkData(
      {
        token: USDC,
        lpAmt: manager.lpAmt(),
        borrowUSDCAmt: 0,
        repayUSDCAmt: debtUSDC
      }
    );

    // withdraw all LP amount, repay all debt and receive base tokens
    manager.work(
      ManagerAction.Withdraw, /* action */
      data
    );
  }

  /**
    * Emergency pause and unpause function
  */
  function togglePause() external onlyKeeper() {
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

