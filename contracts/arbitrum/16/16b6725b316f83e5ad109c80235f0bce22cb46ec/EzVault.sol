// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./USDE.sol";
import "./E2LP.sol";
import "./Conversion.sol";
import "./SwapCollector.sol";
import "./IEzVault.sol";
//import "hardhat/console.sol";

contract EzVaultV1 is Initializable,ReentrancyGuardUpgradeable,PausableUpgradeable,ConversionUpgradeable,SwapCollectorUpgradeable,IEzVault{
  struct ChangeData{
    uint16 value;
    uint256 deadLine;
  }
  using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
  //Error message constant
  string internal constant INVALID_TOKEN = "EzVault: Invalid Token";
  string internal constant WRONG_PARAMETER = "EzVault: Wrong Parameter";
  string internal constant WRONG_BUY_TOKEN = "EzVault: Wrong Buy Token";
  string internal constant WRONG_SELL_TOKEN = "EzVault: Wrong Sell Token";
  string internal constant WRONG_AMOUNT = "EzVault: Wrong Amount";
  string internal constant NOT_CONVERT_DOWN = "EzVault: Not Convert Down";
  //Ezio Stablecoin
  USDEV1 private aToken;
  //Ezio 2x Leverage wstETH Index
  E2LPV1 private bToken;
  //Total reserve of reserve token
  uint256 public totalReserve;
  //Unmatched funds
  uint256 public pooledA;
  //Matched funds
  uint256 public matchedA;
  //Interest rate of matched funds per day
  uint16 public rewardRate;
  //Matched funds day interest rate cap
  uint16 public constant MAX_REWARD_RATE = 137 * 30;
  //Daily staking reward for reserveToken
  uint16 public stakeRewardRate;
  //Daily staking reward limit for reserveToken
  uint16 public constant MAX_STAKE_REWARD_RATE = 115 * 30;
  //Denominator of the rate of return
  uint256 public constant REWARD_RATE_DENOMINATOR = 1000000;
  //Timestamp of the last rebase
  uint256 public lastRebaseTime;
  //Denominator of the leverage ratio
  uint256 public constant LEVERAGE_DENOMINATOR = 1000000;
  //Redemption fee rate for aToken
  uint16 public redeemFeeRateA;
  //Upper limit of the redemption fee rate for aToken
  uint16 public constant MAX_REDEEM_FEE_RATE_A = 50 * 30;
  //Redemption fee rate for bToken
  uint16 public redeemFeeRateB;
  //Upper limit of the redemption fee rate for bToken
  uint16 public constant MAX_REDEEM_FEE_RATE_B = 10 * 30;
  //Denominator of the redemption fee rate
  uint256 public constant REDEEM_RATE_DENOMINATOR = 10000;
  //Total income of the ezio foundation
  uint256 public totalCommission;
  //Parameter change waiting list
  mapping(uint8 => ChangeData) public changeList;

  //Subscription event
  event Purchase(address indexed account, TYPE indexed type_, uint256 indexed amt_, uint256 qty_);
  //Redemption event
  event Redeem(address indexed account, TYPE indexed type_, uint256 indexed qty_, uint256 amt_, uint256 commission_, uint256 totalNetWorth_, uint256 totalSupply_);
  //Downward event
  event ConvertDown(uint256 indexed matchedA_, uint256 indexed totalNetWorth_, uint256 indexed time_);
  //Parameter modification event
  event Change(uint8 indexed type_, uint16 indexed value_, uint256 indexed time_);

  modifier detector(uint16 value,uint16 limitValue) {
    require(limitValue >= value, "EzVault: Out Of Limit");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(IERC20MetadataUpgradeable stableToken_,IERC20MetadataUpgradeable reserveToken_,USDEV1 aToken_,E2LPV1 bToken_,uint16 rewardRate_,uint16 redeemFeeRateA_,uint16 redeemFeeRateB_,uint256 lastRebaseTime_) external initializer {
    __AccessControlEnumerable_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __Conversion_init(stableToken_,reserveToken_);
    __SwapCollector_init();
    aToken = aToken_;
    bToken = bToken_;
    rewardRate = rewardRate_;
    lastRebaseTime = lastRebaseTime_;
    redeemFeeRateA = redeemFeeRateA_;
    redeemFeeRateB = redeemFeeRateB_;
    _grantRole(GOVERNOR_ROLE, msg.sender);
    _grantRole(OPERATOR_ROLE, msg.sender);
    _grantRole(0x00, msg.sender);
  }

  /**
  * @notice              Investors purchasing aToken or bToken
  * @param type_         0 represent aToken,1 represent bToken
  * @param channel_      0 represent 0x,1 represent 1inch
  * @param quotes_       Request parameters
  */
  function purchase(TYPE type_,uint8 channel_,bytes[] calldata quotes_) external nonReentrant whenNotPaused{
    require(quotes_.length==1||quotes_.length==2,WRONG_PARAMETER);
    ParsedQuoteData memory parsedQuoteData = parseQuoteData(channel_,quotes_[0]);
    require(parsedQuoteData.sellAmount>0,WRONG_PARAMETER);
    IERC20MetadataUpgradeable token = IERC20MetadataUpgradeable(parsedQuoteData.sellToken);
    token.safeTransferFrom(msg.sender,address(this),parsedQuoteData.sellAmount);
    uint256 stableAmount;
    if(type_==TYPE.A){
      //console.log("start purchase aToken");
      if(parsedQuoteData.sellToken==address(stableToken)){
        stableAmount = parsedQuoteData.sellAmount;
        require(stableAmount>0,WRONG_AMOUNT);
      }else{
        //Trade with an exchange for STABLE_COIN
        require(parsedQuoteData.buyToken==address(stableToken),WRONG_BUY_TOKEN);
        stableAmount = convertAmt(parsedQuoteData.sellToken,address(stableToken),parsedQuoteData.sellAmount);
        require(stableAmount>0,WRONG_AMOUNT);
        require(parsedQuoteData.buyAmount>=stableAmount * 90 /100,WRONG_AMOUNT);
        _swap(channel_,quotes_[0],parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
      }
      //Mining aToken for investors
      uint256 qty = stableAmount * 1e18/ aToken.netWorth();
      //console.log("aToken qty=",qty);
      aToken.mint(msg.sender, qty);
      pooledA += stableAmount;
      emit Purchase(msg.sender,TYPE.A,stableAmount,qty);
    }else if(type_==TYPE.B){
      //console.log("start purchase bToken");
      require(parsedQuoteData.buyToken==address(reserveToken),WRONG_BUY_TOKEN);
      uint256 buyAmount = convertAmt(parsedQuoteData.sellToken,parsedQuoteData.buyToken,parsedQuoteData.sellAmount);
      require(parsedQuoteData.buyAmount>=buyAmount * 90 /100,WRONG_AMOUNT);
      if(parsedQuoteData.sellToken==address(stableToken)){
        stableAmount = parsedQuoteData.sellAmount;
      }else{
        //The amount convert
        stableAmount = convertAmt(parsedQuoteData.sellToken,address(stableToken),parsedQuoteData.sellAmount);
      }
      require(stableAmount>0,WRONG_AMOUNT);
      //console.log("stableAmount=",stableAmount);
      //Mining bToke
      uint256 qty = stableAmount * 1e18/ bToken.netWorth();
      //console.log("bToken qty=",qty);
      bToken.mint(msg.sender, qty);
      //Trading with the exchange using us
      totalReserve += buyAmount;
      _swap(channel_,quotes_[0],parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
      emit Purchase(msg.sender,TYPE.B,stableAmount,qty);
    }else{
      revert(INVALID_TOKEN);
    }
    if(quotes_.length==2){
      require(type_==TYPE.B,WRONG_PARAMETER);
      ParsedQuoteData memory parsedQuoteDataExt = parseQuoteData(channel_,quotes_[1]);
      uint stableAmountExt;
      if(pooledA>stableAmount){
        stableAmountExt = stableAmount;
      }else{
        stableAmountExt = pooledA;
      }
      require(stableAmountExt>0,WRONG_AMOUNT);
      require(parsedQuoteDataExt.sellToken==address(stableToken),WRONG_SELL_TOKEN);
      require(parsedQuoteDataExt.buyToken==address(reserveToken),WRONG_BUY_TOKEN);
      require(parsedQuoteDataExt.sellAmount == stableAmountExt,WRONG_AMOUNT);
      uint256 buyAmount = convertAmt(parsedQuoteData.sellToken,parsedQuoteData.buyToken,parsedQuoteData.sellAmount);
      require(parsedQuoteData.buyAmount>=buyAmount * 90 / 100,WRONG_AMOUNT);
      pooledA -= stableAmountExt;
      matchedA += stableAmountExt;
      //Using reserve funds to trade with the exchange for reserve coins, increasing totalReserve
      totalReserve += buyAmount;
      _swap(channel_,quotes_[1],parsedQuoteDataExt.sellToken,parsedQuoteDataExt.sellAmount);
    }
  }

  /**
  * @notice              Investors redeem aToken or bToken
  * @param type_         0 represent aToken,1 represent bToken
  * @param channel_      0 represent 0x,1 represent 1inch
  * @param qty_          Redemption amount
  * @param token_        The token to be returned
  * @param quote_        Request parameters
  */
  function redeem(TYPE type_,uint8 channel_,uint256 qty_,address token_,bytes calldata quote_) external nonReentrant whenNotPaused{
    require(qty_>0,WRONG_PARAMETER);
    ParsedQuoteData memory parsedQuoteData = parseQuoteData(channel_,quote_);
    if(type_ == TYPE.A){
      require(token_==address(stableToken),WRONG_PARAMETER);
      //The vault transfers STABLE_COIN to the user
      uint256 amt = qty_ * aToken.netWorth() / 1e18 ;
      //Operation of the vault when redeeming
      if(amt <= pooledA){
        //burn aToken
        aToken.burn(msg.sender,qty_);
        pooledA -= amt;
      }else{
        //Sell the reserve tokens for stablecoins and then trade them to the user
        uint256 saleAmount = amt - pooledA;
        uint256 saleQty = saleAmount * 1e18 / getPrice(address(reserveToken));
        require(parsedQuoteData.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
        require(parsedQuoteData.buyToken==address(stableToken),WRONG_BUY_TOKEN);
        require(parsedQuoteData.sellAmount==saleQty,WRONG_AMOUNT);
        uint256 buyAmount = convertAmt(parsedQuoteData.sellToken,parsedQuoteData.buyToken,parsedQuoteData.sellAmount);
        require(parsedQuoteData.buyAmount>=buyAmount * 90 / 100,WRONG_AMOUNT);
        //burn aToken
        aToken.burn(msg.sender,qty_);
        totalReserve -= saleQty;
        matchedA -= saleAmount;
        pooledA -= pooledA;
        _swap(channel_,quote_,parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
      }
      //Calculating transaction fee
      uint256 commission = amt * redeemFeeRateA / REDEEM_RATE_DENOMINATOR;
      totalCommission += commission;
      //Sending USDC
      stableToken.safeTransfer(msg.sender, amt - commission);
      emit Redeem(msg.sender,type_,qty_,amt,commission,aToken.totalNetWorth(),aToken.totalSupply());
    }else if(type_ == TYPE.B){
      uint256 amt = qty_ * bToken.netWorth() / 1e18;
      if(token_==address(stableToken)){
        //Transfer STABLE_TOKEN from vault to user
        uint256 saleQty = totalReserve * qty_ / bToken.totalSupply();
        uint256 saleAmount = saleQty * getPrice(address(reserveToken)) / 1e18;
        require(parsedQuoteData.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
        require(parsedQuoteData.buyToken==address(stableToken),WRONG_BUY_TOKEN);
        require(parsedQuoteData.sellAmount==saleQty,WRONG_AMOUNT);
        uint256 buyAmount = convertAmt(parsedQuoteData.sellToken,parsedQuoteData.buyToken,parsedQuoteData.sellAmount);
        require(parsedQuoteData.buyAmount>=buyAmount * 90 /100,WRONG_AMOUNT);
        //Burn bToken
        bToken.burn(msg.sender,qty_);
        totalReserve -= saleQty;
        pooledA += (saleAmount-amt);
        matchedA -= (saleAmount-amt);
        //Calculating transaction fee
        uint256 commission = amt * redeemFeeRateB / REDEEM_RATE_DENOMINATOR;
        totalCommission += commission;
        _swap(channel_,quote_,parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
        //Sending USDC
        stableToken.safeTransfer(msg.sender, amt - commission);
        emit Redeem(msg.sender,type_,qty_,amt,commission,bToken.totalNetWorth(),bToken.totalSupply());
      }else if(token_==address(reserveToken)){
        //Transfer RESERVE_TOKEN from vault to user
        uint256 redeemReserveQty = totalReserve * qty_ / bToken.totalSupply();
        uint256 transQty = LEVERAGE_DENOMINATOR * redeemReserveQty / leverage();
        uint256 saleQty = (leverage()-LEVERAGE_DENOMINATOR) * redeemReserveQty / leverage();
        if(saleQty>0){
          uint256 saleAmount = saleQty * getPrice(address(reserveToken)) / 1e18;
          require(parsedQuoteData.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
          require(parsedQuoteData.buyToken==address(stableToken),WRONG_BUY_TOKEN);
          require(parsedQuoteData.sellAmount==saleQty,WRONG_AMOUNT);
          uint256 buyAmount = convertAmt(parsedQuoteData.sellToken,parsedQuoteData.buyToken,parsedQuoteData.sellAmount);
          require(parsedQuoteData.buyAmount>=buyAmount * 90 / 100,WRONG_AMOUNT);
          _swap(channel_,quote_,parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
          pooledA += saleAmount;
          matchedA -= saleAmount;
        }
        totalReserve -= redeemReserveQty;
        //Burn bToken
        bToken.burn(msg.sender,qty_);
        //Calculate commission
        uint256 commissionQty = transQty * redeemFeeRateB / REDEEM_RATE_DENOMINATOR;
        uint256 commission = commissionQty * getPrice(address(reserveToken)) / 1e18;
        totalCommission += commission;
        //Sending reserve coin
        reserveToken.safeTransfer(msg.sender, transQty - commissionQty);
        emit Redeem(msg.sender,type_,qty_,amt,commission,bToken.totalNetWorth(),bToken.totalSupply());
      }else{
        revert(INVALID_TOKEN);
      }
    }else{
      revert(INVALID_TOKEN);
    }
  }

  /**
  * @notice               The total reserve net value of the vault = the total reserve amount * the current reserve coin price + pooledA
  * @return uint256       The total reserve net value of the vault
  */
  function totalNetWorth() public view returns(uint256){
    return totalReserve * getPrice(address(reserveToken)) /1e18 + pooledA;
  }

  /**
  * @notice               Dynamic calculation of daily interest
  */
  function _interestRate() internal view returns(uint256){
    return aToken.totalNetWorth()>0?(matchedA * rewardRate) / aToken.totalNetWorth():rewardRate;
  }

  /**
  * @notice               The daily interest rate of aToken (9/10 of the total daily interest rate)
  */
  function interestRate() external view returns(uint256){
    return _interestRate() * 9 / 10;
  }

  /**
  * @notice           Leverage Ratio = aToken Paired Funds / bToken Paired Funds + 1
  * @return uint256   Leverage Ratio of bToken
  */
  function leverage() public view returns(uint256){
    return bToken.totalNetWorth()>0?LEVERAGE_DENOMINATOR*matchedA/bToken.totalNetWorth()+1*LEVERAGE_DENOMINATOR:2000000;
  }

  /**
  * @notice    Check the Paired Funds of bToken, if it is less than 60% of the Paired Funds of aToken, trigger downward rebase
  */
  function check() public view returns(bool) {
    if(bToken.totalNetWorth()<matchedA*3/5){
      //The indication of downward rebase is determined as true
      return true;
    }else{
      return false;
    }
  }

  /**
  * @notice           Get downward rebase price of bToken
  * @return uint256   downward rebase price of bToken
  */
  function convertDownPrice() external view returns(uint256) {
    return bToken.totalSupply()>0?matchedA * 3 * 1e18 / (5 * bToken.totalSupply()):0;
  }

  /**
  * @notice             downward rebase
  * @param channel_     0 represent 0x,1 represent 1inch
  * @param quote_       Request parameters
  */
  function convertDown(uint8 channel_,bytes calldata quote_) external onlyRole(OPERATOR_ROLE) nonReentrant{
    require(check(),NOT_CONVERT_DOWN);
    ParsedQuoteData memory parsedQuoteData = parseQuoteData(channel_,quote_);
    require(parsedQuoteData.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
    require(parsedQuoteData.buyToken==address(stableToken),WRONG_BUY_TOKEN);
    require(totalReserve / 4  == parsedQuoteData.sellAmount,WRONG_PARAMETER);
    uint256 buyAmount = parsedQuoteData.sellAmount * getPrice(address(reserveToken)) / 1e18;
    require(parsedQuoteData.buyAmount>=buyAmount * 90 /100,WRONG_AMOUNT);
    //console.log("buyAmount=",buyAmount);
    totalReserve -= parsedQuoteData.sellAmount;
    matchedA -= buyAmount;
    pooledA += buyAmount;
    _swap(channel_,quote_,parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
    emit ConvertDown(matchedA, totalReserve, block.timestamp);
  }

  /**
  * @notice               rebase,increase in Paired Funds of aToken
  */
  function rebase() external nonReentrant whenNotPaused{
    if(changeList[0].value>0&&block.timestamp>=changeList[0].deadLine){
      rewardRate = changeList[0].value;
      emit Change(0,rewardRate,block.timestamp);
    }
    if(changeList[1].value>0&&block.timestamp>=changeList[1].deadLine){
      redeemFeeRateA = changeList[1].value;
      emit Change(1,redeemFeeRateA,block.timestamp);
    }
    if(changeList[2].value>0&&block.timestamp>=changeList[2].deadLine){
      redeemFeeRateB = changeList[2].value;
      emit Change(2,redeemFeeRateB,block.timestamp);
    }
    if(block.timestamp-lastRebaseTime >= 86400){
      //10% of the total profit of matchedA is taken as the commission for the vault
      uint256 commission = matchedA * rewardRate / (REWARD_RATE_DENOMINATOR * 10);
      //10% of the appreciated portion of wstETH is taken as the commission for the vault
      uint256 stakeCommission = totalReserve * getPrice(address(reserveToken)) * stakeRewardRate / (1e18 * REWARD_RATE_DENOMINATOR * 10);
      totalCommission += (commission + stakeCommission);
      totalReserve -= (commission + stakeCommission) * 1e18 / getPrice(address(reserveToken));
      //90% of the total profit of matchedA is considered as the profit for aToken
      matchedA += matchedA * rewardRate * 9 / (REWARD_RATE_DENOMINATOR * 10);
      lastRebaseTime += 86400;
    }
  }

  /**
  * @notice     Set the daily return rate for pooledA
  */
  function setRewardRate(uint16 rewardRate_,uint256 deadLine_) external detector(rewardRate_,MAX_REWARD_RATE) onlyRole(OPERATOR_ROLE) nonReentrant{
    changeList[0] = ChangeData(rewardRate_, deadLine_);
  }

  /**
  * @notice     Set the daily staking reward for reserveToken
  */
  function setStakeRewardRate(uint16 stakeRewardRate_) external detector(stakeRewardRate_,MAX_STAKE_REWARD_RATE) onlyRole(OPERATOR_ROLE) nonReentrant{
    stakeRewardRate = stakeRewardRate_;
    emit Change(3,stakeRewardRate,block.timestamp);
  }

  /**
  * @notice                     Set the fee rate for redeeming aToken
  * @param redeemFeeRateA_      Fee rate
  */
  function setRedeemFeeRateA(uint16 redeemFeeRateA_,uint256 deadLine_) external detector(redeemFeeRateA_,MAX_REDEEM_FEE_RATE_A) onlyRole(OPERATOR_ROLE) nonReentrant{
    changeList[1] = ChangeData(redeemFeeRateA_, deadLine_);
  }

  /**
  * @notice                     Set the fee rate for redeeming bToken
  * @param redeemFeeRateB_      Fee rate
  */
  function setRedeemFeeRateB(uint16 redeemFeeRateB_,uint256 deadLine_) external detector(redeemFeeRateB_,MAX_REDEEM_FEE_RATE_B) onlyRole(OPERATOR_ROLE) nonReentrant{
    changeList[2] = ChangeData(redeemFeeRateB_, deadLine_);
  }

  /**
  * @notice     Admin withdraws commission
  */
  function withdraw(uint256 amount,uint8 channel_,bytes calldata quote_) external onlyRole(GOVERNOR_ROLE) nonReentrant{
    require(amount<=totalCommission,WRONG_AMOUNT);
    ParsedQuoteData memory parsedQuoteData = parseQuoteData(channel_,quote_);
    uint256 balance = stableToken.balanceOf(address(this));
    uint256 receiveAmount = amount;
    if(amount + pooledA>balance){
      //Exchange reserveToken in the vault for stableToken
      require(parsedQuoteData.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
      require(parsedQuoteData.buyToken==address(stableToken),WRONG_BUY_TOKEN);
      require(parsedQuoteData.sellAmount == amount * 1e18 / getPrice(address(reserveToken)),WRONG_AMOUNT);
      uint256 buyAmount = convertAmt(parsedQuoteData.sellToken,parsedQuoteData.buyToken,parsedQuoteData.sellAmount);
      require(parsedQuoteData.buyAmount>=buyAmount * 90 / 100,WRONG_AMOUNT);
      receiveAmount = _swap(channel_,quote_,parsedQuoteData.sellToken,parsedQuoteData.sellAmount);
    }
    totalCommission -= amount;
    stableToken.safeTransfer(msg.sender, receiveAmount);
  }

  /**
  * @notice             Set the credit limit of the main contract for 0x or 1inch
  * @param token        Token for the credit operation
  * @param channel      0 represent 0x,1 represent 1inch
  * @param amount       Credit limit
  */
  function setApprove(IERC20MetadataUpgradeable token,uint8 channel,uint256 amount) external onlyRole(OPERATOR_ROLE) nonReentrant whenNotPaused{
    if(channel==0){
      token.approve(ZEROEX_ADDRESS, amount);
    }else if(channel==1){
      token.approve(ONEINCH_ADDRESS, amount);
    }else{
      revert(WRONG_PARAMETER);
    }
  }

  /**
  * @notice     Pause the contract
  */
  function pause() external onlyRole(GOVERNOR_ROLE) nonReentrant{
    super._pause();
  }

  /**
* @notice     Unpause the contract
  */
  function unpause() external onlyRole(GOVERNOR_ROLE) nonReentrant{
    super._unpause();
  }

}

