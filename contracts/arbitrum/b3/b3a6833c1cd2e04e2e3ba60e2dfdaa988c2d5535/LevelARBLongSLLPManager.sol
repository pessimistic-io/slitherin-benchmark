// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ILiquidityRouter.sol";
import "./ILevelMasterV2.sol";
import "./ILVLStaking.sol";
import "./ILevelARBLongSLLPVault.sol";
import "./ISLLP.sol";
import "./ILendingPool.sol";
import "./ILevelARBOracle.sol";
import "./ManagerAction.sol";
import "./Errors.sol";

contract LevelARBLongSLLPManager is Ownable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Vault contract
  ILevelARBLongSLLPVault public immutable vault;
  // USDT lending pool contract
  ILendingPool public immutable lendingPoolUSDT;
  // Level liquidity router
  ILiquidityRouter public immutable liquidityRouter;
  // SLLP stake pool to earn LVL
  ILevelMasterV2 public immutable sllpStakePool;
  // LVL stake pool to earn SLLP
  ILVLStaking public immutable lvlStakePool;
  // Steadefi deployed Level ARB oracle
  ILevelARBOracle public immutable levelARBOracle;

  /* ========== STRUCTS ========== */

  struct WorkData {
    address token; // deposit/withdraw token
    uint256 lpAmt; // lp amount to withdraw or add
    uint256 borrowUSDTAmt;
    uint256 repayUSDTAmt;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
  address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  address public constant SLLP = 0x5573405636F4b895E511C9C54aAfbefa0E7Ee458;
  address public constant LVL = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _lendingPoolUSDT Lending pool contract
    * @param _liquidityRouter Level liquidity router
    * @param _sllpStakePool SLLP stake pool
    * @param _lvlStakePool LVL stake pool
    * @param _levelARBOracle Steadefi deployed Level ARB oracle
  */
  constructor(
    ILevelARBLongSLLPVault _vault,
    ILendingPool _lendingPoolUSDT,
    ILiquidityRouter _liquidityRouter,
    ILevelMasterV2 _sllpStakePool,
    ILVLStaking _lvlStakePool,
    ILevelARBOracle _levelARBOracle
  ) {
    vault = _vault;
    lendingPoolUSDT = _lendingPoolUSDT;
    liquidityRouter = _liquidityRouter;
    sllpStakePool = _sllpStakePool;
    lvlStakePool = _lvlStakePool;
    levelARBOracle = _levelARBOracle;

    IERC20(address(USDT)).approve(address(lendingPoolUSDT), type(uint256).max);
    IERC20(address(WETH)).approve(address(liquidityRouter), type(uint256).max);
    IERC20(address(WBTC)).approve(address(liquidityRouter), type(uint256).max);
    IERC20(address(USDT)).approve(address(liquidityRouter), type(uint256).max);
    IERC20(address(SLLP)).approve(address(liquidityRouter), type(uint256).max);
    IERC20(address(SLLP)).approve(address(sllpStakePool), type(uint256).max);
    IERC20(address(LVL)).approve(address(lvlStakePool), type(uint256).max);
  }

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
  */
  function onlyKeeper() private view {
    if (!keepers[msg.sender]) revert Errors.OnlyKeeperAllowed();
  }

  /**
    * Only allow approved address of vault
  */
  function onlyVault() private view {
    if (msg.sender != address(vault)) revert Errors.OnlyVaultAllowed();
  }

  /* ========== EVENTS ========== */

  event Rebalance(uint256 svTokenValueBefore, uint256 svTokenValueAfter);
  event Compound(address vault);

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Return the lp token amount held by manager
    * @return lpAmt amount of lp tokens owned by manager
  */
  function lpAmt() public view returns (uint256) {
    // SLLP pool id 0
    (uint256 amt, ) = sllpStakePool.userInfo(0, address(this));
    return amt;
  }

  /**
    * Get token debt amt from lending pool
    * @return tokenDebtAmt debt amt for each token
  */
  function debtAmt() public view returns (uint256) {
    return lendingPoolUSDT.maxRepay(address(this));
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
  ) external {
    onlyKeeper();

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
  ) external {
    onlyKeeper();

    // ********** Deposit Flow && Rebalance: AddLiquidity Flow **********
    if (_action == ManagerAction.Deposit || _action == ManagerAction.AddLiquidity) {
      // borrow from lending pool
      _borrow(_data.borrowUSDTAmt);
      // mint SLLP
      if (_data.token == USDT || _data.token == SLLP) {
        // mint SLLP with USDT deposited and/or borrowed USDT
        _addLiquidity(USDT);
      } else if (_data.token == WETH || _data.token == WBTC) {
        // mint SLLP with deposited WETH/WBTC
        _addLiquidity(_data.token);
        // mint SLLP with borrowed USDT
        _addLiquidity(USDT);
      }
      // Stake SLLP
      _stake(SLLP);
    }

    // ********** Withdraw Flow **********
    if (_action == ManagerAction.Withdraw) {
      if (_data.lpAmt <= 0) revert Errors.EmptyLiquidityProviderAmount();
      // unstake SLLP
      _unstake(SLLP, _data.lpAmt);

      if (_data.token != SLLP) { // USDT, WETH, BNB, BTC
        // remove LP receive USDT
        _removeLiquidity(_data);
        // repay lending pool
        _repay(_data.repayUSDTAmt);
        // transfer _data.token to vault for user to withdraw
        IERC20(_data.token).safeTransfer(msg.sender, IERC20(_data.token).balanceOf(address(this)));
      } else if (_data.token == SLLP) {
        // remove LP receive USDT, calculate remaining SLLP to withdraw
        uint256 sllpToWithdraw = _removeLiquidity(_data);
        // repay lending pool
        _repay(_data.repayUSDTAmt);
        // transfer staked sllpToken to vault for user to withdraw
        ISLLP(SLLP).transfer(msg.sender, sllpToWithdraw);
      }
      // add liquidity if any leftover
      _addLiquidity(USDT);
      // Stake any newly minted SLLP from leftover
      _stake(SLLP);
    }

    // ********** Rebalance: Remove Liquidity Flow **********
    if (_action == ManagerAction.RemoveLiquidity) {
      if (_data.lpAmt <= 0) revert Errors.EmptyLiquidityProviderAmount();
      // unstake LP
      _unstake(SLLP, _data.lpAmt);
      // remove LP receive borrowToken
      _removeLiquidity(_data);
      // repay lending pool
      _repay(IERC20(USDT).balanceOf(address(this)));
      // add liquidity if any leftover
      _addLiquidity(USDT);
      // Stake any newly minted SLLP from leftover
      _stake(SLLP);
    }
  }

  /**
    * Compound rewards, convert to more LP; called by vault or keeper
  */
  function compound() external {
    // Claim LVL rewards; pool id is 0 for SLLP pool
    if (sllpStakePool.pendingReward(0, address(this)) > 0) {
      sllpStakePool.harvest(0, address(this));

      // Stake LVL rewards for more SLLP
      _stake(LVL);
    }

    // Claim SLLP rewards
    uint256 currentLVLEpoch = lvlStakePool.currentEpoch();

    if (lvlStakePool.pendingRewards(currentLVLEpoch, address(this)) > 0) {
      lvlStakePool.claimRewards(currentLVLEpoch, address(this));

      // Transfer performance fees to treasury as SLLP
      uint256 fee = IERC20(SLLP).balanceOf(address(this))
                    * vault.vaultConfig().perfFee
                    / SAFE_MULTIPLIER;

      IERC20(SLLP).safeTransfer(vault.treasury(), fee);

      _stake(SLLP);
    }

    emit Compound(address(this));
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Internal function to convert token balances to LP tokens
    * @param _token Token to convert to LP
  */
  function _addLiquidity(address _token) internal {
    if (IERC20(_token).balanceOf(address(this)) > 0) {
      liquidityRouter.addLiquidity(
        SLLP, // SLLP tranche address
        _token,
        IERC20(_token).balanceOf(address(this)),
        0,
        address(this)
      );
    }
  }

  /**
    * Internal function to withdraw LP tokens
    * @param _data WorkData struct
    * @return lpAmtLeft Remaining SLLP to transfer to user
  */
  function _removeLiquidity(WorkData calldata _data) internal returns (uint256) {
    // unstake all lpAmt in USDT for repaying lending pools and transfer back to user
    if (_data.token == USDT) {
      liquidityRouter.removeLiquidity(
        SLLP, // SLLP tranche address
        USDT,
        _data.lpAmt,
        0,
        address(this)
      );
      return 0;

    } else if (_data.token == WETH || _data.token == WBTC) {
      // unstake only what is necessary to repay USDT debt
      uint256 amtIn = levelARBOracle.getLLPAmountIn(_data.repayUSDTAmt, SLLP, USDT);
      liquidityRouter.removeLiquidity(
        SLLP, // SLLP tranche address
        USDT,
        amtIn,
        0,
        address(this)
      );
      // unstake remainder in _data.token to transfer back to user
      liquidityRouter.removeLiquidity(
        SLLP, // SLLP tranche address
        _data.token,
        _data.lpAmt - amtIn,
        0,
        address(this)
      );
      return 0;

    } else if (_data.token == SLLP) {
      // unstake only what is necessary to repay USDT debt
      uint256 amtIn = levelARBOracle.getLLPAmountIn(_data.repayUSDTAmt, SLLP, USDT);
      liquidityRouter.removeLiquidity(
        SLLP, // SLLP tranche address
        USDT,
        amtIn,
        0,
        address(this)
      );
      // return amt of SLLP to transfer to user
      return _data.lpAmt - amtIn;
    }
    return 0;
  }

  /**
    * Internal function to borrow from lending pools
    * @param _borrowTokenAmt   Amt of deposit token to borrow in token decimals
  */
  function _borrow(uint256 _borrowTokenAmt) internal {
    if (_borrowTokenAmt > 0) {
      lendingPoolUSDT.borrow(_borrowTokenAmt);
    }
  }

  /**
    * Internal function to repay lending pools
    * @param _repayTokenAmt   Amt of deposit token to repay in token decimals
  */
  function _repay(uint256 _repayTokenAmt) internal {
    if (_repayTokenAmt > 0) {
      lendingPoolUSDT.repay(_repayTokenAmt);
    }
  }

  /**
    * Internal function to stake tokens
    * @param _token   Address of token to be staked
  */
  function _stake(address _token) internal {
    // Stake LVL rewards for more SLLP
    if (_token == LVL) {
      if (IERC20(LVL).balanceOf(address(this)) > 0) {
        lvlStakePool.stake(address(this), IERC20(LVL).balanceOf(address(this)));
      }
    }

    // Stake SLLP rewards for more LVL; pool id is 0 for SLLP pool
    if (_token == SLLP) {
      if (IERC20(SLLP).balanceOf(address(this)) > 0) {
        sllpStakePool.deposit(0, IERC20(SLLP).balanceOf(address(this)), address(this));
      }
    }
  }

  /**
    * Internal function to unstake tokens
    * @param _token   Address of token to be unstaked
    * @param _amt   Amt of token to unstake
  */
  function _unstake(address _token, uint256 _amt) internal {
    // Unstake LVL rewards for more SLLP
    if (_token == LVL) {
      lvlStakePool.unstake(address(this), _amt);
    }

    // Unstake SLLP rewards for more LVL; pool id is 0 for SLLP pool
    if (_token == SLLP) {
      sllpStakePool.withdraw(0, _amt, address(this));
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Unstake LVL from stake pool and transfer LVL to owner (manually sell for USDT)
    * only callable when vault is shut down
  */
  function unstakeAndTransferLVL() external {
    onlyVault();

    // Unstake all LVL tokens from LVL stake pool
    uint256 amt = lvlStakePool.stakedAmounts(address(this));

    if (amt > 0) {
      _unstake(LVL, amt);
    }

    IERC20(LVL).safeTransfer(owner(), IERC20(LVL).balanceOf(address(this)));
  }

  /**
    * Approve or revoke address to be a keeper for this vault
    * @param _keeper Keeper address
    * @param _approval Boolean to approve keeper or not
  */
  function updateKeeper(address _keeper, bool _approval) external onlyOwner {
    keepers[_keeper] = _approval;
  }
}

