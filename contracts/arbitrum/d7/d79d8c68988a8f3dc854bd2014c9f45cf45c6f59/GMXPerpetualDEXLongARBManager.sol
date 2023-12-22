// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IGMXPerpetualDEXLongVault.sol";
import "./IGMXVault.sol";
import "./IGMXRewardRouterHandler.sol";
import "./IGMXRewardRouter.sol";
import "./IGMXStakePool.sol";
import "./IGMXRewardReader.sol";
import "./IStakedGLP.sol";
import "./ILendingPool.sol";
import "./IGMXOracle.sol";
import "./ManagerAction.sol";

contract GMXPerpetualDEXLongARBManager is Ownable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Vault contract
  IGMXPerpetualDEXLongVault public immutable vault;
  // Deposit token lending pool contract
  ILendingPool public immutable lendingPoolUSDC;
  // GLP Reward router handler
  IGMXRewardRouterHandler public immutable rewardRouterHandler;
  // GLP Reward router
  IGMXRewardRouter public immutable rewardRouter;
  // GLP Stake pool
  IGMXStakePool public immutable stakePool;
  // GMX Oracle
  IGMXOracle public immutable gmxOracle;

  /* ========== STRUCTS ========== */

  struct WorkData {
    address token; // deposit/withdraw token
    uint256 lpAmt; // lp amount to withdraw or add
    uint256 borrowUSDCAmt;
    uint256 repayUSDCAmt;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant GLP = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
  address public constant STAKED_GLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _lendingPoolUSDC lending pool contract
    * @param _rewardRouterHandler GLP Reward router handler
    * @param _rewardRouter GLP Reward router
    * @param _stakePool GLP Stake pool
    * @param _gmxOracle GMX Oracle
    * @param _glpManager GLP manager
  */
  constructor(
    IGMXPerpetualDEXLongVault _vault,
    ILendingPool _lendingPoolUSDC,
    IGMXRewardRouterHandler _rewardRouterHandler,
    IGMXRewardRouter _rewardRouter,
    IGMXStakePool _stakePool,
    IGMXOracle _gmxOracle,
    address _glpManager
  ) {
    vault = _vault;
    lendingPoolUSDC = _lendingPoolUSDC;
    rewardRouterHandler = _rewardRouterHandler;
    rewardRouter = _rewardRouter;
    stakePool = _stakePool;
    gmxOracle = _gmxOracle;

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
    * @return tokenDebtAmt debt amt for each token
  */
  function debtAmt() public view returns (uint256) {
      return lendingPoolUSDC.maxRepay(address(this));
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Called by keepers if rebalance conditions are triggered
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _data WorkData struct
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
      // borrow from lending pool
      _borrow(_data.borrowUSDCAmt);
      // mint GLP
      _addLiquidity(_data);
    }

    // ********** Withdraw Flow **********
    if (_action == ManagerAction.Withdraw) {
      require(_data.lpAmt > 0, "lpAmt is zero");

      if (_data.token != STAKED_GLP) {
        // remove LP receive USDC
        _removeLiquidity(_data);
        // repay lending pool
        _repay(_data.repayUSDCAmt);
        // transfer _data.token to vault for user to withdraw
        IERC20(_data.token).safeTransfer(msg.sender, IERC20(_data.token).balanceOf(address(this)));
      } else if (_data.token == STAKED_GLP) {
        // remove LP receive USDC, calculate remaining glp to withdraw
        uint256 glpToWithdraw = _removeLiquidity(_data);
        // repay lending pool
        _repay(_data.repayUSDCAmt);
        // transfer staked glpToken to vault for user to withdraw
        IStakedGLP(STAKED_GLP).transfer(msg.sender, glpToWithdraw);
      }
    }

    // ********** Rebalance: Remove Liquidity Flow **********
    if (_action == ManagerAction.RemoveLiquidity) {
      require(_data.lpAmt > 0, "lpAmt is zero");
      // remove LP receive borrowToken
      _removeLiquidity(_data);
      // repay lending pool
      _repay(IERC20(USDC).balanceOf(address(this)));
      // add liquidity if any leftover
      _addLiquidity(_data);
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
    * @param _data WorkData struct
  */
  function _addLiquidity(WorkData calldata _data) internal {
    // if _data.token is USDC or STAKED_GLP, mint GLP with USDC deposited and/or borrowed USDC
    if (_data.token == USDC || _data.token == STAKED_GLP) {
      if (IERC20(USDC).balanceOf(address(this)) > 0) {
          rewardRouter.mintAndStakeGlp(
          USDC,
          IERC20(USDC).balanceOf(address(this)),
          0,
          0
        );
      }
    } else if (_data.token == WETH || _data.token == WBTC) {
      if (IERC20(_data.token).balanceOf(address(this)) > 0) {
        // mint GLP with deposited WETH/BTC
        rewardRouter.mintAndStakeGlp(
          _data.token,
          IERC20(_data.token).balanceOf(address(this)),
          0,
          0
        );
        // mint GLP with borrowed USDC
        rewardRouter.mintAndStakeGlp(
          USDC,
          IERC20(USDC).balanceOf(address(this)),
          0,
          0
        );
      }
    }
  }

  /**
    * Internal function to withdraw LP tokens
    * @param _data WorkData struct
    * @return lpAmtLeft Remaining GLP to transfer to user
  */
  function _removeLiquidity(WorkData calldata _data) internal returns (uint256) {
    // unstake all lpAmt in USDC for repaying lending pools and transfer back to user
    if (_data.token == USDC) {
      rewardRouter.unstakeAndRedeemGlp(
        _data.token,
        _data.lpAmt,
        0,
        address(this)
      );
      return 0;

    } else if (_data.token == STAKED_GLP) {
      // unstake only what is necessary to repay usdc debt
      uint256 amtIn = gmxOracle.getGlpAmountIn(_data.repayUSDCAmt, GLP, USDC);
      rewardRouter.unstakeAndRedeemGlp(
        USDC,
        amtIn,
        0,
        address(this)
      );
      return _data.lpAmt - amtIn;

    } else if (_data.token == WETH || _data.token == WBTC) {
      // unstake only what is necessary to repay usdc debt
      uint256 amtIn = gmxOracle.getGlpAmountIn(_data.repayUSDCAmt, GLP, USDC);
      rewardRouter.unstakeAndRedeemGlp(
        USDC,
        amtIn,
        0,
        address(this)
      );
      // unstake remainder in _data.token to transfer back to user
      rewardRouter.unstakeAndRedeemGlp(
        _data.token,
        _data.lpAmt - amtIn,
        0,
        address(this)
      );
      return 0;
    }
    return 0;
  }

  /**
    * Internal function to borrow from lending pools
    * @param _borrowTokenAmt   Amt of deposit token to borrow in token decimals
  */
  function _borrow(uint256 _borrowTokenAmt) internal {
    if (_borrowTokenAmt > 0) {
      lendingPoolUSDC.borrow(_borrowTokenAmt);
    }
  }

  /**
    * Internal function to repay lending pools
    * @param _repayTokenAmt   Amt of deposit token to repay in token decimals
  */
  function _repay(uint256 _repayTokenAmt) internal {
    if (_repayTokenAmt > 0) {
      lendingPoolUSDC.repay(_repayTokenAmt);
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

