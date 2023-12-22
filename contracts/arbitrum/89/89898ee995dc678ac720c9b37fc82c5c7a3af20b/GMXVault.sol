// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Ownable } from "./Ownable.sol";
import { Ownable2Step } from "./Ownable2Step.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Pausable } from "./Pausable.sol";
import { IWNT } from "./IWNT.sol";
import { IGMXVault } from "./IGMXVault.sol";
import { ILendingVault } from "./ILendingVault.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IGMXOracle } from "./IGMXOracle.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";
import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { ISwap } from "./ISwap.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXDeposit } from "./GMXDeposit.sol";
import { GMXWithdraw } from "./GMXWithdraw.sol";
import { GMXRebalance } from "./GMXRebalance.sol";
import { GMXCompound } from "./GMXCompound.sol";
import { GMXEmergency } from "./GMXEmergency.sol";
import { GMXReader } from "./GMXReader.sol";

/**
  * @title GMXVault
  * @author Steadefi
  * @notice Main point of interaction with a Steadefi leveraged strategy vault
  * - Users can:
  *   - Deposit assets
  *   - Withdraw assets
  *   - Emergency withdraw of assets
  * - Approved protocol keepers can:
  *   - Compound token rewards for more LP
  *   - Rebalance vault
  *   - Emergency pause vault
  *   - Emergency resume vault
  *   - Emergency close vault
  * - Vault owner (Timelock + MultiSig) can:
  *   - Approve/revoke keepers
  *   - Update treasury
  *   - Update swap router
  *   - Update callback (one-time on intialization)
  *   - Update management fee per second
  *   - Update performance fee
  *   - Update strategy parameters
  *   - Update minimum slippage
  *   - Update minimum execution fee for GMX
  * - Anyone can view and read vault data such as:
  *   - Equity value
  *   - Debt value, amounts
  *   - Asset value, amounts
  *   - Debt ratio
  *   - Delta
  *   - Leverage
  *   - Capacity and additional capacity
  *   - Amount of LP
  *   - Token weights in LP
  *   - Strategy vault token value
*/
contract GMXVault is ERC20, Ownable2Step, ReentrancyGuard, Pausable, IGMXVault {
  using SafeERC20 for IERC20;

  /* ==================== STATE VARIABLES ==================== */

  // GMXTypes.Store
  GMXTypes.Store internal _store;

  /* ======================= MAPPINGS ======================== */

  // Approved keepers
  mapping(address => bool) public keepers;
  // Approved tokens for deposit and withdraw
  mapping(address => bool) public tokens;

  /* ======================= MODIFIERS ======================= */

  // Allow only vault modifier
  modifier onlyVault() {
    _onlyVault();
    _;
  }

  // Allow only keeper modifier
  modifier onlyKeeper() {
    _onlyKeeper();
    _;
  }

  /* ======================== EVENTS ========================= */

  event KeeperUpdated(address keeper, bool approval);
  event TreasuryUpdated(address treasury);
  event SwapRouterUpdated(address router);
  event CallbackUpdated(address callback);
  event MgmtFeePerSecondUpdated(uint256 mgmtFeePerSecond);
  event PerformanceFeeUpdated(uint256 performanceFee);
  event ParameterLimitsUpdated(
    uint256 debtRatioStepThreshold,
    uint256 debtRatioUpperLimit,
    uint256 debtRatioLowerLimit,
    int256 deltaUpperLimit,
    int256 deltaLowerLimit
  );
  event MinSlippageUpdated(uint256 minSlippage);
  event MinExecutionFeeUpdated(uint256 minExecutionFee);

  /* ====================== CONSTRUCTOR ====================== */

  /**
    * @notice Initialize and configure vault's store, token approvals and whitelists
    * @param name Name of vault
    * @param symbol Symbol for vault token
    * @param store_ GMXTypes.Store
  */
  constructor (
    string memory name,
    string memory symbol,
    GMXTypes.Store memory store_
  ) ERC20(name, symbol) Ownable(msg.sender) {
    _store.leverage = uint256(store_.leverage);
    _store.delta = store_.delta;
    _store.mgmtFeePerSecond = uint256(store_.mgmtFeePerSecond);
    _store.performanceFee = uint256(store_.performanceFee);
    _store.treasury = address(store_.treasury);

    _store.debtRatioStepThreshold = uint256(store_.debtRatioStepThreshold);
    _store.debtRatioUpperLimit = uint256(store_.debtRatioUpperLimit);
    _store.debtRatioLowerLimit = uint256(store_.debtRatioLowerLimit);
    _store.deltaUpperLimit = int256(store_.deltaUpperLimit);
    _store.deltaLowerLimit = int256(store_.deltaLowerLimit);
    _store.minSlippage = store_.minSlippage;
    _store.minExecutionFee = store_.minExecutionFee;

    _store.tokenA = IERC20(store_.tokenA);
    _store.tokenB = IERC20(store_.tokenB);
    _store.lpToken = IERC20(store_.lpToken);
    _store.WNT = IWNT(store_.WNT);

    _store.tokenALendingVault = ILendingVault(store_.tokenALendingVault);
    _store.tokenBLendingVault = ILendingVault(store_.tokenBLendingVault);

    _store.vault = IGMXVault(address(this));
    _store.callback = store_.callback;

    _store.chainlinkOracle = IChainlinkOracle(store_.chainlinkOracle);
    _store.gmxOracle = IGMXOracle(store_.gmxOracle);

    _store.exchangeRouter = IExchangeRouter(store_.exchangeRouter);
    _store.router = store_.router;
    _store.depositVault = store_.depositVault;
    _store.withdrawalVault = store_.withdrawalVault;
    _store.roleStore = store_.roleStore;

    _store.swapRouter = ISwap(store_.swapRouter);

    _store.status = GMXTypes.Status.Open;

    _store.lastFeeCollected = block.timestamp;

    // Set token whitelist for this vault
    tokens[address(_store.tokenA)] = true;
    tokens[address(_store.tokenB)] = true;
    tokens[address(_store.lpToken)] = true;

    // Set token approvals for this vault
    _store.tokenA.approve(address(_store.router), type(uint256).max);
    _store.tokenB.approve(address(_store.router), type(uint256).max);
    _store.lpToken.approve(address(_store.router), type(uint256).max);

    _store.tokenA.approve(address(_store.depositVault), type(uint256).max);
    _store.tokenB.approve(address(_store.depositVault), type(uint256).max);

    _store.lpToken.approve(address(_store.withdrawalVault), type(uint256).max);

    _store.tokenA.approve(address(_store.tokenALendingVault), type(uint256).max);
    _store.tokenB.approve(address(_store.tokenBLendingVault), type(uint256).max);

    // Set callback contract as keeper
    keepers[_store.callback] = true;
  }

  /* ===================== VIEW FUNCTIONS ==================== */

  /**
    * @notice View vault store data
    * @return GMXTypes.Store
  */
  function store() public view returns (GMXTypes.Store memory) {
    return _store;
  }

  /**
    * @notice Check if token is whitelisted for deposit/withdraw for this vault
    * @param token Address of token to check
    * @return Boolean of whether token is whitelisted
  */
  function isTokenWhitelisted(address token) public view returns (bool) {
    return tokens[token];
  }

  /**
    * @notice Returns the value of each strategy vault share token; equityValue / totalSupply()
    * @return svTokenValue  USD value of each share token in 1e18
  */
  function svTokenValue() public view returns (uint256) {
    return GMXReader.svTokenValue(_store);
  }

  /**
    * @notice Amount of share pending for minting as a form of mgmt fee
    * @return pendingMgmtFee in 1e18
  */
  function pendingMgmtFee() public view returns (uint256) {
    return GMXReader.pendingMgmtFee(_store);
  }

  /**
    * @notice Conversion of equity value to svToken shares
    * @param value Equity value change after deposit in 1e18
    * @param currentEquity Current equity value of vault in 1e18
    * @return sharesAmt in 1e18
  */
  function valueToShares(uint256 value, uint256 currentEquity) public view returns (uint256) {
    return GMXReader.valueToShares(_store, value, currentEquity);
  }

  /**
    * @notice Convert token amount to USD value using price from oracle
    * @param token Token address
    * @param amt Amount in token decimals
    @ @return tokenValue USD value in 1e18
  */
  function convertToUsdValue(address token, uint256 amt) public view returns (uint256) {
    return GMXReader.convertToUsdValue(_store, token, amt);
  }

  /**
    * @notice Return token weights (%) in LP
    @ @return tokenAWeight in 1e18; e.g. 50% = 5e17
    @ @return tokenBWeight in 1e18; e.g. 50% = 5e17
  */
  function tokenWeights() public view returns (uint256, uint256) {
    return GMXReader.tokenWeights(_store);
  }

  /**
    * @notice Returns the total USD value of tokenA & tokenB assets held by the vault
    * @notice Asset = Debt + Equity
    * @return assetValue USD value of total assets in 1e18
  */
  function assetValue() public view returns (uint256) {
    return GMXReader.assetValue(_store);
  }

  /**
    * @notice Returns the USD value of tokenA & tokenB debt held by the vault
    * @notice Asset = Debt + Equity
    * @return tokenADebtValue USD value of tokenA debt in 1e18
    * @return tokenBDebtValue USD value of tokenB debt in 1e18
  */
  function debtValue() public view returns (uint256, uint256) {
    return GMXReader.debtValue(_store);
  }

  /**
    * @notice Returns the USD value of tokenA & tokenB equity held by the vault;
    * @notice Asset = Debt + Equity
    * @return equityValue USD value of total equity in 1e18
  */
  function equityValue() public view returns (uint256) {
    return GMXReader.equityValue(_store);
  }

  /**
    * @notice Returns the amt of tokenA & tokenB assets held by vault
    * @return tokenAAssetAmt in tokenA decimals
    * @return tokenBAssetAmt in tokenB decimals
  */
  function assetAmt() public view returns (uint256, uint256) {
    return GMXReader.assetAmt(_store);
  }

  /**
    * @notice Returns the amt of tokenA & tokenB debt held by vault
    * @return tokenADebtAmt in tokenA decimals
    * @return tokenBDebtAmt in tokenB decimals
  */
  function debtAmt() public view returns (uint256, uint256) {
    return GMXReader.debtAmt(_store);
  }

  /**
    * @notice Returns the amt of LP tokens held by vault
    * @return lpAmt in 1e18
  */
  function lpAmt() public view returns (uint256) {
    return GMXReader.lpAmt(_store);
  }

  /**
    * @notice Returns the current leverage (asset / equity)
    * @return leverage Current leverage in 1e18
  */
  function leverage() public view returns (uint256) {
    return GMXReader.leverage(_store);
  }

  /**
    * @notice Returns the current delta (tokenA equityValue / vault equityValue)
    * @notice Delta refers to the position exposure of this vault's strategy to the
    * underlying volatile asset. Delta can be a negative value
    * @return delta in 1e18 (0 = Neutral, > 0 = Long, < 0 = Short)
  */
  function delta() public view returns (int256) {
    return GMXReader.delta(_store);
  }

  /**
    * @notice Returns the debt ratio (tokenA and tokenB debtValue) / (total assetValue)
    * @notice When assetValue is 0, we assume the debt ratio to also be 0
    * @return debtRatio % in 1e18
  */
  function debtRatio() public view returns (uint256) {
    return GMXReader.debtRatio(_store);
  }

  /**
    * @notice Additional capacity vault that can be deposited to vault based on available lending liquidity
    @ @return additionalCapacity USD value in 1e18
  */
  function additionalCapacity() public view returns (uint256) {
    return GMXReader.additionalCapacity(_store);
  }

  /**
    * @notice Total capacity of vault; additionalCapacity + equityValue
    @ @return capacity USD value in 1e18
  */
  function capacity() public view returns (uint256) {
    return GMXReader.capacity(_store);
  }

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice Deposit a whitelisted asset into vault and mint strategy vault share tokens to user
    * @param dp GMXTypes.DepositParams
  */
  function deposit(GMXTypes.DepositParams memory dp) external payable nonReentrant whenNotPaused {
    GMXDeposit.depositERC20(_store, dp);
  }

  /**
    * @notice Deposit native asset (e.g. ETH) into vault and mint strategy vault share tokens to user
    * @notice This function is only function if vault accepts native token
    * @param dp GMXTypes.DepositParams
  */
  function depositNative(GMXTypes.DepositParams memory dp) external payable nonReentrant whenNotPaused {
    GMXDeposit.depositNative(_store, dp);
  }

  /**
    * @notice Withdraws a whitelisted asset from vault and burns strategy vault share tokens from user
    * @param wp GMXTypes.WithdrawParams
  */
  function withdraw(GMXTypes.WithdrawParams memory wp) external payable nonReentrant whenNotPaused {
    GMXWithdraw.withdraw(_store, wp);
  }

  /**
    * @notice Emergency withdraw function, enabled only when vault is paused, burns svToken from user
    * @param shareAmt Amount of vault token shares to withdraw in 1e18
  */
  function emergencyWithdraw(uint256 shareAmt) external nonReentrant whenPaused {
    GMXEmergency.emergencyWithdraw(_store, shareAmt);
  }

  /**
    * @notice Mint vault token shares as management fees to protocol treasury
  */
  function mintMgmtFee() public {
    _mint(_store.treasury, GMXReader.pendingMgmtFee(_store));
    _store.lastFeeCollected = block.timestamp;
  }

  /* ================== INTERNAL FUNCTIONS =================== */

  /**
    * @notice Allow only vault
  */
  function _onlyVault() internal view {
    if (msg.sender != address(_store.vault)) revert Errors.OnlyVaultAllowed();
  }

  /**
    * @notice Allow only keeper
  */
  function _onlyKeeper() internal view {
    if (!keepers[msg.sender]) revert Errors.OnlyKeeperAllowed();
  }

  /* ================= RESTRICTED FUNCTIONS ================== */

  /**
    * @notice Post deposit operations if adding liquidity is successful
    * @dev Should be called only after deposit() / depositNative() is called
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processDeposit() external whenNotPaused onlyKeeper {
    GMXDeposit.processDeposit(_store);
  }

  /**
    * @notice Post deposit operations if adding liquidity has been cancelled
    * @dev To be called only after deposit()/depositNative() is called
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processDepositCancellation() external whenNotPaused onlyKeeper {
    GMXDeposit.processDepositCancellation(_store);
  }

  /**
    * @notice Post deposit operations if after deposit checks failed
    * @dev To be called only if afterDepositChecks() failed
    * @dev Should be called by approved Keeper after error event is picked up
    * @param slippage Slippage for liquidity removal
    * @param executionFee Execution fee passed in to remove liquidity
  */
  function processDepositFailure(
    uint256 slippage,
    uint256 executionFee
  ) external payable whenNotPaused onlyKeeper {
    GMXDeposit.processDepositFailure(_store, slippage, executionFee);
  }

  /**
    * @notice Post deposit failure operations
    * @dev To be called after processDepositFailure()
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processDepositFailureLiquidityWithdrawal() external whenNotPaused onlyKeeper {
    GMXDeposit.processDepositFailureLiquidityWithdrawal(_store);
  }

  /**
    * @notice Post withdraw operations if removing liquidity is successful
    * @dev Should be called only after withdraw() is called
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processWithdraw() external whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdraw(_store);
  }

  /**
    * @notice Post withdraw operations if removing liquidity has been cancelled
    * @dev To be called only after withdraw() is called
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processWithdrawCancellation() external whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdrawCancellation(_store);
  }

  /**
    * @notice Post withdraw operations if after withdraw checks failed
    * @dev To be called only if afterWithdrawChecks() failed
    * @dev Should be called by approved Keeper after error event is picked up
    * @param slippage Slippage for liquidity removal
    * @param executionFee Execution fee passed in to remove liquidity
  */
  function processWithdrawFailure(
    uint256 slippage,
    uint256 executionFee
  ) external payable whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdrawFailure(_store, slippage, executionFee);
  }

  /**
    * @notice Post withdraw failure operations
    * @dev To be called after processWithdrawFailure()
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processWithdrawFailureLiquidityAdded() external whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdrawFailureLiquidityAdded(_store);
  }

  /**
    * @notice Rebalance vault's delta and/or debt ratio by adding liquidity
    * @dev Should be called by approved Keeper
    * @param rap GMXTypes.RebalanceAddParams
  */
  function rebalanceAdd(
    GMXTypes.RebalanceAddParams memory rap
  ) external payable nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.rebalanceAdd(_store, rap);
  }

  /**
    * @notice Post rebalance add operations if adding liquidity is successful
    * @dev To be called after rebalanceAdd()
  */
  function processRebalanceAdd() external nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceAdd(_store);
  }

  /**
    * @notice Post rebalance add operations if adding liquidity has been cancelled
    * @dev To be called only after rebalanceAdd() is called
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processRebalanceAddCancellation() external nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceAddCancellation(_store);
  }

  /**
    * @notice Rebalance vault's delta and/or debt ratio by removing liquidity
    * @dev Should be called by approved Keeper
    * @param rrp GMXTypes.RebalanceRemoveParams
  */
  function rebalanceRemove(
    GMXTypes.RebalanceRemoveParams memory rrp
  ) external payable nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.rebalanceRemove(_store, rrp);
  }

  /**
    * @notice Post rebalance remove operations if removing liquidity is successful
    * @dev To be called after rebalanceRemove()
  */
  function processRebalanceRemove() external whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceRemove(_store);
  }

  /**
    * @notice Post rebalance remove operations if removing liquidity has been cancelled
    * @dev To be called only after rebalanceRemove() is called
    * @dev Should be called by approved vault's Callback or approved Keeper
  */
  function processRebalanceRemoveCancellation() external nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceRemoveCancellation(_store);
  }

  /**
    * @notice Compounds ERC20 token rewards and convert to more LP
    * @dev Assumes that reward tokens are already in vault
    * @dev Should be called by approved Keeper
    * @param cp GMXTypes.CompoundParams
  */
  function compound(GMXTypes.CompoundParams memory cp) external payable whenNotPaused onlyKeeper {
    GMXCompound.compound(_store, cp);
  }

  /**
    * @notice Post compound operations if adding liquidity is successful
    * @dev To be called after processCompound()
    * @dev Should be called by approved Keeper
  */
  function processCompound() external whenNotPaused onlyKeeper {
    GMXCompound.processCompound(_store);
  }

    /**
    * @notice Post compound operations if adding liquidity has been cancelled
    * @dev To be called after processCompound()
    * @dev Should be called by approved Keeper
  */
  function processCompoundCancellation() external whenNotPaused onlyKeeper {
    GMXCompound.processCompoundCancellation(_store);
  }

  /**
    * @notice Withdraws LP for all underlying assets to vault and pause vault operations
    * @dev To be called only in an emergency situation
    * @dev Should be called by approved Keeper
  */
  function emergencyPause() external payable whenNotPaused onlyKeeper {
    _pause();
    GMXEmergency.emergencyPause(_store);
  }

  /**
    * @notice Re-add all assets for liquidity for LP in anticipation of vault resuming
    * @dev To manually call unpause() after liquidity is added to allow interactions with vault
    * @dev Should be called by approved Owner (Timelock + MultiSig)
  */
  function emergencyResume() external payable whenPaused onlyOwner {
    GMXEmergency.emergencyResume(_store);
  }

  /**
    * @notice Repays all debt owed by vault and shut down vault, allowing emergency withdrawals
    * @dev To be called only after emergencyPause()
    * @dev Note that this is a one-way irreversible action
    * @dev Should be called by approved Owner (Timelock + MultiSig)
  */
  function emergencyClose() external whenPaused onlyOwner {
    GMXEmergency.emergencyClose(_store);
  }

  /**
    * @notice Pause vault while allowing vault strategy to still run
    * @dev To be called only in a situation to stop deposits/withdrawals/rebalances
    * @dev Should be called by approved Keeper
  */
  function pause() external whenNotPaused onlyKeeper {
    _pause();
  }

  /**
    * @notice Unpause vault and set status of vault to Open
    * @dev Note that this is to be called after emergencyResume()
    * @dev Should be called by approved Owner (Timelock + MultiSig)
  */
  function unpause() external whenPaused onlyOwner {
    _unpause();
    _store.status = GMXTypes.Status.Open;
  }

  /**
    * @notice Approve or revoke address to be a keeper for this vault
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param keeper Keeper address
    * @param approval Boolean to approve keeper or not
  */
  function updateKeeper(address keeper, bool approval) external onlyOwner {
    keepers[keeper] = approval;
    emit KeeperUpdated(keeper, approval);
  }

  /**
    * @notice Update treasury address
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param treasury Treasury address
  */
  function updateTreasury(address treasury) external onlyOwner {
    _store.treasury = treasury;
    emit TreasuryUpdated(treasury);
  }

  /**
    * @notice Update swap router address
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param swapRouter Swap router address
  */
  function updateSwapRouter(address swapRouter) external onlyOwner {
    _store.swapRouter = ISwap(swapRouter);
    emit SwapRouterUpdated(swapRouter);
  }

  /**
    * @notice Update callback address
    * @dev Should only be calle once on vault initialization
    * @param callback Callback address
  */
  function updateCallback(address callback) external onlyOwner {
    _store.callback = callback;
    emit CallbackUpdated(callback);
  }

  /**
    * @notice Update management fee per second
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param mgmtFeePerSecond fee per second in 1e18
  */
  function updateMgmtFeePerSecond(uint256 mgmtFeePerSecond) external onlyOwner {
    _store.mgmtFeePerSecond = mgmtFeePerSecond;
    emit MgmtFeePerSecondUpdated(mgmtFeePerSecond);
  }

  /**
    * @notice Update performance fee
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param performanceFee fee in 1e18
  */
  function updatePerformanceFee(uint256 performanceFee) external onlyOwner {
    _store.performanceFee = performanceFee;
    emit PerformanceFeeUpdated(performanceFee);
  }

  /**
    * @notice Update strategy parameter limits and guard checks
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param debtRatioStepThreshold threshold change for debt ratio allowed in 1e4
    * @param debtRatioUpperLimit upper limit of debt ratio in 1e18
    * @param debtRatioLowerLimit lower limit of debt ratio in 1e18
    * @param deltaUpperLimit upper limit of delta in 1e18
    * @param deltaLowerLimit lower limit of delta in 1e18
  */
  function updateParameterLimits(
    uint256 debtRatioStepThreshold,
    uint256 debtRatioUpperLimit,
    uint256 debtRatioLowerLimit,
    int256 deltaUpperLimit,
    int256 deltaLowerLimit
  ) external onlyOwner {
    _store.debtRatioStepThreshold = debtRatioStepThreshold;
    _store.debtRatioUpperLimit = debtRatioUpperLimit;
    _store.debtRatioLowerLimit = debtRatioLowerLimit;
    _store.deltaUpperLimit = deltaUpperLimit;
    _store.deltaLowerLimit = deltaLowerLimit;

    emit ParameterLimitsUpdated(
      debtRatioStepThreshold,
      debtRatioUpperLimit,
      debtRatioLowerLimit,
      deltaUpperLimit,
      deltaLowerLimit
    );
  }

  /**
    * @notice Update minimum slippage
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param minSlippage minimum slippage value in 1e4
  */
  function updateMinSlippage(uint256 minSlippage) external onlyOwner {
    _store.minSlippage = minSlippage;
    emit MinSlippageUpdated(minSlippage);
  }

  /**
    * @notice Update minimum execution fee for GMX
    * @dev Should be called by approved Owner (Timelock + MultiSig)
    * @param minExecutionFee minimum execution fee value in 1e18
  */
  function updateMinExecutionFee(uint256 minExecutionFee) external onlyOwner {
    _store.minExecutionFee = minExecutionFee;
    emit MinExecutionFeeUpdated(minExecutionFee);
  }

  /**
    * @notice Mints vault token shares to user
    * @dev Should only be called by vault
    * @param to Receiver of the minted vault tokens
    * @param amt Amount of minted vault tokens
  */
  function mint(address to, uint256 amt) external onlyVault {
    _mint(to, amt);
  }

  /**
    * @notice Burns vault token shares from user
    * @dev Should only be called by vault
    * @param to Address's vault tokens to burn
    * @param amt Amount of vault tokens to burn
  */
  function burn(address to, uint256 amt) external onlyVault {
    _burn(to, amt);
  }

  /* ================== FALLBACK FUNCTIONS =================== */

  /**
    * @notice Fallback function to receive native token sent to this contract
    * @dev To refund refundee any ETH received from GMX for unused execution fees
  */
  receive() external payable {
    if (msg.sender == _store.depositVault || msg.sender == _store.withdrawalVault) {
      (bool success, ) = _store.refundee.call{value: address(this).balance}("");
      require(success, "Transfer failed.");
    }
  }
}

