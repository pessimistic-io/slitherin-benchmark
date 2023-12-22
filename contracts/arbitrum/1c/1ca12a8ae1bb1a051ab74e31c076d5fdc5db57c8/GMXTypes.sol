// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IWNT } from "./IWNT.sol";
import { ILendingVault } from "./ILendingVault.sol";
import { IGMXVault } from "./IGMXVault.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IGMXOracle } from "./IGMXOracle.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";

library GMXTypes {

  /* ========== STRUCTS ========== */

  struct Store {
    // Target leverage of the vault in 1e18
    uint256 leverage;
    // Delta strategy
    Delta delta;
    // Management fee per second in % in 1e18
    uint256 mgmtFeePerSecond;
    // Performance fee in % in 1e18
    uint256 performanceFee;
    // Max capacity of vault in USD value in 1e18
    uint256 maxCapacity;
    // Treasury address
    address treasury;

    // Invariant: threshold for debtRatio change after deposit/withdraw
    uint256 debtRatioStepThreshold; // in 1e4; e.g. 500 = 5%
    // Invariant: threshold for delta change after deposit/withdraw
    uint256 deltaStepThreshold; // in 1e4; e.g. 500 = 5%
    // Invariant: upper limit of debt ratio after rebalance
    uint256 debtRatioUpperLimit; // in 1e4; e.g. 6900 = 0.69
    // Invariant: lower limit of debt ratio after rebalance
    uint256 debtRatioLowerLimit; // in 1e4; e.g. 6100 = 0.61
    // Invariant: upper limit of delta after rebalance
    int256 deltaUpperLimit; // in 1e4; e.g. 10500 = 1.05
    // Invariant: lower limit of delta after rebalance
    int256 deltaLowerLimit; // in 1e4; e.g. 9500 = 0.95
    // Minimum execution fee required
    uint256 minExecutionFee; // in 1e18

    // Token A in this strategy; long token + index token
    IERC20 tokenA;
    // Token B in this strategy; short token
    IERC20 tokenB;
    // LP token of this strategy; market token
    IERC20 lpToken;
    // Native token for this chain (e.g. WETH, WAVAX, WBNB, etc.)
    IWNT WNT;

    // Token A lending vault
    ILendingVault tokenALendingVault;
    // Token B lending vault
    ILendingVault tokenBLendingVault;

    // Vault address
    IGMXVault vault;
    // Queue contract address; if address(0) it means there is no queue enabled
    address queue;
    // Callback contract address; if address(0) it means there is no callback enabled
    address callback;

    // Chainlink Oracle contract address
    IChainlinkOracle chainlinkOracle;
    // GMX Oracle contract address
    IGMXOracle gmxOracle;

    // GMX exchange router contract address
    IExchangeRouter exchangeRouter;
    // GMX router contract address
    address router;
    // GMX deposit vault address
    address depositVault;
    // GMX withdrawal vault address
    address withdrawalVault;
    // GMX order vault address
    address orderVault;
    // GMX role store address
    address roleStore;

    // Status of the vault
    Status status;

    // Timestamp when vault last collected management fee
    uint256 lastFeeCollected;
    // Timestamp when last user deposit happened
    uint256 lastDepositBlock;

    // Address to refund execution fees to
    address payable refundTo;
    // DepositCache
    DepositCache depositCache;
    // WithdrawCache
    WithdrawCache withdrawCache;
    // RebalanceAddCache
    RebalanceAddCache rebalanceAddCache;
    // RebalanceRemoveCache
    RebalanceRemoveCache rebalanceRemoveCache;
    // CompoundCache
    CompoundCache compoundCache;
  }

  struct DepositCache {
    // Address of user that is depositing
    address payable user;
    // Timestamp of deposit created, filled by vault
    uint256 timestamp;
    // USD value of deposit in 1e18; filled by vault
    uint256 depositValue;
    // Amount of shares to mint in 1e18; filled by vault
    uint256 sharesToUser;
    // Deposit key from GMX in bytes32
    bytes32 depositKey;
    // DepositParams
    DepositParams depositParams;
    // BorrowParams
    BorrowParams borrowParams;
    // HealthParams
    HealthParams healthParams;
  }

  struct WithdrawCache {
    // Address of user that is withdrawing
    address payable user;
    // Timestamp of withdrawal created, filled by vault
    uint256 timestamp;
    // Ratio of shares out of total supply of shares to burn; filled by vault
    uint256 shareRatio;
    // Actual amount of withdraw token that user receives
    uint256 withdrawTokenAmt;
    // Withdraw key from GMX in bytes32
    bytes32 withdrawKey;
    // WithdrawParams
    WithdrawParams withdrawParams;
    // RepayParams
    RepayParams repayParams;
    // HealthParams
    HealthParams healthParams;
  }

  struct RebalanceAddCache {
    // This should be the approved keeper address; filled by vault
    address payable user;
    // Timestamp of deposit created, filled by vault
    uint256 timestamp;
    // Deposit key from GMX in bytes32
    bytes32 depositKey;
    // RebalanceAddParams
    RebalanceAddParams rebalanceAddParams;
    // HealthParams
    HealthParams healthParams;
  }

  struct RebalanceRemoveCache {
    // This should be the approved keeper address; filled by vault
    address payable user;
    // Timestamp of deposit created, filled by vault
    uint256 timestamp;
    // Withdraw key from GMX in bytes32
    bytes32 withdrawKey;
    // Deposit key from GMX in bytes32
    bytes32 depositKey;
    // RebalanceRemoveParams
    RebalanceRemoveParams rebalanceRemoveParams;
    // HealthParams
    HealthParams healthParams;
  }

  struct CompoundCache {
    // This should be the approved keeper address; filled by vault
    address payable user;
    // Timestamp of deposit created, filled by vault
    uint256 timestamp;
    // Deposit key from GMX in bytes32
    bytes32 depositKey;
    // CompoundParams
    CompoundParams compoundParams;
  }

  struct DepositParams {
    // Address of token depositing; can be tokenA, tokenB or lpToken
    address token;
    // Amount of token to deposit in token decimals
    uint256 amt;
    // Minimum amount of shares to receive in 1e18
    uint256 minSharesAmt;
    // Slippage tolerance for adding liquidity; e.g. 3 = 0.03%
    uint256 slippage;
    // TODO Timestamp of deadline
    uint256 deadline;
    // Execution fee sent to GMX for adding liquidity
    uint256 executionFee;
  }

  struct WithdrawParams {
    // Amount of shares to burn in 1e18
    uint256 shareAmt;
    // Address of token to withdraw to; could be tokenA, tokenB or lpToken
    address token;
    // Minimum amount of token to receive in token decimals
    uint256 minWithdrawTokenAmt;
    // Slippage tolerance for removing liquidity; e.g. 3 = 0.03%
    uint256 slippage;
    // TODO Timestamp of deadline
    uint256 deadline;
    // Execution fee sent to GMX for removing liquidity
    uint256 executionFee;
    // Amount of shares to remove in 1e18; filled by vault
    uint256 lpAmtToRemove;
    // SwapParams Swap for repay parameters
    SwapParams swapForRepayParams;
    // SwapParams Swap for withdraw parameters
    SwapParams swapForWithdrawParams;
  }

  struct RebalanceAddParams {
    // DepositParams
    DepositParams depositParams;
    // BorrowParams
    BorrowParams borrowParams;
    // RepayParams
    RepayParams repayParams;
  }

  struct RebalanceRemoveParams {
    // Amount of LP tokens to remove
    uint256 lpAmtToRemove;
    // DepositParams
    DepositParams depositParams;
    // WithdrawParams
    WithdrawParams withdrawParams;
    // BorrowParams
    BorrowParams borrowParams;
    // RepayParams
    RepayParams repayParams;
    // SwapParams Swap for repay parameters
    SwapParams swapForRepayParams;
  }

  struct CompoundParams {
    // SwapParams
    SwapParams swapParams;
    // DepositParams
    DepositParams depositParams;
  }

  struct AddLiquidityParams {
    // Amount of tokenA to add liquidity
    uint256 tokenAAmt;
    // Amount of tokenB to add liquidity
    uint256 tokenBAmt;
    // Slippage tolerance for adding liquidity; e.g. 3 = 0.03%
    uint256 slippage;
    // Execution fee sent to GMX for adding liquidity
    uint256 executionFee;
  }

  struct RemoveLiquidityParams {
    // Amount of lpToken to remove liquidity
    uint256 lpTokenAmt;
    // Slippage tolerance for removing liquidity; e.g. 3 = 0.03%
    uint256 slippage;
    // Execution fee sent to GMX for removing liquidity
    uint256 executionFee;
  }

  struct BorrowParams {
    // Amount of tokenA to borrow in tokenA decimals
    uint256 borrowTokenAAmt;
    // Amount of tokenB to borrow in tokenB decimals
    uint256 borrowTokenBAmt;
  }

  struct RepayParams {
    // Amount of tokenA to repay in tokenA decimals
    uint256 repayTokenAAmt;
    // Amount of tokenB to repay in tokenB decimals
    uint256 repayTokenBAmt;
  }

  struct SwapParams {
    // Address of token swapping from; filled by vault
    address tokenFrom;
    // Address of token swapping to; filled by vault
    address tokenTo;
    // Amount of token swapping from; filled by vault
    uint256 tokenFromAmt;
    // Slippage tolerance swap; e.g. 3 = 0.03%
    uint256 slippage;
    // TODO Timestamp of deadline
    uint256 deadline;
    // Execution fee sent to GMX for swap orders
    uint256 executionFee;
    // Order key from GMX in bytes32
    bytes32 orderKey;
  }

  struct HealthParams {
    // USD value of equity in 1e18
    uint256 equityBefore;
    // Debt ratio in 1e18
    uint256 debtRatioBefore;
    // Delta in 1e18
    int256 deltaBefore;
    // LP token balance in 1e18
    uint256 lpAmtBefore;
    // Debt amount of tokenA in token decimals
    uint256 debtAmtTokenABefore;
    // Debt amount of tokenB in token decimals
    uint256 debtAmtTokenBBefore;
    // USD value of equity in 1e18
    uint256 equityAfter;
    // svToken value before in 1e18
    uint256 svTokenValueBefore;
    // // svToken value after in 1e18
    uint256 svTokenValueAfter;
  }

  /* ========== ENUM ========== */

  enum Status {
    // Vault is not open for any action
    Closed,
    // Vault is open for deposit/withdraw/rebalance
    Open,
    // User is depositing assets
    Deposit,
    // Vault is borrowing assets
    Borrow,
    // Vault is swapping for adding liquidity; note: unused
    Swap_For_Add,
    // Vault is adding liquidity
    Add_Liquidity,
    // Vault is minting shares
    Mint,
    // Vault is staking LP token; note: unused
    Stake,
    // User is withdrawing assets
    Withdraw,
    // Vault is unstaking LP token; note: unused
    Unstake,
    // Vault is removing liquidity
    Remove_Liquidity,
    // Vault is swapping assets for repayments
    Swap_For_Repay,
    // Vault is repaying assets
    Repay,
    // Vault is swapping assets for withdrawal
    Swap_For_Withdraw,
    // Vault is burning shares
    Burn,
    // Vault is rebalancing by adding more debt
    Rebalance_Add,
    // Vault is borrowing during rebalancing add
    Rebalance_Add_Borrow,
    // Vault is repaying during rebalancing add
    Rebalance_Add_Repay,
    // Vault is swapping for adding liquidity during rebalancing add; note: unused
    Rebalance_Add_Swap_For_Add,
    // Vault is adding liquidity during rebalancing add
    Rebalance_Add_Add_Liquidity,
    // Vault is rebalancing by reducing debt
    Rebalance_Remove,
    // Vault is removing liquidity during rebalancing remove
    Rebalance_Remove_Remove_Liquidity,
    // Vault is borrowing during rebalancing remove
    Rebalance_Remove_Borrow,
    // Vault is swapping for repay during rebalancing remove
    Rebalance_Remove_Swap_For_Repay,
    // Vault is repaying during rebalancing remove
    Rebalance_Remove_Repay,
    // Vault is swapping for adding liquidity during rebalancing remove; note: unused
    Rebalance_Remove_Swap_For_Add,
    // Vault is adding liquidity during rebalancing remove
    Rebalance_Remove_Add_Liquidity,
    // Vault is starting to compound
    Compound,
    // Vault is swapping during compound
    Compound_Swap,
    // Vault is adding liquidity during compound
    Compound_Add_Liquidity,
    // Vault is has added liquidity during compound
    Compound_Liquidity_Added,
    // Vault is performing an emergency shutdown
    Emergency_Shutdown,
    // // Vault is performing an emergency resume
    Emergency_Resume
  }

  enum Delta {
    Neutral,
    Long
  }
}

