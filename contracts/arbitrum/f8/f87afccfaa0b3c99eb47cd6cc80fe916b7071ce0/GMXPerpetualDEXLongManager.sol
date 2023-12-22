// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IGMXPerpetualDEXLongVault.sol";
import "./IGMXVault.sol";
import "./IGMXGLPManager.sol";
import "./IGMXRewardRouterHandler.sol";
import "./IGMXRewardRouter.sol";
import "./IGMXStakePool.sol";
import "./IGMXRewardReader.sol";
import "./ILendingPool.sol";
import "./ManagerAction.sol";

contract GMXPerpetualDEXLongManager is Ownable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Deposit token - USDC
  IERC20 public immutable token;
  // Reward token - WETH/WAVAX for GLP
  IERC20 public immutable rewardToken;
  // Vault contract
  IGMXPerpetualDEXLongVault public immutable vault;
  // Deposit token lending pool contract
  ILendingPool public immutable tokenLendingPool;
  // GLP Reward router handler
  IGMXRewardRouterHandler public immutable rewardRouterHandler;
  // GLP Reward router
  IGMXRewardRouter public immutable rewardRouter;
  // GLP Stake pool
  IGMXStakePool public immutable stakePool;
  // GLP manager
  IGMXGLPManager public immutable glpManager;
  // GLP Reward reader
  IGMXRewardReader public immutable rewardReader;
  // GMX Vault
  IGMXVault public immutable gmxVault;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _tokenLendingPool Deposit token (USDC) lending pool contract
    * @param _rewardRouterHandler GLP Reward router handler
    * @param _rewardRouter GLP Reward router
    * @param _stakePool GLP Stake pool
    * @param _glpManager GLP manager
    * @param _rewardReader GLP Reward reader
    * @param _gmxVault GMX Vault
  */
  constructor(
    IGMXPerpetualDEXLongVault _vault,
    ILendingPool _tokenLendingPool,
    IGMXRewardRouterHandler _rewardRouterHandler,
    IGMXRewardRouter _rewardRouter,
    IGMXStakePool _stakePool,
    IGMXGLPManager _glpManager,
    IGMXRewardReader _rewardReader,
    IGMXVault _gmxVault
  ) {
    require(address(_vault) != address(0), "Invalid address");
    require(address(_tokenLendingPool) != address(0), "Invalid address");
    require(address(_rewardRouterHandler) != address(0), "Invalid address");
    require(address(_rewardRouter) != address(0), "Invalid address");
    require(address(_stakePool) != address(0), "Invalid address");
    require(address(_glpManager) != address(0), "Invalid address");
    require(address(_rewardReader) != address(0), "Invalid address");
    require(address(_gmxVault) != address(0), "Invalid address");

    vault = _vault;
    token = IERC20(vault.token());
    tokenLendingPool = _tokenLendingPool;
    rewardRouterHandler = _rewardRouterHandler;
    rewardRouter = _rewardRouter;
    stakePool = _stakePool;
    glpManager = _glpManager;
    rewardReader = _rewardReader;
    gmxVault = _gmxVault;
    rewardToken = IERC20(rewardRouter.weth());

    IERC20(rewardToken).approve(address(glpManager), type(uint256).max);
    IERC20(address(token)).approve(address(glpManager), type(uint256).max);
    IERC20(address(token)).approve(address(tokenLendingPool), type(uint256).max);
  }

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved address of vault
  */
  modifier onlyVault() {
    require(msg.sender == address(vault), "Caller is not approved vault");
    _;
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Return the lp token amount held by manager
    * @return lpTokenAmt lpToken amount
  */
  function lpTokenAmt() public view returns (uint256) {
    return stakePool.balanceOf(address(this));
  }

  /**
    * Returns the desired token weight
    * @param _token   token's address
    * @return tokenWeight token weight in 1e18
  */
  function currentTokenWeight(address _token) public view returns (uint256) {
    uint256 usdgSupply = getTotalUsdgAmount();

    return gmxVault.usdgAmounts(_token) * SAFE_MULTIPLIER / usdgSupply;
  }

  /**
    * Returns all whitelisted token addresses and current weights
    * @return tokenAddress array of whitelied tokens
    * @return tokenWeight array of token weights in 1e18
  */
  function currentTokenWeights() public view returns (address[] memory, uint256[]memory) {
    uint256 usdgSupply = getTotalUsdgAmount();
    uint256 length = gmxVault.allWhitelistedTokensLength();

    address[] memory tokenAddress = new address[](length);
    uint256[] memory tokenWeight = new uint256[](length);

    address whitelistedToken;
    bool isWhitelisted;

    for (uint256 i = 0; i < length;) {
      whitelistedToken = gmxVault.allWhitelistedTokens(i);
      isWhitelisted = gmxVault.whitelistedTokens(whitelistedToken);
      if (isWhitelisted) {
        tokenAddress[i] = whitelistedToken;
        tokenWeight[i] = gmxVault.usdgAmounts(whitelistedToken)
          * (SAFE_MULTIPLIER)
          / (usdgSupply);
      }
      unchecked { i ++; }
    }

    return (tokenAddress, tokenWeight);
  }

  /**
    * Returns all GLP asset token addresses and current weights
    * @return tokenAddress array of whitelied tokens
    * @return tokenAmt array of token amts
  */
  function assetInfo() public view returns (address[] memory, uint256[] memory) {
    // get manager's glp balance
    uint256 lpTokenBal = lpTokenAmt();
    // get total supply of glp
    uint256 glpTotalSupply = stakePool.totalSupply();
    // get total supply of USDG
    uint256 usdgSupply = getTotalUsdgAmount();

    // calculate manager's glp amt in USDG
    uint256 glpAmtInUsdg = (lpTokenBal * SAFE_MULTIPLIER /
                            glpTotalSupply)
                            * usdgSupply
                            / SAFE_MULTIPLIER;

    uint256 length = gmxVault.allWhitelistedTokensLength();
    address[] memory tokenAddress = new address[](length);
    uint256[] memory tokenAmt = new uint256[](length);

    address whitelistedToken;
    bool isWhitelisted;
    uint256 tokenWeight;

    for (uint256 i = 0; i < length;) {
      // check if token is whitelisted
      whitelistedToken = gmxVault.allWhitelistedTokens(i);
      isWhitelisted = gmxVault.whitelistedTokens(whitelistedToken);
      if (isWhitelisted) {
        tokenAddress[i] = whitelistedToken;
        // calculate token weight expressed in token amt
        tokenWeight = gmxVault.usdgAmounts(whitelistedToken) * SAFE_MULTIPLIER / usdgSupply;
        tokenAmt[i] = (tokenWeight * glpAmtInUsdg / SAFE_MULTIPLIER)
                      * SAFE_MULTIPLIER
                      / (gmxVault.getMinPrice(whitelistedToken) / 1e12);
      }
      unchecked { i ++; }
    }
    return (tokenAddress, tokenAmt);
  }

  /**
    * Get token debt amt from lending pool
    * @return tokenDebtAmt tokenDebtAmt
  */
  function debtInfo() public view returns (uint256) {
      return tokenLendingPool.maxRepay(address(this));
  }

  /**
    * Get total USDG supply
    * @return usdgSupply
  */
  function getTotalUsdgAmount() public view returns (uint256) {
    uint256 length = gmxVault.allWhitelistedTokensLength();
    uint256 usdgSupply;

    address whitelistedToken;
    bool isWhitelisted;

    for (uint256 i = 0; i < length;) {
      whitelistedToken = gmxVault.allWhitelistedTokens(i);
      isWhitelisted = gmxVault.whitelistedTokens(whitelistedToken);
      if (isWhitelisted) {
        usdgSupply += gmxVault.usdgAmounts(whitelistedToken);
      }
      unchecked { i += 1; }
    }
    return usdgSupply;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * General function for deposit, withdraw, rebalance, called by vault
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _lpAmt Amt of LP tokens to sell for repay in 1e18
    * @param _borrowTokenAmt Amt of tokens to borrow in 1e18
    * @param _repayTokenAmt Amt of tokens to repay in 1e18
  */
  function work(
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAmt,
    uint256 _repayTokenAmt
  ) external onlyVault {

    // ********** Deposit Flow && Rebalance: AddLiquidity Flow **********
    if (_action == ManagerAction.Deposit || _action == ManagerAction.AddLiquidity) {
      // borrow from lending pool
      _borrow(_borrowTokenAmt);
      // add tokens to LP receive LP tokens and stake
      _addLiquidity();
    }

    // ********** Withdraw Flow **********
    if (_action == ManagerAction.Withdraw) {
      if (_lpAmt > 0) {
        // If estimated LP amount is more than actual LP amount owned
        if (_lpAmt > lpTokenAmt()) {
          _lpAmt = lpTokenAmt();
        }
        // remove LP receive token
        _removeLiquidity(_lpAmt);
        // repay lending pool
        _repay(_repayTokenAmt);
      }
    }

    // ********** Rebalance: Remove Liquidity Flow **********
    if (_action == ManagerAction.RemoveLiquidity) {
      if (_lpAmt > 0) {
        // If estimated lp amount is more than actual lp amount owned
        if (_lpAmt > lpTokenAmt()) {
          _lpAmt = lpTokenAmt();
        }
        // Unstake lp from rewards pool
        _removeLiquidity(_lpAmt);
        // repay lending pools
        _repay(token.balanceOf(address(this)));
      }
    }

    // Send tokens back to vault, also account for any dust cleanup
    token.safeTransfer(msg.sender, token.balanceOf(address(this)));
  }

  /**
    * Compound rewards, convert to more LP; called by vault or keeper
  */
  function compound(address[] calldata _rewardTrackers) external {
    // check if there are pending rewards to claim
    uint256[] memory res = rewardReader.getStakingInfo(address(this), _rewardTrackers);

    if (res[0] > 0) {
      // Transfer pending ETH/WETH rewards to manager
      rewardRouterHandler.handleRewards(
        false, // should claim GMX
        false, // should stake GMX
        true, // should claim esGMX
        true, // should stake esGMX
        true, // should stake multiplier points
        true, // should claim WETH
        false // should convert WETH to ETH
      );
    }

    // Transfer perf fees to treasury as WETH/WAVAX
    uint256 fee = rewardToken.balanceOf(address(this))
                  * vault.perfFee()
                  / SAFE_MULTIPLIER;

    rewardToken.safeTransfer(vault.treasury(), fee);

    // Convert remaining WETH/WAVAX to GLP
    rewardRouter.mintAndStakeGlp(
      address(rewardToken),
      rewardToken.balanceOf(address(this)),
      0, // minimum acceptable USD value of the GLP purchased
      0 //  minimum acceptable GLP amount
    );
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Internal function to optimally convert token balances to LP tokens
  */
  function _addLiquidity() internal {
    // Add liquidity
    rewardRouter.mintAndStakeGlp(
      address(token),
      token.balanceOf(address(this)),
      0,
      0
    );
  }

  /**
    * Internal function to withdraw LP tokens
    * @param _lpAmt   Amt of lp tokens to withdraw in 1e18
  */
  function _removeLiquidity(uint256 _lpAmt) internal {
    rewardRouter.unstakeAndRedeemGlp(
      address(token),
      _lpAmt,
      0,
      address(this)
    );
  }

  /**
    * Internal function to borrow from lending pools
    * @param _borrowTokenAmt   Amt of deposit token to borrow in token decimals
  */
  function _borrow(uint256 _borrowTokenAmt) internal {
    if (_borrowTokenAmt > 0) {
      tokenLendingPool.borrow(_borrowTokenAmt);
    }
  }

  /**
    * Internal function to repay lending pools
    * @param _repayTokenAmt   Amt of deposit token to repay in token decimals
  */
  function _repay(uint256 _repayTokenAmt) internal {
    if (_repayTokenAmt > 0) {
      tokenLendingPool.repay(_repayTokenAmt);
    }
  }

  /**
    * Restricted function to transfer esGMX to another account
    * @param _destination   Address of account to transfer to
  */
  function transferEsGMX(address _destination) external onlyOwner {
    rewardRouterHandler.signalTransfer(_destination);
  }
}

