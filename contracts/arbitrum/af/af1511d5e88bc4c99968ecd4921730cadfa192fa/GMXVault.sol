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

contract GMXVault is ERC20, Ownable2Step, ReentrancyGuard, Pausable, IGMXVault {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Vault store struct
  GMXTypes.Store internal _store;

  /* ========== MAPPINGS ========== */

  // Approved keepers
  mapping(address => bool) public keepers;
  // Approved tokens for deposit and withdraws
  mapping(address => bool) public tokens;

  /* ========== MODIFIERS ========== */

  /**
    * Allow only vault
  */
  modifier onlyVault() {
    _onlyVault();
    _;
  }

  /**
    * Allow only keeper
  */
  modifier onlyKeeper() {
    _onlyKeeper();
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  /**
    * @dev Initialize store with state variables, configurations and state
    * @param name Name of vault
    * @param symbol Symbol for vault token
    * @param store_ Vault Store struct
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

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * @dev View strategy store data
    * @return GMXTypes.Store struct data
  */
  function store() public view returns (GMXTypes.Store memory) {
    return _store;
  }

  /**
    * @dev Check if token is whitelisted for deposit/withdraw for this vault
    * @param token Address of token to check
    * @return Boolean of whether token is whitelisted
  */
  function isTokenWhitelisted(address token) public view returns (bool) {
    return tokens[token];
  }

  /**
    * @dev Returns the value of each share token; total equity / share token supply
    * @return svTokenValue   Value of each share token in 1e18
  */
  function svTokenValue() public view returns (uint256) {
    return GMXReader.svTokenValue(_store);
  }

  /**
    * @dev Amount of share pending for minting as a form of mgmt fee
    * @return pendingMgmtFee in 1e18
  */
  function pendingMgmtFee() public view returns (uint256) {
    return GMXReader.pendingMgmtFee(_store);
  }

  /**
    * @dev Conversion of equity value to svToken shares
    * @param value Equity value change after deposit in 1e18
    * @param currentEquity Current equity value of vault in 1e18
    * @return sharesAmt Shares amt in 1e18
  */
  function valueToShares(
    uint256 value,
    uint256 currentEquity
  ) public view returns (uint256) {
    return GMXReader.valueToShares(_store, value, currentEquity);
  }

  /**
    * @dev Convert token amount to value using oracle price
    * @param token Token address
    * @param amt Amount of token in token decimals
    @ @return tokenValue Token USD value in 1e18
  */
  function convertToUsdValue(address token, uint256 amt) public view returns (uint256) {
    return GMXReader.convertToUsdValue(_store, token, amt);
  }

  /**
    * @dev Return % weighted value of tokens in LP
    @ @return (tokenAWeight, tokenBWeight) in 1e18; e.g. 50% = 5e17
  */
  function tokenWeights() public view returns (uint256, uint256) {
    return GMXReader.tokenWeights(_store);
  }

  /**
    * @dev Returns the total value of token A & token B assets held by the vault;
    * asset = debt + equity
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValue() public view returns (uint256) {
    return GMXReader.assetValue(_store);
  }

  /**
    * @dev Returns the value of token A & token B debt held by the vault
    * @return debtValue   Value of token A and token B debt in 1e18
  */
  function debtValue() public view returns (uint256, uint256) {
    return GMXReader.debtValue(_store);
  }

  /**
    * @dev Returns the value of token A & token B equity held by the vault;
    * equity = asset - debt
    * @return equityValue   Value of total equity in 1e18
  */
  function equityValue() public view returns (uint256) {
    return GMXReader.equityValue(_store);
  }

  /**
    * @dev Returns the amt of token A & token B assets held by vault
    * @return assetAmt   Amt of token A and token B asset in asset decimals
  */
  function assetAmt() public view returns (uint256, uint256) {
    return GMXReader.assetAmt(_store);
  }

  /**
    * @dev Returns the amt of token A & token B debt held by vault
    * @return debtAmt   Amt of token A and token B debt in token decimals
  */
  function debtAmt() public view returns (uint256, uint256) {
    return GMXReader.debtAmt(_store);
  }

  /**
    * @dev Returns the amt of LP tokens held by vault
    * @return lpAmt   Amt of LP tokens in 1e18
  */
  function lpAmt() public view returns (uint256) {
    return GMXReader.lpAmt(_store);
  }

  /**
    * @dev Returns the current leverage (asset / equity)
    * @return leverage   Current leverage in 1e18
  */
  function leverage() public view returns (uint256) {
    return GMXReader.leverage(_store);
  }

  /**
    * @dev Returns the current delta (tokenA equityValue / vault equityValue)
    * Delta refers to the position exposure of this vault's strategy to the
    * underlying volatile asset. This function assumes that tokenA will always
    * be the non-stablecoin token and tokenB always being the stablecoin
    * The delta can be a negative value
    * @return delta  Current delta (0 = Neutral, > 0 = Long, < 0 = Short) in 1e18
  */
  function delta() public view returns (int256) {
    return GMXReader.delta(_store);
  }

  /**
    * @dev Returns the debt ratio (tokenA and tokenB debtValue) / (total assetValue)
    * When assetValue is 0, we assume the debt ratio to also be 0
    * @return debtRatio   Current debt ratio % in 1e18
  */
  function debtRatio() public view returns (uint256) {
    return GMXReader.debtRatio(_store);
  }

  /**
    * @dev To get additional capacity vault can hold based on lending vault available liquidity
    @ @return additionalCapacity Additional capacity vault can hold based on lending vault available liquidity
  */
  function additionalCapacity() public view returns (uint256) {
    return GMXReader.additionalCapacity(_store);
  }

  /**
    * @dev External function to get soft capacity vault can hold based on lending vault available liquidity and current equity
    @ @return capacity soft capacity of vault
  */
  function capacity() public view returns (uint256) {
    return GMXReader.capacity(_store);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Deposits asset into vault and mint svToken to user
    * @param dp DepositParams struct of deposit parameters
  */
  function deposit(
    GMXTypes.DepositParams memory dp
  ) external payable nonReentrant whenNotPaused {
    GMXDeposit.depositERC20(_store, dp);
  }

  /**
    * @dev  Deposits native asset into vault and mint svToken to user
    * @param dp DepositParams struct of deposit parameters
  */
  function depositNative(
    GMXTypes.DepositParams memory dp
  ) external payable nonReentrant whenNotPaused {
    GMXDeposit.depositNative(_store, dp);
  }

  /**
    * @dev Withdraws asset from vault, burns svToken from user
    * @param wp WithdrawParams struct of withdraw parameters
  */
  function withdraw(
    GMXTypes.WithdrawParams memory wp
  ) external payable nonReentrant whenNotPaused {
    GMXWithdraw.withdraw(_store, wp);
  }

  /**
    * @dev Emergency withdraw function, enabled only when vault is paused, burns svToken from user
    * @param shareAmt Amount of shares to withdraw
  */
  function emergencyWithdraw(uint256 shareAmt) external nonReentrant whenPaused {
    GMXEmergency.emergencyWithdraw(_store, shareAmt);
  }

  /**
    * @dev Minting shares as a form of management fee to treasury address
  */
  function mintMgmtFee() public {
    _mint(_store.treasury, GMXReader.pendingMgmtFee(_store));
    _store.lastFeeCollected = block.timestamp;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Allow only vault
  */
  function _onlyVault() internal view {
    if (msg.sender != address(_store.vault)) revert Errors.OnlyVaultAllowed();
  }

  /**
    * Allow only keeper
  */
  function _onlyKeeper() internal view {
    if (!keepers[msg.sender]) revert Errors.OnlyKeeperAllowed();
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * @dev Mint shares after deposit is executed on GMX
  */
  function processDeposit() external whenNotPaused onlyKeeper {
    GMXDeposit.processDeposit(_store);
  }

  /**
    * @dev Process actions if adding liquidity was cancelled
  */
  function processDepositCancellation() external whenNotPaused onlyKeeper {
    GMXDeposit.processDepositCancellation(_store);
  }

  /**
    * @dev Revert vault status due to after deposit checks failed
    * @notice Called by an approved keeper
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
    * @dev Revert vault status due to after deposit checks failing
    * @notice Should be called by callback
  */
  function processDepositFailureLiquidityWithdrawal() external whenNotPaused onlyKeeper {
    GMXDeposit.processDepositFailureLiquidityWithdrawal(_store);
  }

  /**
    * @dev Repay debt after swap for repay completed, and process swap for withdrawal of assets to user
  */
  function processWithdraw() external whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdraw(_store);
  }

  /**
    * @dev Process actions if adding liquidity was cancelled
  */
  function processWithdrawCancellation() external whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdrawCancellation(_store);
  }

  /**
    * @dev Revert vault status due to after deposit checks failed
    * @notice Called by an approved keeper
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
    * @dev Revert vault status due to after deposit checks failing
    * @notice Should be called by callback
  */
  function processWithdrawFailureLiquidityAdded() external whenNotPaused onlyKeeper {
    GMXWithdraw.processWithdrawFailureLiquidityAdded(_store);
  }

  /**
    * @dev Rebalance vault by adding liquidity, called by keeper
    * @param rap GMXTypes.RebalanceAddParams
  */
  function rebalanceAdd(
    GMXTypes.RebalanceAddParams memory rap
  ) external payable nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.rebalanceAdd(_store, rap);
  }

  /**
    * @dev Process after rebalancing by adding liquidity
    * @notice Called after rebalanceAdd
  */
  function processRebalanceAdd() external nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceAdd(_store);
  }

  /**
    * @dev Process after rebalancing add cancelled due to adding liquidity cancellation
    * @notice Called after rebalanceAdd
  */
  function processRebalanceAddCancellation() external nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceAddCancellation(_store);
  }

  /**
    * @dev Rebalance vault by removing liquidity, called by keeper
    * @param rrp GMXTypes.RebalanceRemoveParams
  */
  function rebalanceRemove(
    GMXTypes.RebalanceRemoveParams memory rrp
  ) external payable nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.rebalanceRemove(_store, rrp);
  }

  /**
    * @dev Process after rebalancing by removing liquidity; checking if swap needed
    * @notice Called by keeper via Event Emitted from GMX
  */
  function processRebalanceRemove() external whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceRemove(_store);
  }

  /**
    * @dev Process after rebalancing remove cancelled due to adding liquidity cancellation
    * @notice Called after rebalanceAdd
  */
  function processRebalanceRemoveCancellation() external nonReentrant whenNotPaused onlyKeeper {
    GMXRebalance.processRebalanceRemoveCancellation(_store);
  }

  /**
    * @dev Compound ERC20 token rewards and convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param cp GMXTypes.CompoundParams
  */
  function compound(GMXTypes.CompoundParams memory cp) external payable whenNotPaused onlyKeeper {
    GMXCompound.compound(_store, cp);
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
  */
  function processCompound() external whenNotPaused onlyKeeper {
    GMXCompound.processCompound(_store);
  }

    /**
    * @dev Process compound cancellation due to adding liquidity cancellation
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
  */
  function processCompoundCancellation() external whenNotPaused onlyKeeper {
    GMXCompound.processCompoundCancellation(_store);
  }

  /**
    * @dev Emergency shut down of vault that withdraws all assets from LP
  */
  function emergencyShutdown() external payable whenNotPaused onlyKeeper {
    _pause();

    GMXEmergency.emergencyShutdown(_store);
  }

  /**
    * @dev Repayment of all debt after emergency shutdown and
    * @notice Closes vault for good, allowing emergency withdrawals
  */
  function emergencyClose() external whenPaused onlyOwner {
    GMXEmergency.emergencyClose(_store);
  }

  /**
    * @dev Emergency resumuption of vault that re-deposits all assets
    * @notice To manually trigger unpause() to resume vault after
  */
  function emergencyResume() external payable whenPaused onlyOwner {
    GMXEmergency.emergencyResume(_store);
  }

  /**
    * @dev Pauses vault, disallowing whenNotPaused actions
  */
  function pause() external whenNotPaused onlyKeeper {
    _pause();
  }

  /**
    * @dev Unpauses vault and set status of vault to Open
  */
  function unpause() external whenPaused onlyOwner {
    _unpause();

    _store.status = GMXTypes.Status.Open;
  }

  /**
    * @dev Approve or revoke address to be a keeper for this vault
    * @param keeper Keeper address
    * @param approval Boolean to approve keeper or not
  */
  function updateKeeper(address keeper, bool approval) external onlyOwner {
    keepers[keeper] = approval;
  }

  /**
    * @dev Update treasury address
    * @param treasury Treasury address
  */
  function updateTreasury(address treasury) external onlyOwner {
    _store.treasury = treasury;
  }

  /**
    * @dev Update swap router address
    * @param swapRouter Swap router address
  */
  function updateSwapRouter(address swapRouter) external onlyOwner {
    _store.swapRouter = ISwap(swapRouter);
  }

  /**
    * @dev Update callback address
    * @param callback Callback address
  */
  function updateCallback(address callback) external onlyOwner {
    _store.callback = callback;
  }

  /**
    * @dev Update management fee per second
    * @param mgmtFeePerSecond management fee per second value in 1e18
  */
  function updateMgmtFeePerSecond(uint256 mgmtFeePerSecond) external onlyOwner {
    _store.mgmtFeePerSecond = mgmtFeePerSecond;
  }

  /**
    * @dev Update performance fee
    * @param performanceFee performance fee value in 1e18
  */
  function updatePerformanceFee(uint256 performanceFee) external onlyOwner {
    _store.performanceFee = performanceFee;
  }

  /**
    * @dev Update invariants
    * @param debtRatioStepThreshold threshold for debtRatio change after deposit/withdraw
    * @param debtRatioUpperLimit upper limit of debt ratio after rebalance; in 1e4; e.g. 6900 = 0.69
    * @param debtRatioLowerLimit lower limit of debt ratio after rebalance; in 1e4; e.g. 6100 = 0.61
    * @param deltaUpperLimit upper limit of delta after rebalance; in 1e4; e.g. 10500 = 1.05
    * @param deltaLowerLimit lower limit of delta after rebalance; in 1e4; e.g. 9500 = 0.95
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
  }

  /**
    * @dev Update minimum slippage
    * @param minSlippage minimum slippage value in 1e2
  */
  function updateMinSlippage(uint256 minSlippage) external onlyOwner {
    _store.minSlippage = minSlippage;
  }

  /**
    * @dev Update minimum execution fee
    * @param minExecutionFee minimum execution fee value in 1e18
  */
  function updateMinExecutionFee(uint256 minExecutionFee) external onlyOwner {
    _store.minExecutionFee = minExecutionFee;
  }

  /**
    * @dev Mints vault tokens
    * @param to Receiver of the minted vault tokens
    * @param amt Amount of minted vault tokens
  */
  function mint(address to, uint256 amt) external onlyVault {
    _mint(to, amt);
  }

  /**
    * @dev Burns vault tokens
    * @param to Address's vault tokens to burn
    * @param amt Amount of vault tokens to burn
  */
  function burn(address to, uint256 amt) external onlyVault {
    _burn(to, amt);
  }

  // TODO to remove
  function resetVault() external onlyOwner {
    _store.WNT.withdraw(address(this).balance);
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    _store.status = GMXTypes.Status.Open;
    delete _store.refundee;
    delete _store.depositCache;
    delete _store.withdrawCache;
    delete _store.rebalanceCache;
    delete _store.compoundCache;


    IERC20(_store.tokenA).safeTransfer(msg.sender, IERC20(_store.tokenA).balanceOf(address(this)));
    IERC20(_store.tokenB).safeTransfer(msg.sender, IERC20(_store.tokenB).balanceOf(address(this)));
    IERC20(_store.lpToken).safeTransfer(msg.sender, IERC20(_store.lpToken).balanceOf(address(this)));
    _store.vault.burn(msg.sender, IERC20(address(_store.vault)).balanceOf(msg.sender));
  }

  /* ========== FALLBACK FUNCTIONS ========== */

  /**
    * Fallback function to receive native token sent to this contract,
  */
  receive() external payable {
    // Refund GMX execution fee to user that last initiated interaction with the vault
    if (msg.sender == _store.depositVault || msg.sender == _store.withdrawalVault) {
      (bool success, ) = _store.refundee.call{value: address(this).balance}("");
      require(success, "Transfer failed.");
    }
  }
}

