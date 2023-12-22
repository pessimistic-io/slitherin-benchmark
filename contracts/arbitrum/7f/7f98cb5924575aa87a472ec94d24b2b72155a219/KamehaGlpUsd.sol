pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import {ILendingPool} from "./IAaveLendingPoolV2.sol";
import "./ISwapRouter.sol";
import "./ERC20.sol";
import "./Ownable.sol";

interface RewardRouterV2 {
  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
  function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
  function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}

interface RewardTracker {
  function claimable(address _account) external view returns (uint256);
}

interface GlpManager {
  function getAumInUsdg(bool maximise) external view returns (uint256);
}

interface AggregatorV3Interface {
  function latestRoundData() external view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

/**
 * Delta Neutral GLP farming strategy
 
    Balance: for $100 of GLP, delta neutral user should be short the other tokens
      Current pool composition:
        - Total $390M
        - USDC+USDT+DAI+FRAX 198 = 50%
        - ETH: $115M ~30%
        - BTC $70M  ~18%
        - LINK 4.5M, UNI 3M   LINK+UNI ~2%
        
    - Cannot perfectly hedge but try to maintain 34% ETH 16%  BTC hedge
    - borrow assets on Aave:
      - deposit USDC
      - borrow ETH
      - swap ETH for GLP
      
      - General function: for source X% in pool, need to hedge X-100 by borrowing in Aave with 66% LTV
      - For Usd, shareAsset = 50%, put 40% directly, 60% in Aave to borrow 40% of assets to hedge: efficiency 80%
      - For Eth, shareAsset = 1/3, put 25% directly, 75% in Aave to borrow 50% of assets to hedge: efficiency 75%
      - For Btc, shareAsset = 1/6, put 13.8% directly, 86.2% in Aave to borrow 57.5% of assets: efficiency 71%
 */
contract KamehaGlpUsd is ERC20, Ownable {

  /// CONSTANTS
  RewardRouterV2 constant GMX_REWARD_ROUTER = RewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
  RewardTracker constant GMX_REWARD_TRACKER = RewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);
  address constant GMX_GLP_MANAGER = 0x321F653eED006AD1C29D174e17d96351BDe22649;
  ERC20 constant STAKED_GLP_TRACKER = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
  
  AggregatorV3Interface constant ETH_ORACLE = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
  AggregatorV3Interface constant USDC_ORACLE = AggregatorV3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
  AggregatorV3Interface constant WBTC_ORACLE = AggregatorV3Interface(0x6ce185860a4963106506C203335A2910413708e9);
  
  
  ILendingPool constant AAVE_LP = ILendingPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
  ISwapRouter constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

  address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
  address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  
  address constant VARDEBT_WETH = 0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351;
  address constant VARDEBT_WBTC = 0x92b42c66840C7AD907b4BF74879FF3eF7c529473;

  /// VARS
  uint public lifetimeRewardsUSD;
  bool public isPaused = false;
  uint public rewardThreshold = 1e16;
  
  address public treasury = 0xC0D7223db9850C87268c178E8b46cea10DbA90E1;
  uint8 public treasuryFee = 0; // fee in percent
  
  /// EVENTS
  event Deposit(address user, uint amount, uint shares);
  event Withdraw(address user, uint amount, uint shares);
  

  constructor() ERC20("Kameha GLP-U", "KGU") {
    ERC20(USDC).approve(address(GMX_GLP_MANAGER), 2**256-1);
    ERC20(WETH).approve(address(GMX_GLP_MANAGER), 2**256-1);
    ERC20(WBTC).approve(address(GMX_GLP_MANAGER), 2**256-1);
    ERC20(USDC).approve(address(AAVE_LP), 2**256-1);
    ERC20(WETH).approve(address(AAVE_LP), 2**256-1);
    ERC20(WBTC).approve(address(AAVE_LP), 2**256-1);
    ERC20(WETH).approve(address(SWAP_ROUTER), 2**256-1);
  }
  
  
  /// @notice Pause/unpause deposits: prevents griefing attack where dust deposit every 15mn prevents withdrawals for 15mn
  function allowDeposits(bool isPaused_) public onlyOwner {
    isPaused = isPaused_;
  }
  /// @notice Change the threshold for claiming+compounding rewards
  function changeRewardThreshold (uint limit) public onlyOwner {
    rewardThreshold = limit;
  }
  
  ///@notice Change treasury address
  function updateTreasury (address treasury_, uint8 treasuryFee_) public onlyOwner {
    treasury = treasury_;
    treasuryFee = treasuryFee_;
  }

  /// @notice User deposits USDC and opens a delta neutral GLP position
  function deposit(uint amount) public {
    require (amount > 0, "Invalid Amount");
    // 0. Compound 
    harvestAndCompound();
    
    // 1. Transfer USDC here
    ERC20(USDC).transferFrom(msg.sender, address(this), amount);
    _mintDeltaNeutralGLP(amount, true);
  }  


    
  /// @notice Use a bunch of USDC to create a delta neutral position.
  /// @param amount Amount of USDC
  /// @param mintTokens True if kamGlp tokens are minted (user depositing USDC), False if compounding rewards
  function _mintDeltaNeutralGLP (uint amount, bool mintTokens) private {
    require(isPaused == false, "Deposits paused");
    
    uint glpBalance = STAKED_GLP_TRACKER.balanceOf(address(this));
    // 1. mint GLP with 40% USDC 
    uint glpAmount = GMX_REWARD_ROUTER.mintAndStakeGlp(USDC, amount * 40 / 100, 0, 1);

    // 2. deposit remaing 60% in Aave
    AAVE_LP.deposit(USDC, amount * 60 / 100, address(this), 0);
    
    // 2. borrow amount*40% worth of ETH+WBTC (Aave LTV 80%, 40/60 ~ 66%), ETH:BTC ratio ~ 2:1, ETH=27% BTC =13%
    // ethamount * ethPrice / ethDecimals = amount * usdcPrice / usdcDecimals
    uint wethAmount = (amount * 27 / 100) * latestUsdcPrice() * 10**12 / latestEthPrice(); // USDC 6 to WETH 18 decimals
    uint wbtcAmount = (amount * 13 / 100) * latestUsdcPrice() * 10**2  / latestWbtcPrice();  // USDC 6 to WBTC 8 decimals
    AAVE_LP.borrow(WETH, wethAmount, 2, 0, address(this));
    AAVE_LP.borrow(WBTC, wbtcAmount, 2, 0, address(this));

    // 3. mint GLP with ETH then with BTC
    glpAmount += GMX_REWARD_ROUTER.mintAndStakeGlp(WBTC, wbtcAmount, 0, 1);
    glpAmount += GMX_REWARD_ROUTER.mintAndStakeGlp(WETH, wethAmount, 0, 1);

    // 4. Mint local token based on GLP minted
    if (mintTokens) {
      uint mintAmount;
      if (glpBalance == 0 || totalSupply() == 0) mintAmount = glpAmount;
      else mintAmount = totalSupply() * glpAmount / glpBalance;
      _mint(msg.sender, mintAmount);
      emit Deposit(msg.sender, amount, mintAmount);
    }
  }
  
  
  /// @notice User redeems some tokens for USDC
  /// @dev Those tokens are burned, and the equivalent underlying GLP amount is redeemed for WETH, which is partly used to repay Aave debt
  function withdraw(uint shares) public {
    require (shares > 0, "Invalid Amount");
    // 0. Dont compound rewards or will reset cooldown
    //harvestAndCompound();
    uint glpBalance = STAKED_GLP_TRACKER.balanceOf(address(this));
    uint shareSupply = totalSupply();
    
    // 1. Withdraw as ETH
    uint redeemedWETH = GMX_REWARD_ROUTER.unstakeAndRedeemGlp(WETH, glpBalance * shares / shareSupply, 1, address(this) );
    
    // 2. Repay Aave ETH+WBTC debt in proportion
    uint debt = ERC20(VARDEBT_WETH).balanceOf(address(this));
    AAVE_LP.repay(WETH, debt * shares / shareSupply, 2, address(this));
    
    // wBTC debt
    debt = ERC20(VARDEBT_WBTC).balanceOf(address(this)) * shares / shareSupply;
    _swapEthForExactWbtc(debt);
    //require( ERC20(WBTC).balanceOf(address(this)) == debt, "Swap not exact?");
    AAVE_LP.repay(WBTC, debt, 2, address(this));
    
    // 3. Withdraw Aave USDC in proportion
    uint usdcAave = ERC20(0x625E7708f30cA75bfd92586e17077590C60eb4cD).balanceOf(address(this)); // aUSDC 0x625E7708f30cA75bfd92586e17077590C60eb4cD
    usdcAave = AAVE_LP.withdraw(USDC, usdcAave * shares / shareSupply, msg.sender);
        
    // 4. There should be an excess WETH: convert, send all USDC remaining to user
    uint uOut = _swapAllWethToUsdc();
    
    // 5. burn
    _burn(msg.sender, shares);
    emit Withdraw(msg.sender, shares, usdcAave + uOut);
  }
  
  
  /// @notice Harvest fees from reward router, then convert all WETH to USDC and compound
  function harvestAndCompound() public {
    // if rewards less than 0.01 Eth just return
    if ( GMX_REWARD_TRACKER.claimable(address(this)) < rewardThreshold ) return;
    
    // 1. get rewards from Reward router
    GMX_REWARD_ROUTER.handleRewards(true, false, true, false, true, true, false); //withdraw all, dont stake, get ETH as WETH
    
    // 2. Send fee to treasury
    if (treasuryFee > 0) ERC20(WETH).transfer(treasury, ERC20(WETH).balanceOf(address(this)) * treasuryFee / 100);
    
    // 3. Swap WETH to USDC then compound
    uint amountOut = _swapAllWethToUsdc();
    if (amountOut > 0){
      lifetimeRewardsUSD += amountOut;
      _mintDeltaNeutralGLP(amountOut, false);
    }
  }
  
  
  /** @notice Rebalance positions
    Adding liquidity to the pool will push back towards the balance, however withdrawing doesn'than
    If the pool HR moves, the GLP is rebalanced and the hedge moves futrher away from the balance
    Worst case when it is too high the Aave position can be liquidated.
    
    In some cases it may be necessary to call for a rebalancing:
      - if HR too high (LTV too low), remove some USDC from Aave and add it to the pool
      - if HR too low (LTV too high), withdraw some GLP and repay some debt, but don't withdraw USDC
      
    Base LTV is 40/60 = 66%, if LTV<62% or LTV>71% allow rebalance
  */
  function rebalance() public returns (uint) {
    (uint collateral, uint debt,,,,) = AAVE_LP.getUserAccountData(address(this));
    // if LTV < 62%, rebalance up
    if (debt * 100 / collateral < 62){
      // simple way not gas efficient: withdraw excess USDC, then add that amount to pool
      uint rebalUsdAmount = collateral - debt * 100 / 66;
      uint rebalUsdc = rebalUsdAmount / 100; // amount is X8 but USDC is X6
      AAVE_LP.withdraw(USDC, rebalUsdc, address(this)); 
      _mintDeltaNeutralGLP(rebalUsdc, false);
      // TODO: gas efficiency, since adding to pool will deposit back some amount, just borrow the difference
    }
    else if ( debt * 100 / collateral > 71 ){
      // withdraw some GLP and repay debt
      uint rebalUsdAmount = debt - collateral * 71 / 100; // amount of debt to repay in USDX8
      uint rebalGlp = rebalUsdAmount * 10**18 / latestGlpPrice();
      uint redeemedWETH = GMX_REWARD_ROUTER.unstakeAndRedeemGlp(WETH, rebalGlp, 1, address(this) );
      _swapExactEthForWbtc(redeemedWETH / 3); // swap a third to BTC

      AAVE_LP.repay(WETH, ERC20(WETH).balanceOf(address(this)), 2, address(this));
      AAVE_LP.repay(WBTC, ERC20(WBTC).balanceOf(address(this)), 2, address(this));
    }
  }
  
  /// @notice Swap all WETH local balance to USDC
  function _swapAllWethToUsdc() private returns (uint amountOut){
    uint amountIn = ERC20(WETH).balanceOf(address(this));
    if (amountIn == 0) return 0;
    ISwapRouter.ExactInputSingleParams memory params =
      ISwapRouter.ExactInputSingleParams({
          tokenIn: WETH,
          tokenOut: USDC,
          fee: 500,
          recipient: msg.sender,
          deadline: block.timestamp,
          amountIn: amountIn,
          amountOutMinimum: amountIn * latestEthPrice() / latestUsdcPrice() * 98 / 100 / 1e12, // tolerable slippage 2%
          sqrtPriceLimitX96: 0
      });
    amountOut = SWAP_ROUTER.exactInputSingle(params);
  }
  
  
  /// @notice Swaps ETH for some BTC
  function _swapEthForExactWbtc(uint amountOut) internal returns (uint amountIn){
    ISwapRouter.ExactOutputSingleParams memory params =
      ISwapRouter.ExactOutputSingleParams({
          tokenIn: WETH,
          tokenOut: WBTC,
          fee: 3000,
          recipient: address(this),
          deadline: block.timestamp,
          amountOut: amountOut,
          amountInMaximum:  amountOut * latestWbtcPrice() / latestEthPrice() * 102 / 100 * 1e10, // tolerable slippage 2
          sqrtPriceLimitX96: 0
      });
    amountIn = SWAP_ROUTER.exactOutputSingle(params);
  }
  
  /// @notice Swaps some ETH for BTC
  function _swapExactEthForWbtc(uint amountIn) internal returns (uint amountOut){
    ISwapRouter.ExactInputSingleParams memory params =
      ISwapRouter.ExactInputSingleParams({
          tokenIn: WETH,
          tokenOut: WBTC,
          fee: 3000,
          recipient: address(this),
          deadline: block.timestamp,
          amountIn: amountIn,
          amountOutMinimum: amountIn * latestEthPrice() / latestWbtcPrice() * 98 / 100 / 1e10, // tolerable slippage 2%
          sqrtPriceLimitX96: 0
      });
    amountOut = SWAP_ROUTER.exactInputSingle(params);
  }
  
  
  /// @notice withdraw stuck tokens other than GLP: GMX, esGMX, ...
  /*function emptyToken (address token) onlyOwner public {
    ERC20(token).transfer( msg.sender, ERC20(token).balanceOf(address(this))  );
  }*/
  
  function latestEthPrice() public view returns (uint priceX8){
    (, int256 price,,,) = ETH_ORACLE.latestRoundData();
    priceX8 = uint(price);
  }
  function latestUsdcPrice() public view returns (uint priceX8){
    (, int256 price,,,) = USDC_ORACLE.latestRoundData();
    priceX8 = uint(price);
  }
  function latestWbtcPrice() public view returns (uint priceX8){
    (, int256 price,,,) = WBTC_ORACLE.latestRoundData();
    priceX8 = uint(price);
  }
  function latestGlpPrice() public view returns (uint priceX8){
    uint aumInUsdg = GlpManager(GMX_GLP_MANAGER).getAumInUsdg(true);
    uint glpBalance = ERC20(STAKED_GLP_TRACKER).totalSupply();
    priceX8 = aumInUsdg * 10**8 / glpBalance;
  }
  function latestPrice() public view returns (uint priceX8){
    uint glpBalance = STAKED_GLP_TRACKER.balanceOf(address(this));
    priceX8 = glpBalance * latestGlpPrice() / 10**10;
  }
}
