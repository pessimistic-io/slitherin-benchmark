// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IERC721Receiver.sol";
import "./ICamelotOracle.sol";
import "./ILendingPool.sol";
import "./ICamelotYieldFarmVault.sol";
import "./ICamelotRouter.sol";
import "./ICamelotPair.sol";
import "./ICamelotSpNft.sol";
import "./ICamelotPositionHelper.sol";
import "./ICamelotXGrail.sol";
import "./ICamelotDividends.sol";
import "./OptimalDeposit.sol";
import "./ManagerAction.sol";
import "./VaultStrategy.sol";


contract CamelotYieldFarmManager is Ownable, IERC721Receiver {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Router contract
  ICamelotRouter public immutable router;
  // Vault contract
  ICamelotYieldFarmVault public immutable vault;
  // Token A lending pool contract
  ILendingPool public immutable tokenALendingPool;
  // Token B lending pool contract
  ILendingPool public immutable tokenBLendingPool;
  // e.g. WETH
  IERC20 public immutable tokenA;
  // e.g. USDC
  IERC20 public immutable tokenB;
  // Camelot LP token
  address public immutable lpToken;
  // SPNFT contract
  address public immutable spNft;
  // Camelot position helper contract used to establish spNFT
  address public immutable positionHelper;
  // SPNFT token ID
  uint256 public positionId;
  // Camelot Oracle contract
  ICamelotOracle public immutable camelotOracle;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant GRAIL = 0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8;
  address public constant xGRAIL = 0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b;

  /* ========== EVENTS ========== */

  // event UpdateRouter(address indexed router);

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _lpToken LP token contract
    * @param _tokenALendingPool Token A lending pool contract
    * @param _tokenBLendingPool Token B lending pool contract
    * @param _router Camelot Router contract
    * @param _spNft Camelot SPNFT contract
    * @param _positionHelper Camelot Position helper contract
    * @param _camelotOracle Camelot Oracle contract
  */
  constructor(
    ICamelotYieldFarmVault _vault,
    ILendingPool _tokenALendingPool,
    ILendingPool _tokenBLendingPool,
    ICamelotRouter _router,
    address _lpToken,
    address _spNft,
    address _positionHelper,
    ICamelotOracle _camelotOracle
   ) {
    require(address(_vault) != address(0), "Invalid address");
    require(address(_tokenALendingPool) != address(0), "Invalid address");
    require(address(_tokenBLendingPool) != address(0), "Invalid address");
    require(address(_router) != address(0), "Invalid address");
    require(address(_lpToken) != address(0), "Invalid address");
    require(address(_spNft) != address(0), "Invalid address");
    require(address(_positionHelper) != address(0), "Invalid address");
    require(address(_camelotOracle) != address(0), "Invalid address");

    vault = _vault;
    tokenA = IERC20(_vault.tokenA());
    tokenB = IERC20(_vault.tokenB());
    tokenALendingPool = _tokenALendingPool;
    tokenBLendingPool = _tokenBLendingPool;
    router = _router;
    lpToken = _lpToken;
    spNft = _spNft;
    positionHelper = _positionHelper;
    camelotOracle = _camelotOracle;

    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    tokenA.approve(address(positionHelper), type(uint256).max);
    tokenB.approve(address(positionHelper), type(uint256).max);
    tokenA.approve(address(tokenALendingPool), type(uint256).max);
    tokenB.approve(address(tokenBLendingPool), type(uint256).max);
    IERC20(lpToken).approve(address(spNft), type(uint256).max);
    IERC20(lpToken).approve(address(router), type(uint256).max);
    IERC20(GRAIL).approve(address(router), type(uint256).max);
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
    * @return lpTokenAmt lpToken in 1e18
  */
  function lpTokenAmt() public view returns (uint256) {
    (,uint256 amountWithMultiplier,,,,,,) = ICamelotSpNft(spNft).getStakingPosition(positionId);

    return amountWithMultiplier;
  }

  /**
    * Get token A and B asset amt. Asset = Debt + Equity
    * @return tokenAAssetAmt Token A amt in token decimals
    * @return tokenBAssetAmt Token B amt in token decimals
  */
  function assetInfo() public view returns (uint256, uint256) {
    (uint256 tokenAAssetAmt, uint256 tokenBAssetAmt) = camelotOracle.getLpTokenReserves(
      lpTokenAmt(),
      address(tokenA),
      address(tokenB),
      lpToken
    );

    return (tokenAAssetAmt, tokenBAssetAmt);
  }

  /**
    * Get token A and B debt amt from lending pools
    * @return tokenADebtAmt Token A amt in token decimals
    * @return tokenBDebtAmt Token B amt in token decimals
  */
  function debtInfo() public view returns (uint256, uint256) {
    return (
      tokenALendingPool.maxRepay(address(this)),
      tokenBLendingPool.maxRepay(address(this))
    );
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * General function for deposit, withdraw, rebalance, called by vault
    * @param _action Enum, 0 - Deposit, 1 - Withdraw, 2 - AddLiquidity, 3 - RemoveLiquidity
    * @param _lpAmt Amt of LP tokens to sell for repay
    * @param _borrowTokenAAmt Amt of tokens to borrow in 1e18
    * @param _borrowTokenBAmt Amt of tokens to borrow in 1e18
    * @param _repayTokenAAmt Amt of tokens to repay in 1e18
    * @param _repayTokenBAmt Amt of tokens to repay in 1e18
  */
  function work(
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAAmt,
    uint256 _borrowTokenBAmt,
    uint256 _repayTokenAAmt,
    uint256 _repayTokenBAmt
  ) external onlyVault {

    // ********** Deposit Flow **********
    if (_action == ManagerAction.Deposit) {
      // borrow from lending pools
      _borrow(_borrowTokenAAmt, _borrowTokenBAmt);

      // Swap assets optimally for LP
      _swapForOptimalDeposit();
      // Add tokens to lp receive lp tokens
      _addLiquidity();
      // Add lp in SPNFT position for rewards
      _stake();

      // If position not created, create position; else add lp tokens to position
      // if (positionId == 0) {
      //   // Swap assets optimally for LP
      //   _swapForOptimalDeposit();
      //   // Create SPNFT position
      //   _initPosition();
      // } else {
      //   // Swap assets optimally for LP
      //   _swapForOptimalDeposit();
      //   // Add tokens to lp receive lp tokens
      //   _addLiquidity();
      //   // Add lp in SPNFT position for rewards
      //   _stake();
      // }
    }

    // ********** Withdraw Flow **********
    if (_action == ManagerAction.Withdraw) {
      if (_lpAmt > 0) {
        // If estimated LP amount is more than actual LP amount owned
        if (_lpAmt > lpTokenAmt()) {
          _lpAmt = lpTokenAmt();
        }

        // Unstake LP from rewards pool
        _unstake(_lpAmt);
        // remove lp receive tokenA + B
        _removeLiquidity(lpToken, _lpAmt);
        // Swap tokens to ensure sufficient balance to repay
        _swapForRepay(_repayTokenAAmt, _repayTokenBAmt);
        // repay lending pools
        _repay(_repayTokenAAmt, _repayTokenBAmt);
        // swap excess tokens
        _swapExcess();

      }
    }

    // ********** Rebalance: Add Liquidity Flow **********
    if (_action == ManagerAction.AddLiquidity) {
      // Borrow from lending pools
      _borrow(_borrowTokenAAmt, _borrowTokenBAmt);
      // Check for dust amount before swapping to avoid revert
      if (_repayTokenAAmt > 1e16 || _repayTokenBAmt > 1e5) {
        // If required Swap tokens to ensure sufficient balance to repay
         _swapForRepay(_repayTokenAAmt, _repayTokenBAmt);
        // If required, repay lending pools
        _repay(_repayTokenAAmt, _repayTokenBAmt);
      }
      // Swap assets optimally for LP
      _swapForOptimalDeposit();
      // Add tokens to lp receive lp tokens
      _addLiquidity();
      // Stake lp in rewards pool
      _stake();
    }

    // ********** Rebalance: Remove Liquidity Flow **********
    if (_action == ManagerAction.RemoveLiquidity) {
      if (_lpAmt > 0) {
        // If estimated lp amount is more than actual lp amount owned
        if (_lpAmt > lpTokenAmt()) {
          _lpAmt = lpTokenAmt();
        }
        // Unstake lp from rewards pool
        _unstake(_lpAmt);
        // remove lp receive tokenA + B
        _removeLiquidity(lpToken, _lpAmt);
        // If required, borrow from lending pools
        _borrow(_borrowTokenAAmt, _borrowTokenBAmt);
        // Check for dust amount before swapping to avoid revert
        if (_repayTokenAAmt > 1e16 || _repayTokenBAmt > 1e5) {
          // If required Swap tokens to ensure sufficient balance to repay
          _swapForRepay(_repayTokenAAmt, _repayTokenBAmt);
          // If required, repay lending pools
          _repay(_repayTokenAAmt, _repayTokenBAmt);
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
    tokenA.safeTransfer(msg.sender, tokenA.balanceOf(address(this)));
    tokenB.safeTransfer(msg.sender, tokenB.balanceOf(address(this)));
  }

  /**
    * Compound rewards, convert to more LP; called by vault or keeper
    * @notice Pass empty data if no allocation to dividends plugin
    * @param _data Bytes, 0 - dividendsPlugin, 1 - lpTokenRewards address[]
  */
  function compound(bytes calldata _data) external {
    // Harvest dividends receive WETH-USDC LP tokens + xGRAIL
    if (_data.length > 0) {
      (address dividendsPlugin, address[] memory lpTokenRewards) = abi.decode(_data, (address, address[]));
      ICamelotDividends(dividendsPlugin).harvestAllDividends();

      // Convert LP tokens to tokenB; loop to handle possible future multiple LP rewards
      for (uint256 i = 0; i < lpTokenRewards.length; i++) {
        address lpTokenAddress = lpTokenRewards[i];
        if (IERC20(lpTokenAddress).balanceOf(address(this)) > 0) {
          // Convert LP tokens to token0 + token1
          _removeLiquidity(lpTokenAddress, IERC20(lpTokenAddress).balanceOf(address(this)));
          // Swap token0 & token1 to tokenB (e.g. USDC), taking fee
          _swapRewardWithFee(ICamelotPair(lpTokenAddress).token0());
          _swapRewardWithFee(ICamelotPair(lpTokenAddress).token1());
        }
      }
    }

    // Harvest rewards receive GRAIL + xGRAIL
    ICamelotSpNft(spNft).harvestPosition(positionId);

    // Convert GRAIL to LP tokens
    if (IERC20(GRAIL).balanceOf(address(this)) > 0) {
      _swapRewardWithFee(GRAIL);
      _swapForOptimalDeposit();
      _addLiquidity();
      _stake();
    }

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
    // (uint256 reserveA, uint256 reserveB, uint256 feeA, uint256 feeB) = ICamelotPair(lpToken).getReserves();

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

    // Check if pair is stable swap, cannot use _getAmountsIn for stableswap
    require(!ICamelotPair(lpToken).stableSwap(), 'pair is stable swap');

    // (uint256 reserveA, uint256 reserveB, uint256 feeA, uint256 feeB) = ICamelotPair(lpToken).getReserves();

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
    address[] memory swapPathForRepayDifference = new address[](2);

    if (vault.strategy() == VaultStrategy.Neutral) {
      // TODO: to check?
      if (tokenA.balanceOf(address(this)) > (SAFE_MULTIPLIER / 10)) {
        swapPathForRepayDifference[0] = address(tokenA);
        swapPathForRepayDifference[1] = address(tokenB);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          tokenA.balanceOf(address(this)),
          0,
          swapPathForRepayDifference,
          address(this),
          address(0),
          block.timestamp
        );
      }
    }

    if (vault.strategy() == VaultStrategy.Long) {
      if (tokenB.balanceOf(address(this)) > 0) {
        swapPathForRepayDifference[0] = address(tokenB);
        swapPathForRepayDifference[1] = address(tokenA);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          tokenB.balanceOf(address(this)),
          0,
          swapPathForRepayDifference,
          address(this),
          address(0),
          block.timestamp
        );
      }
    }
  }

  /**
    * Internal function to swap reward token for Token B (USDC); take cut of fees and transfer to treasury
    * TODO: @param _rewardToken ?????
  */
  function _swapRewardWithFee(address _rewardToken) internal {
    address[] memory swapRewardTokenPath = new address[](2);
    swapRewardTokenPath[0] = address(_rewardToken);
    swapRewardTokenPath[1] = address(tokenB);

    // Swap reward token to WETH/USDC
    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      IERC20(_rewardToken).balanceOf(address(this)),
      0,
      swapRewardTokenPath,
      address(this),
      address(0),
      block.timestamp
    );

    uint256 fee = tokenB.balanceOf(address(this))
                  * vault.perfFee()
                  / SAFE_MULTIPLIER;

    tokenB.safeTransfer(vault.treasury(), fee);
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

  /**
    * Internal function to initialize spNFT position
  */
  // function _initPosition() internal {
  //   ICamelotPositionHelper(positionHelper).addLiquidityAndCreatePosition(
  //     address(tokenA),
  //     address(tokenB),
  //     tokenA.balanceOf(address(this)),
  //     tokenB.balanceOf(address(this)),
  //     0,
  //     0,
  //     block.timestamp,
  //     address(this),
  //     INFTPool(address(spNft)),
  //     0
  //   );
  //   // Set position id
  //   positionId = ICamelotSpNft(spNft).tokenOfOwnerByIndex(address(this), 0);
  // }

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
    * @notice usageData: 0: NFT pool address, 1: position id -- only for yield booster, if dividends, leave usageData empty
    * @param _data  Encoded data for allocation 0: usageAddress, 1: amt of xGRAIL to allocate, 2: usageData
  */
  function allocate(bytes calldata _data) external onlyVault {
    (
      address usageAddress,
      uint256 amt,
      bytes memory usageData
    ) = abi.decode(_data, (address, uint256, bytes));

    ICamelotXGrail(xGRAIL).approveUsage(IXGrailTokenUsage(usageAddress), amt);
    IERC20(xGRAIL).approve(usageAddress, amt);

    ICamelotXGrail(xGRAIL).allocate(usageAddress, amt, usageData);
  }

  /**
    * Deallocate xGRAIL from desired plugin
    * @notice usageData: 0: NFT pool address, 1: position id -- only for yield booster, if dividends, leave usageData empty
    * @param _data  Encoded data for deallocation 0: usageAddress, 1: amt of xGRAIL to deallocate, 2: usageData
  */
  function deallocate(bytes calldata _data) external onlyVault {
    (
      address usageAddress,
      uint256 amt,
      bytes memory usageData
    ) = abi.decode(_data, (address, uint256, bytes));

    ICamelotXGrail(xGRAIL).deallocate(usageAddress, amt, usageData);
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
  */
  function finalizeRedeem() external onlyOwner {
    // Get all manager's redeem positions
    uint256 userRedeemLength = ICamelotXGrail(xGRAIL).getUserRedeemsLength(address(this));
    if (userRedeemLength == 0) return;
    // Loop through all redeem positions
    for (uint256 i = 0; i < userRedeemLength; i++) {
      (,,uint256 endTime,,) = ICamelotXGrail(xGRAIL).getUserRedeem(address(this), i);

      // If redeem period has ended finalize redeem claim GRAIL
      if (endTime < block.timestamp) {
        ICamelotXGrail(xGRAIL).finalizeRedeem(i);
      }
    }
  }

  /**
    * Transfer GRAIL to another address
    * @param _to  Address to transfer xGRAIL to
    * @param _amt Amt of xGRAIL to transfer
  */
  function transferGRAIL(address _to, uint256 _amt) external onlyOwner {
    IERC20(GRAIL).transfer(_to, _amt);
  }

  /**
    * Transfer xGRAIL (only if whitelisted) to another address
    * @param _to  Address to transfer xGRAIL to
    * @param _amt Amt of xGRAIL to transfer
  */
  function transferxGRAIL(address _to, uint256 _amt) external onlyOwner {
    IERC20(xGRAIL).transfer(_to, _amt);
  }
}

