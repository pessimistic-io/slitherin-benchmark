// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./ICamelotOracle.sol";
import "./ILendingPool.sol";
import "./ICamelotVault.sol";
import "./ICamelotManager.sol";
import "./ICamelotRouter.sol";
import "./ICamelotPair.sol";
import "./ICamelotSpNft.sol";
import "./ICamelotXGrail.sol";
import "./ICamelotDividends.sol";
import "./ICamelotNitroPool.sol";
import "./OptimalDeposit.sol";
import "./ManagerAction.sol";

contract CamelotETHUSDCeNeutralManager is Ownable, IERC721Receiver, ICamelotManager {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Router contract
  ICamelotRouter public immutable router;
  // Vault contract
  ICamelotVault public immutable vault;
  // Token A lending pool contract
  ILendingPool public immutable tokenALendingPool;
  // Token B lending pool contract
  ILendingPool public immutable tokenBLendingPool;
  // e.g. WETH
  IERC20 public immutable tokenA;
  // e.g. USDCe
  IERC20 public immutable tokenB;
  // Camelot LP token
  address public immutable lpToken;
  // Camelot SPNFT contract
  address public immutable spNft;
  // SPNFT token ID
  uint256 public positionId;
  // Camelot Oracle contract
  ICamelotOracle public immutable camelotOracle;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant GRAIL = 0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8;
  address public constant xGRAIL = 0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b;
  address public constant USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _lpToken LP token contract
    * @param _tokenALendingPool Token A lending pool contract
    * @param _tokenBLendingPool Token B lending pool contract
    * @param _router Camelot Router contract
    * @param _spNft Camelot SPNFT contract
    * @param _camelotOracle Camelot Oracle contract
  */
  constructor(
    ICamelotVault _vault,
    ILendingPool _tokenALendingPool,
    ILendingPool _tokenBLendingPool,
    ICamelotRouter _router,
    address _lpToken,
    address _spNft,
    ICamelotOracle _camelotOracle
   ) {
    vault = _vault;
    tokenA = IERC20(_vault.tokenA());
    tokenB = IERC20(_vault.tokenB());
    tokenALendingPool = _tokenALendingPool;
    tokenBLendingPool = _tokenBLendingPool;
    router = _router;
    lpToken = _lpToken;
    spNft = _spNft;
    camelotOracle = _camelotOracle;

    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    IERC20(USDCe).approve(address(router), type(uint256).max);
    IERC20(lpToken).approve(address(router), type(uint256).max);
    tokenA.approve(address(tokenALendingPool), type(uint256).max);
    tokenB.approve(address(tokenBLendingPool), type(uint256).max);
    IERC20(lpToken).approve(address(spNft), type(uint256).max);
  }

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
    * Turned intro private function to reduce contract size
  */
  function onlyKeeper() private view {
    require(keepers[msg.sender], "Keeper not approved");
  }

  /* ========== EVENTS ========== */

  event Rebalance(uint256 svTokenValueBefore, uint256 svTokenValueAfter);
  event Compound(address vault);

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * Called by keepers if rebalance conditions are triggered
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _data  WorkData struct
  */
  function rebalance(ManagerAction _action, WorkData calldata _data) external {
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
  function work(ManagerAction _action, WorkData calldata _data) external {
    onlyKeeper();

    // ********** Deposit Flow & Rebalance: Add Liquidity Flow **********
    if (_action == ManagerAction.Deposit || _action == ManagerAction.AddLiquidity ) {
      // borrow from lending pools
      _borrow(_data.borrowTokenAAmt, _data.borrowTokenBAmt);
      // Repay if necessary
      if (_data.repayTokenAAmt > 0 || _data.repayTokenBAmt > 0) {
        // If required Swap tokens to ensure sufficient balance to repay
         _swapForRepay(_data.repayTokenAAmt, _data.repayTokenBAmt);
        // If required, repay lending pools
        _repay(_data.repayTokenAAmt, _data.repayTokenBAmt);
      }
      // Swap assets optimally for LP
      _swapForOptimalDeposit();
      // Add tokens to lp receive lp tokens
      _addLiquidity();
      // Add lp in SPNFT position for rewards
      _stake();
    }

    // ********** Withdraw Flow **********
    if (_action == ManagerAction.Withdraw) {
      if (_data.lpAmt > 0) {
         // Unstake LP from rewards pool
        _unstake(_data.lpAmt);
        // remove lp receive tokenA + B
        _removeLiquidity(lpToken, _data.lpAmt);
        // Swap tokens to ensure sufficient balance to repay
        _swapForRepay(_data.repayTokenAAmt, _data.repayTokenBAmt);
        // repay lending pools
        _repay(_data.repayTokenAAmt, _data.repayTokenBAmt);
        // swap excess tokens
        _swapExcess();
      }
    }

    // ********** Rebalance: Remove Liquidity Flow **********
    if (_action == ManagerAction.RemoveLiquidity) {
      if (_data.lpAmt > 0) {
        // Unstake lp from rewards pool
        _unstake(_data.lpAmt);
        // remove lp receive tokenA + B
        _removeLiquidity(lpToken, _data.lpAmt);
        // If required, borrow from lending pools
        _borrow(_data.borrowTokenAAmt, _data.borrowTokenBAmt);
        // Check for dust amount before swapping to avoid revert
        if (_data.repayTokenAAmt > 0 || _data.repayTokenBAmt > 0) {
          // If required Swap tokens to ensure sufficient balance to repay
          _swapForRepay(_data.repayTokenAAmt, _data.repayTokenBAmt);
          // If required, repay lending pools
          _repay(_data.repayTokenAAmt, _data.repayTokenBAmt);
        }
        // Swap assets optimally for LP
        _swapForOptimalDeposit();
        // Add tokens to lp receive lp tokens
        _addLiquidity();
        // Stake lp in rewards pool
        _stake();
      }
    }

    // Send tokens back to vault, also account for any dust cleanup
    // Long vaults send back tokenA, neutral vaults send back tokenB
    tokenB.safeTransfer(msg.sender, tokenB.balanceOf(address(this)));
  }

  /**
    * Compound rewards, convert to more LP; called by vault or keeper
    * @param _data Bytes, 0 - dividendsPlugin, 1 - reward lpToken address, 2 - reward token address, nitro pool address
    * @notice Pass empty data if no allocation to dividends plugin or nitro pool
  */
  function compound(bytes calldata _data) external {
    onlyKeeper();

    if (_data.length > 0) {
      (
        address dividendsPlugin,
        address[] memory lpTokenRewards,
        address[] memory tokenRewards,
        address nitroPool,
        address[] memory nitroTokenRewards
      ) = abi.decode(_data, (address, address[], address[], address, address[]));

      ICamelotDividends(dividendsPlugin).harvestAllDividends();

      // Convert LP tokens to USDCe; loop to handle possible future multiple LP rewards
      for (uint256 i = 0; i < lpTokenRewards.length; i++) {
        address lpTokenAddress = lpTokenRewards[i];
        if (IERC20(lpTokenAddress).balanceOf(address(this)) > 0) {
          // Approve LP token for router
          IERC20(lpTokenAddress).approve(address(router), IERC20(lpTokenAddress).balanceOf(address(this)));
          // Convert LP tokens to token0 + token1
          _removeLiquidity(lpTokenAddress, IERC20(lpTokenAddress).balanceOf(address(this)));
          // Swap token0 & token1 to USDCe, taking fee
          _swapRewardWithFee(ICamelotPair(lpTokenAddress).token0());
          _swapRewardWithFee(ICamelotPair(lpTokenAddress).token1());
        }
      }

      // Convert ERC20 tokens to USDCe; loop to handle possible future multiple ERC20 token rewards
      for (uint256 i = 0; i < tokenRewards.length; i++) {
        address tokenAddress = tokenRewards[i];
        if (IERC20(tokenAddress).balanceOf(address(this)) > 0) {
          // Swap token to USDCe, taking fee
          _swapRewardWithFee(tokenAddress);
        }
      }

      // if there is a nitro pool with sufficient pending rewards for swaps
      if (nitroPool != address(0)) {
        // harvest rewards
        ICamelotNitroPool(nitroPool).harvest();

        for (uint256 i = 0; i < nitroTokenRewards.length; i++) {
          address nitroTokenAddress = nitroTokenRewards[i];
          if (IERC20(nitroTokenAddress).balanceOf(address(this)) > 0) {
            // Swap token to USDCe, taking fee
            _swapRewardWithFee(nitroTokenAddress);
          }
        }
      }
    }

    // Harvest spNFT rewards receive GRAIL + xGRAIL
    ICamelotSpNft(spNft).harvestPosition(positionId);

    // Convert GRAIL to USDCe
    if (IERC20(GRAIL).balanceOf(address(this)) > 1e10) {
      _swapRewardWithFee(GRAIL);
    }

    // Add liquidity
    _swapForOptimalDeposit();
    _addLiquidity();
    _stake();

    // Note: Balance of xGRAIL will be allocated by keeper
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Internal function to optimally convert token balances to LP tokens
  */
  function _addLiquidity() internal {
    // Add liquidity receive LP tokens
    router.addLiquidity(
      address(tokenA),
      address(tokenB),
      tokenA.balanceOf(address(this)),
      tokenB.balanceOf(address(this)),
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  /**
    * Internal function to withdraw LP tokens
    * @param _lpToken   Address of LP token
    * @param _lpAmt   Amt of lp tokens to withdraw in 1e18
  */
  function _removeLiquidity(address _lpToken, uint256 _lpAmt) internal {
    router.removeLiquidity(
      ICamelotPair(address(_lpToken)).token0(),
      ICamelotPair(address(_lpToken)).token1(),
      _lpAmt,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  /**
    * Internal function to stake LP tokens
  */
  function _stake() internal {
    // Add LP tokens to position (stake)
    ICamelotSpNft(spNft).addToPosition(
      positionId, // spNFT token id
      IERC20(lpToken).balanceOf(address(this)) // amount to add
    );
  }

  /**
    * Internal function to unstake LP tokens
    * @param _lpAmt   Amt of lp tokens to unstake in 1e18
  */
  function _unstake(uint256 _lpAmt) internal {
    ICamelotSpNft(spNft).withdrawFromPosition(
      positionId, // spNFT token id
      _lpAmt // amount to withdraw
    );
  }

  /**
    * Internal function to swap tokens for optimal deposit into LP
  */
  function _swapForOptimalDeposit() internal {
    (uint256 reserveA, uint256 reserveB) = camelotOracle.getLpTokenReserves(
      IERC20(lpToken).totalSupply(),
      address(tokenA),
      address(tokenB),
      lpToken
    );

    (uint16 feeA, uint16 feeB) = camelotOracle.getLpTokenFees(
      address(tokenA),
      address(tokenB),
      lpToken
    );

    // Calculate optimal deposit for token0
    (uint256 optimalSwapAmount, bool isReversed) = OptimalDeposit.optimalDepositTwoFees(
      tokenA.balanceOf(address(this)),
      tokenB.balanceOf(address(this)),
      reserveA,
      reserveB,
      feeA/100,
      feeB/100 // e.g. fee of 0.3% = 3
    );

    address[] memory swapPathForOptimalDeposit = new address[](2);

    if (isReversed) {
      swapPathForOptimalDeposit[0] = address(tokenB);
      swapPathForOptimalDeposit[1] = address(tokenA);
    } else {
      swapPathForOptimalDeposit[0] = address(tokenA);
      swapPathForOptimalDeposit[1] = address(tokenB);
    }

    // Swap tokens to achieve optimal deposit amount
    if (optimalSwapAmount > 0) {
      router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        optimalSwapAmount, // amountIn
        0, // amountOutMin
        swapPathForOptimalDeposit, // path
        address(this), // to
        address(0), // referrer
        block.timestamp // deadline
      );
    }
  }

  /**
    * Internal function to swap tokens A/B to ensure sufficient amount for repaying lending pools
    * @param _repayTokenAAmt    Amt of token A to repay in token decimals
    * @param _repayTokenBAmt    Amt of token B to repay in token decimals
  */
  function _swapForRepay(uint256 _repayTokenAAmt, uint256 _repayTokenBAmt) internal {
    uint256 swapAmountIn;
    uint256 swapAmountOut;
    address[] memory swapPath = new address[](2);

    (uint256 reserveA, uint256 reserveB) = camelotOracle.getLpTokenReserves(
      IERC20(lpToken).totalSupply(),
      address(tokenA),
      address(tokenB),
      lpToken
    );

    (uint16 feeA, uint16 feeB) = camelotOracle.getLpTokenFees(
      address(tokenA),
      address(tokenB),
      lpToken
    );

    if (_repayTokenAAmt > tokenA.balanceOf(address(this))) {
      // if insufficient tokenA, swap B for A
      swapPath[0] = address(tokenB);
      swapPath[1] = address(tokenA);
      unchecked {
        swapAmountOut = _repayTokenAAmt - tokenA.balanceOf(address(this));
      }
      // In: tokenB, Out: tokenA
      swapAmountIn = camelotOracle.getAmountsIn(
        swapAmountOut, // amountOut
        reserveB, // reserveIn
        reserveA, // reserveOut
        feeB // fee paid on token IN
      );
    } else if (_repayTokenBAmt > tokenB.balanceOf(address(this))) {
      // if insufficient tokenB, swap A for B
      swapPath[0] = address(tokenA);
      swapPath[1] = address(tokenB);
      unchecked {
        swapAmountOut = _repayTokenBAmt - tokenB.balanceOf(address(this));
      }
      // In: tokenA, Out: tokenB
      swapAmountIn = camelotOracle.getAmountsIn(
        swapAmountOut, // amountOut
        reserveA, // reserveIn
        reserveB, // reserveOut
        feeA // fee paid on token IN
      );
    }

    if (swapAmountIn > 0) {
      router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        swapAmountIn,
        0,
        swapPath,
        address(this),
        address(0),
        block.timestamp
      );
    }
  }

  /**
    * Internal function to swap excess tokens according to vault strategy.
    * Neutral vault - swap A -> B, Long vault - swap B -> A
  */
  function _swapExcess() internal {
    address[] memory swapPath = new address[](2);

    swapPath[0] = address(tokenA);
    swapPath[1] = address(tokenB);
    try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      tokenA.balanceOf(address(this)),
      0,
      swapPath,
      address(this),
      address(0),
      block.timestamp
    ) {} catch {
      // if swap fails, continue
    }
  }

  /**
    * Internal function to swap reward token for USDCe; take cut of fees and transfer to treasury
    * Then swap remaining USDCe for deposit token
    * @param _rewardToken  Address of reward token
  */
    function _swapRewardWithFee(address _rewardToken) internal {
    if (_rewardToken != USDCe && IERC20(_rewardToken).balanceOf(address(this)) > 1e10) {
      address[] memory swapPath = new address[](2);
      swapPath[0] = address(_rewardToken);
      swapPath[1] = USDCe;

      IERC20(_rewardToken).approve(address(router), type(uint256).max);

      // Swap reward token to USDCe
      router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        IERC20(_rewardToken).balanceOf(address(this)),
        0,
        swapPath,
        address(this),
        address(0),
        block.timestamp
      );

      uint256 fee = IERC20(USDCe).balanceOf(address(this))
                  * vault.getVaultConfig().perfFee
                  / SAFE_MULTIPLIER;

      IERC20(USDCe).safeTransfer(vault.treasury(), fee);
    }
  }

  /**
    * Internal function to borrow from lending pools
    * @param _borrowTokenAAmt   Amt of token A to borrow in token decimals
    * @param _borrowTokenBAmt   Amt of token B to borrow in token decimals
  */
  function _borrow(uint256 _borrowTokenAAmt, uint256 _borrowTokenBAmt) internal {
    if (_borrowTokenAAmt > 0) {
      tokenALendingPool.borrow(_borrowTokenAAmt);
    }
    if (_borrowTokenBAmt > 0) {
      tokenBLendingPool.borrow(_borrowTokenBAmt);
    }
  }

  /**
    * Internal function to repay lending pools
    * @param _repayTokenAAmt   Amt of token A to repay in token decimals
    * @param _repayTokenBAmt   Amt of token B to repay in token decimals
  */
  function _repay(uint256 _repayTokenAAmt, uint256 _repayTokenBAmt) internal {
    if (_repayTokenAAmt > 0) {
      tokenALendingPool.repay(_repayTokenAAmt);
    }
    if (_repayTokenBAmt > 0) {
      tokenBLendingPool.repay(_repayTokenBAmt);
    }
  }

  /* ========== INTERFACE FUNCTIONS ========== */

  /**
    * Required to allow contract to receive ERC721 spNFT
  */
  function onERC721Received(
    address /*operator*/,
    address /*from*/,
    uint256 /*tokenId*/,
    bytes memory /*data*/
  ) external pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }

  /**
    * Required by Camelot contracts to handle NFT position
  */
  function onNFTAddToPosition(
    address /*operator*/,
    uint256 /*tokenId*/,
    uint256 /*lpAmount*/
  ) external pure returns (bool) {
    return true;
  }

  /**
    * Required by Camelot contracts to handle NFT position
  */
  function onNFTWithdraw(
    address /*operator*/,
    uint256 /*tokenId*/,
    uint256 /*lpAmount*/
  ) external pure returns (bool) {
    return true;
  }

  /**
    * Required by Camelot contracts to handle NFT position
  */
  function onNFTHarvest(
    address /*operator*/,
    address /*to*/,
    uint256 /*tokenId*/,
    uint256 /*grailAmount*/,
    uint256 /*xGRAILAmount*/
  ) external pure returns (bool) {
    return true;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Update position id of SPNFT
  */
  function updatePositionId(uint256 _id) external onlyOwner {
    positionId = _id;
  }

  /**
    * Allocate xGRAIL to desired plugin
    * @param _action  Action to take 0: allocate; 1: deallocate
    * @param _data  Encoded data for allocation 0: usageAddress, 1: amt of xGRAIL to allocate, 2: usageData
    * @notice usageData: 0: NFT pool address, 1: position id -- only for yield booster, if dividends, leave usageData empty
  */
  function allocate(uint256 _action, bytes calldata _data) external {
    onlyKeeper();

    (
      address usageAddress,
      uint256 amt,
      bytes memory usageData
    ) = abi.decode(_data, (address, uint256, bytes));

    if (_action == 0) {
      ICamelotXGrail(xGRAIL).approveUsage(IXGrailTokenUsage(usageAddress), amt);
      IERC20(xGRAIL).approve(usageAddress, amt);

      ICamelotXGrail(xGRAIL).allocate(usageAddress, amt, usageData);

    } else if (_action == 1) {
      ICamelotXGrail(xGRAIL).deallocate(usageAddress, amt, usageData);
    }
  }

  /**
    * Redeem xGRAIL for Grail after vesting period
    * @param _amt Amt of xGRAIL to redeem
    * @param _redeemDuration Duration of redeem period in seconds
  */
  function redeem(uint256 _amt, uint256 _redeemDuration) external onlyOwner {
    ICamelotXGrail(xGRAIL).redeem(_amt, _redeemDuration);
  }

  /**
    * Finalize redeem after redeem period has ended
    * @param _index Index of redemption position
  */
  function finalizeRedeem(uint256 _index) external onlyOwner {
    ICamelotXGrail(xGRAIL).finalizeRedeem(_index);
  }

  /**
    * Transfer GRAIL to another address
    * @param _to  Address to transfer GRAIL to
    * @param _amt Amt of GRAIL to transfer
  */
  function transferGRAIL(address _to, uint256 _amt) external onlyOwner {
    IERC20(GRAIL).transfer(_to, _amt);
  }

  /**
    * Transfer spNFT to nitro pool
    * @param _to  Nitro pool address to transfer spNFT to
  */
  function transferToNitro(address _to) external onlyOwner {
    IERC721(address(spNft)).safeTransferFrom(address(this), _to, positionId);
  }

  /**
    * Withdraw spNFT from nitro pool
    * @param _from  Nitro pool address to withdraw spNFT from
  */
  function withdrawFromNitro(address _from) external onlyOwner {
    ICamelotNitroPool(_from).withdraw(positionId);
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

