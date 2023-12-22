// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IGMXPerpetualDEXNeutralVault.sol";
import "./IGMXVault.sol";
import "./IGMXRewardRouterHandler.sol";
import "./IGMXRewardRouter.sol";
import "./IGMXStakePool.sol";
import "./IGMXRewardReader.sol";
import "./IStakedGLP.sol";
import "./ILendingPool.sol";
import "./IGMXOracle.sol";
import "./ManagerAction.sol";

contract GMXPerpetualDEXNeutralARBManager is Ownable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Vault contract
  IGMXPerpetualDEXNeutralVault public immutable vault;
  // WETH lending pool contract
  ILendingPool public immutable lendingPoolWETH;
  // WBTC lending pool contract
  ILendingPool public immutable lendingPoolWBTC;
  // USDC lending pool contract
  ILendingPool public immutable lendingPoolUSDC;
  // GLP Reward router handler -- for claiming rewards
  IGMXRewardRouterHandler public immutable rewardRouterHandler;
  // GLP Reward router -- for minting GLP
  IGMXRewardRouter public immutable rewardRouter;
  // GLP Stake pool
  IGMXStakePool public immutable stakePool;
  // GMX Oracle
  IGMXOracle public immutable gmxOracle;

  /* ========== STRUCTS ========== */

  struct WorkData {
    address token; // deposit/withdraw token
    uint256 lpAmt; // lp amount to withdraw or add
    uint256 borrowWETHAmt;
    uint256 borrowWBTCAmt;
    uint256 borrowUSDCAmt;
    uint256 repayWETHAmt;
    uint256 repayWBTCAmt;
    uint256 repayUSDCAmt;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant GLP = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
  address public constant fsGLP = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _lendingPoolWETH lending pool contract
    * @param _lendingPoolWBTC lending pool contract
    * @param _lendingPoolUSDC lending pool contract
    * @param _rewardRouterHandler GLP Reward router handler
    * @param _rewardRouter GLP Reward router
    * @param _stakePool GLP Stake pool
    * @param _gmxOracle GMX Oracle
    * @param _glpManager GLP manager
  */
  constructor(
    IGMXPerpetualDEXNeutralVault _vault,
    ILendingPool _lendingPoolWETH,
    ILendingPool _lendingPoolWBTC,
    ILendingPool _lendingPoolUSDC,
    IGMXRewardRouterHandler _rewardRouterHandler,
    IGMXRewardRouter _rewardRouter,
    IGMXStakePool _stakePool,
    IGMXOracle _gmxOracle,
    address _glpManager
  ) {
    vault = _vault;
    lendingPoolWETH = _lendingPoolWETH;
    lendingPoolWBTC = _lendingPoolWBTC;
    lendingPoolUSDC = _lendingPoolUSDC;
    rewardRouterHandler = _rewardRouterHandler;
    rewardRouter = _rewardRouter;
    stakePool = _stakePool;
    gmxOracle = _gmxOracle;

    IERC20(address(WETH)).approve(address(lendingPoolWETH), type(uint256).max);
    IERC20(address(WBTC)).approve(address(lendingPoolWBTC), type(uint256).max);
    IERC20(address(USDC)).approve(address(lendingPoolUSDC), type(uint256).max);
    IERC20(address(WETH)).approve(address(_glpManager), type(uint256).max);
    IERC20(address(WBTC)).approve(address(_glpManager), type(uint256).max);
    IERC20(address(USDC)).approve(address(_glpManager), type(uint256).max);
  }

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

  event Rebalance(uint256 svTokenValueBefore, uint256 svTokenValueAfter);
  event Compound(address vault);
  event UpdateKeeper(address keeper, bool status);

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Return the lp token amount held by manager
    * @return lpAmt amount of lp tokens owned by manager
  */
  function lpAmt() public view returns (uint256) {
    return stakePool.balanceOf(address(this));
  }

  /**
    * Get token debt amt from lending pool
    * @return tokenDebtAmts[] debt amt for each token
  */
  function debtAmts() public view returns (uint256, uint256, uint256) {
    return (
      lendingPoolWETH.maxRepay(address(this)),
      lendingPoolWBTC.maxRepay(address(this)),
      lendingPoolUSDC.maxRepay(address(this))
    );
  }

  /**
    * Get token debt amt from lending pool
    * @param _token address of token
    * @return tokenDebtAmt debt amt of specific token
  */
  function debtAmt(address _token) public view returns (uint256) {
    if (_token == WETH) {
      return lendingPoolWETH.maxRepay(address(this));
    } else if (_token == WBTC) {
      return lendingPoolWBTC.maxRepay(address(this));
    } else if (_token == USDC) {
      return lendingPoolUSDC.maxRepay(address(this));
    } else {
      revert("Invalid token");
    }
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Called by keepers if rebalance conditions are triggered
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _data  WorkData struct
  */
  function rebalance(
    ManagerAction _action,
    WorkData calldata _data
  ) external onlyKeeper {
    vault.mintMgmtFee();

    uint256 svTokenValueBefore = vault.svTokenValue();

    this.work(
      _action,
      _data
    );

    emit Rebalance(svTokenValueBefore, vault.svTokenValue());
  }

  /**
    * General function for deposit, withdraw, rebalance, called by vault
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _data WorkData struct
  */
  function work(
    ManagerAction _action,
    WorkData calldata _data
  ) external onlyKeeper {

    // ********** Deposit Flow && Rebalance: AddLiquidity Flow **********
    if (_action == ManagerAction.Deposit || _action == ManagerAction.AddLiquidity) {
      // borrow from lending pools
      _borrow(_data);
      // add liquidity
      _addLiquidity();
    }

    // ********** Withdraw Flow **********
    if (_action == ManagerAction.Withdraw) {
      require(_data.lpAmt > 0, "lpAmt is zero");
      // remove liquidity, calculate remaining glp to withdraw
      uint256 glpToWithdraw = _removeLiquidity(_data);
      // repay lending pools
      _repay(_data);
      // transfer USDC to vault for user to withdraw
      if (_data.token == USDC) {
        IERC20(USDC).safeTransfer(msg.sender, IERC20(USDC).balanceOf(address(this)));
      } else {
        // transfer GLP to vault for user to withdraw
        IStakedGLP(fsGLP).transfer(msg.sender, glpToWithdraw);
      }
     }

    // ********** Rebalance: Remove Liquidity Flow **********
    if (_action == ManagerAction.RemoveLiquidity) {
      require(_data.lpAmt > 0, "lpAmt is zero");
      // remove LP receive borrowToken
      _removeLiquidity(_data);
      // repay lending pools
      _repay(_data);
      // add liquidity if any leftover
      _addLiquidity();
    }
  }

  /**
    * Compound rewards, convert to more LP; called by vault or keeper
  */
  function compound() external {
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

    if (IERC20(WETH).balanceOf(address(this)) > 0) {
      // Transfer perf fees to treasury as WETH/WAVAX
      uint256 fee = IERC20(WETH).balanceOf(address(this))
                    * vault.vaultConfig().perfFee
                    / SAFE_MULTIPLIER;

      IERC20(WETH).safeTransfer(vault.treasury(), fee);

      // Convert remaining WETH/WAVAX to GLP
      rewardRouter.mintAndStakeGlp(
        address(WETH),
        IERC20(WETH).balanceOf(address(this)),
        0, // minimum acceptable USD value of the GLP purchased
        0 //  minimum acceptable GLP amount
      );

      emit Compound(address(this));
    }
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Internal function to convert token balances to LP tokens
  */
  function _addLiquidity() internal {
    if (IERC20(WETH).balanceOf(address(this)) > 0) {
      rewardRouter.mintAndStakeGlp(
        WETH,
        IERC20(WETH).balanceOf(address(this)),
        0,
        0
      );
    }
    if (IERC20(WBTC).balanceOf(address(this)) > 0) {
      rewardRouter.mintAndStakeGlp(
        WBTC,
        IERC20(WBTC).balanceOf(address(this)),
        0,
        0
      );
    }
    if (IERC20(USDC).balanceOf(address(this)) > 0) {
      rewardRouter.mintAndStakeGlp(
        USDC,
        IERC20(USDC).balanceOf(address(this)),
        0,
        0
      );
    }
  }

  /**
    * Internal function to withdraw LP tokens for multiple tokens
    * @param _data  WorkData struct
    * @return lpAmtLeft Remaining lpAmt to transfer to user
  */
  function _removeLiquidity(WorkData calldata _data) internal returns (uint256) {
    uint256 glpAmtInForWETH;
    uint256 glpAmtInForWBTC;
    // remove lp receive enough WETH for repay
    if (_data.repayWETHAmt > 0) {
      glpAmtInForWETH = gmxOracle.getGlpAmountIn(_data.repayWETHAmt, GLP, WETH);

      rewardRouter.unstakeAndRedeemGlp(
        WETH,
        glpAmtInForWETH,
        0,
        address(this)
      );
    }
    // remove lp receive enough WBTC for repay
    if (_data.repayWBTCAmt > 0) {
      glpAmtInForWBTC = gmxOracle.getGlpAmountIn(_data.repayWBTCAmt, GLP, WBTC);

      rewardRouter.unstakeAndRedeemGlp(
        WBTC,
        glpAmtInForWBTC,
        0,
        address(this)
      );
    }
    // if desired withdraw token is USDC, remove remaining LP receive USDC
    // in rebalance scenario, removing LP to repay USDC debt
    if (_data.token == USDC) {
      rewardRouter.unstakeAndRedeemGlp(
        USDC,
        _data.lpAmt - glpAmtInForWETH - glpAmtInForWBTC,
        0,
        address(this)
      );
      return 0;
    } else {
      // else, desired withdraw token is GLP, remove enough lp receive usdc for repay of usdc debt
      uint256 glpAmtInForUSDC = gmxOracle.getGlpAmountIn((_data.repayUSDCAmt), GLP, USDC);
      rewardRouter.unstakeAndRedeemGlp(
        USDC,
        glpAmtInForUSDC,
        0,
        address(this)
      );
      return (_data.lpAmt - glpAmtInForWETH - glpAmtInForWBTC - glpAmtInForUSDC);
    }
  }

  /**
    * Internal function to borrow from lending pools
    * @param _data   WorkData struct
  */
  function _borrow(WorkData calldata _data) internal {
    if (_data.borrowWETHAmt > 0) {
      lendingPoolWETH.borrow(_data.borrowWETHAmt);
    }
    if (_data.borrowWBTCAmt > 0) {
      lendingPoolWBTC.borrow(_data.borrowWBTCAmt);
    }
    if (_data.borrowUSDCAmt > 0) {
      lendingPoolUSDC.borrow(_data.borrowUSDCAmt);
    }
  }

  /**
    * Internal function to repay lending pools
    * @param _data   WorkData struct
  */
  function _repay(WorkData calldata _data) internal {
    if (_data.repayWETHAmt > 0) {
      lendingPoolWETH.repay(_data.repayWETHAmt);
    }
    if (_data.repayWBTCAmt > 0) {
      lendingPoolWBTC.repay(_data.repayWBTCAmt);
    }
    if (_data.repayUSDCAmt > 0) {
      lendingPoolUSDC.repay(_data.repayUSDCAmt);
    }
  }

  /**
    * Restricted function to transfer esGMX to another account
    * @param _to   Address of account to transfer to
  */
  function transferEsGMX(address _to) external onlyOwner {
    rewardRouterHandler.signalTransfer(_to);
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
}

