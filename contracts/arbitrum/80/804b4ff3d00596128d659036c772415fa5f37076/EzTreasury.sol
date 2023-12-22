// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./USDE.sol";
import "./E2LP.sol";
import "./Conversion.sol";
import "./SwapCollector.sol";
import "./IEzTreasury.sol";
//import "hardhat/console.sol";

contract EzTreasuryV1 is Initializable,ReentrancyGuardUpgradeable,ConversionUpgradeable,SwapCollectorUpgradeable,IEzTreasury{
  struct ChangeData{
    uint16 value;
    uint256 deadLine;
  }
  using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
  //报错信息常量
  string internal constant INVALID_TOKEN = "EzTreasury: Invalid Token";
  string internal constant WRONG_PARAMETER = "EzTreasury: Wrong Parameter";
  string internal constant WRONG_BUY_TOKEN = "EzTreasury: Wrong Buy Token";
  string internal constant WRONG_SELL_TOKEN = "EzTreasury: Wrong Sell Token";
  string internal constant WRONG_AMOUNT = "EzTreasury: Wrong Amount";
  //优先份额合约
  USDEV1 private aToken;
  //进取份额合约
  E2LPV1 private bToken;
  //储备币总储量,购买储备币时会增加,出售储备币时会减少
  uint256 public totalReserve;
  //未配对的aToken资金
  uint256 public pooledA;
  //已配对的aToken资金
  uint256 public matchedA;
  //pooledA每天的回报率
  uint16 public rewardRate;
  //pooledA每天的回报率上限
  uint16 public constant MAX_REWARD_RATE = 137 * 30;
  //reserveToken每天的质押奖励
  uint16 public stakeRewardRate;
  //reserveToken每天的质押奖励上限
  uint16 public constant MAX_STAKE_REWARD_RATE = 115 * 30;
  //回报率的分母
  uint256 public constant REWARD_RATE_DENOMINATOR = 1000000;
  //上次rebase的时间戳
  uint256 public lastRebaseTime;
  //杠杆倍数分母
  uint256 public constant LEVERAGE_DENOMINATOR = 1000000;
  //赎回aToken的手续费费率
  uint16 public redeemFeeRateA;
  //赎回aToken的手续费费率上限
  uint16 public constant MAX_REDEEM_FEE_RATE_A = 50 * 30;
  //赎回bToken的手续费费率
  uint16 public redeemFeeRateB;
  //赎回bToken的手续费费率上限
  uint16 public constant MAX_REDEEM_FEE_RATE_B = 10 * 30;
  //赎回手续费费率的分母
  uint256 public constant REDEEM_RATE_DENOMINATOR = 10000;
  //ezio基金会总收入
  uint256 public totalCommission;
  //参数变更等待列表
  mapping(uint8 => ChangeData) public changeList;

  //申购事件
  event Purchase(address indexed account, TYPE indexed type_, uint256 indexed amt_, uint256 qty_);
  //赎回事件
  event Redeem(address indexed account, TYPE indexed type_, uint256 indexed qty_, uint256 amt_, uint256 commission_, uint256 totalNetWorth_, uint256 totalSupply_);
  //下折事件
  event ConvertDown(uint256 indexed matchedA_, uint256 indexed totalNetWorth_, uint256 indexed time_);
  //修改参数事件
  event Change(uint8 indexed type_, uint16 indexed value_, uint256 indexed time_);

  modifier detector(uint16 value,uint16 limitValue) {
    require(limitValue >= value, "EzTreasury: Out Of Limit");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(IERC20MetadataUpgradeable stableToken_,IERC20MetadataUpgradeable reserveToken_,USDEV1 aToken_,E2LPV1 bToken_,uint16 rewardRate_,uint16 redeemFeeRateA_,uint16 redeemFeeRateB_,uint256 lastRebaseTime_) external initializer {
    __AccessControlEnumerable_init();
    __ReentrancyGuard_init();
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
  * @notice              投资人购买aToken或bToken
  * @param type_         0为aToken,1为bToken
  * @param channel_      0为0x,1为1inch
  * @param quotes_       请求参数
  */
  function purchase(TYPE type_,uint8 channel_,SwapQuote[] calldata quotes_) external nonReentrant{
    require(quotes_.length==1||quotes_.length==2,WRONG_PARAMETER);
    SwapQuote calldata quote_ = quotes_[0];
    require(quote_.sellAmount>0,WRONG_PARAMETER);
    IERC20MetadataUpgradeable token = IERC20MetadataUpgradeable(quote_.sellToken);
    token.safeTransferFrom(msg.sender,address(this),quote_.sellAmount);
    uint256 stableAmount;
    if(type_==TYPE.A){
      //console.log("start purchase aToken");
      if(quote_.sellToken==address(stableToken)){
        stableAmount = quote_.sellAmount;
      }else{
        //跟交易所进行交易换成STABLE_COIN
        require(quote_.buyToken==address(stableToken),WRONG_BUY_TOKEN);
        stableAmount = swap(channel_,quote_);
      }
      require(stableAmount>0,WRONG_AMOUNT);
      //开采aToken给投资者
      uint256 qty = stableAmount * 1e18/ aToken.netWorth();
      //console.log("aToken qty=",qty);
      aToken.mint(msg.sender, qty);
      pooledA += stableAmount;
      emit Purchase(msg.sender,TYPE.A,stableAmount,qty);
    }else if(type_==TYPE.B){
      //console.log("start purchase bToken");
      require(quote_.buyToken==address(reserveToken),WRONG_BUY_TOKEN);
      if(quote_.sellToken==address(stableToken)){
        stableAmount = quote_.sellAmount;
      }else{
        //转化为STABLE_COIN的数量
        stableAmount = convertAmt(quote_.sellToken,address(stableToken),quote_.sellAmount);
      }
      require(stableAmount>0,WRONG_AMOUNT);
      //console.log("stableAmount=",stableAmount);
      //开采bToken给投资者
      uint256 qty = stableAmount * 1e18/ bToken.netWorth();
      //console.log("bToken qty=",qty);
      bToken.mint(msg.sender, qty);
      //使用用户资金跟交易所进行交易换成储备币,totalReserve增加
      uint256 reserveAmountB = swap(channel_,quote_);
      totalReserve += reserveAmountB;
      emit Purchase(msg.sender,TYPE.B,stableAmount,qty);
    }else{
      revert(INVALID_TOKEN);
    }
    if(quotes_.length==2){
      require(type_==TYPE.B,WRONG_PARAMETER);
      SwapQuote calldata quoteExt_ = quotes_[1];
      require(quoteExt_.buyToken==address(reserveToken),WRONG_BUY_TOKEN);
      require(quoteExt_.sellToken==address(stableToken),WRONG_SELL_TOKEN);
      uint stableAmountExt;
      if(pooledA>stableAmount){
        stableAmountExt = stableAmount;
      }else{
        stableAmountExt = pooledA;
      }
      require(stableAmountExt>0,WRONG_AMOUNT);
      pooledA -= stableAmountExt;
      matchedA += stableAmountExt;
      //使用储备资金跟交易所进行交易换成储备币,totalReserve增加
      uint256 reserveAmountA = swap(channel_,quoteExt_);
      totalReserve += reserveAmountA;
    }
  }

  /**
  * @notice              投资人赎回aToken或bToken
  * @param type_         0为aToken,1为bToken
  * @param channel_      0为0x,1为1inch
  * @param qty_          赎回数量
  * @param token_        返还的token
  * @param quote_        请求参数
  */
  function redeem(TYPE type_,uint8 channel_,uint256 qty_,address token_,SwapQuote calldata quote_) external nonReentrant{
    require(qty_>0,WRONG_PARAMETER);
    if(type_ == TYPE.A){
      require(token_==address(stableToken),WRONG_PARAMETER);
      //金库转STABLE_COIN给用户
      uint256 amt = qty_ * aToken.netWorth() / 1e18 ;
      //赎回时金库的操作
      if(amt <= pooledA){
        //销毁aToken
        aToken.burn(msg.sender,qty_);
        pooledA -= amt;
      }else{
        //出售储备币换成稳定币再交易给用户
        uint256 saleAmount = amt - pooledA;
        uint256 saleQty = saleAmount * 1e18 / getPrice(address(reserveToken));
        swap(channel_,quote_);
        //销毁aToken
        aToken.burn(msg.sender,qty_);
        totalReserve -= saleQty;
        matchedA -= saleAmount;
        pooledA -= pooledA;
      }
      //计算手续费
      uint256 commission = amt * redeemFeeRateA / REDEEM_RATE_DENOMINATOR;
      totalCommission += commission;
      //发送USDC
      stableToken.safeTransfer(msg.sender, amt - commission);
      emit Redeem(msg.sender,type_,qty_,amt,commission,aToken.totalNetWorth(),aToken.totalShare());
    }else if(type_ == TYPE.B){
      uint256 amt = qty_ * bToken.netWorth() / 1e18;
      if(token_==address(stableToken)){
        //金库转STABLE_TOKEN给用户
        uint256 saleQty = totalReserve * qty_ / bToken.totalSupply();
        uint256 saleAmount = saleQty * getPrice(address(reserveToken)) / 1e18;
        swap(channel_,quote_);
        //销毁bToken
        bToken.burn(msg.sender,qty_);
        totalReserve -= saleQty;
        pooledA += (saleAmount-amt);
        matchedA -= (saleAmount-amt);
        //计算手续费
        uint256 commission = amt * redeemFeeRateB / REDEEM_RATE_DENOMINATOR;
        totalCommission += commission;
        //发送USDC
        stableToken.safeTransfer(msg.sender, amt - commission);
        emit Redeem(msg.sender,type_,qty_,amt,commission,bToken.totalNetWorth(),bToken.totalSupply());
      }else if(token_==address(reserveToken)){
        //金库转RESERVE_TOKEN给用户
        uint256 redeemReserveQty = totalReserve * qty_ / bToken.totalSupply();
        uint256 transQty = LEVERAGE_DENOMINATOR * redeemReserveQty / leverage();
        uint256 saleQty = (leverage()-LEVERAGE_DENOMINATOR) * redeemReserveQty / leverage();
        if(saleQty>0){
          uint256 saleAmount = saleQty * getPrice(address(reserveToken)) / 1e18;
          swap(channel_,quote_);
          pooledA += saleAmount;
          matchedA -= saleAmount;
        }
        totalReserve -= redeemReserveQty;
        //销毁bToken
        bToken.burn(msg.sender,qty_);
        //计算佣金
        uint256 commissionQty = transQty * redeemFeeRateB / REDEEM_RATE_DENOMINATOR;
        uint256 commission = commissionQty * getPrice(address(reserveToken)) / 1e18;
        totalCommission += commission;
        //发送储备币
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
  * @notice               金库总储备净值=储备币总储量*当前储备币价格+pooledA
  * @return uint256       金库总储备净值
  */
  function totalNetWorth() public view returns(uint256){
    return totalReserve*getPrice(address(reserveToken))/1e18+pooledA;
  }

  /**
  * @notice               动态计算日利息
  */
  function _interestRate() internal view returns(uint256){
    return aToken.totalNetWorth()>0?(matchedA * rewardRate) / aToken.totalNetWorth():rewardRate;
  }

  /**
  * @notice               aToken的日利息(总的日利息的9/10)
  */
  function interestRate() external view returns(uint256){
    return _interestRate() * 9 / 10;
  }

  /**
  * @notice           杠杆率=aToken已配对资金/bToken已配对资金+1
  * @return uint256   bToken的杠杆率
  */
  function leverage() public view returns(uint256){
    return bToken.totalNetWorth()>0?LEVERAGE_DENOMINATOR*matchedA/bToken.totalNetWorth()+1*LEVERAGE_DENOMINATOR:2000000;
  }

  /**
  * @notice    检查bToken的已配对资金,如果小于aToken的已配对资金的60%则触发下折
  */
  function check() external view returns(bool convertDownFlag) {
    if(bToken.totalNetWorth()<matchedA*3/5){
      //判断下折标识为true
      convertDownFlag = true;
    }
  }

  /**
  * @notice           获取bToken的下折价格
  * @return uint256   bToken的下折价格
  */
  function convertDownPrice() external view returns(uint256) {
    return bToken.totalSupply()>0?matchedA * 3 * 1e18 / (5 * bToken.totalSupply()):0;
  }

  /**
  * @notice             下折操作
  * @param channel_     0为0x,1为1inch
  * @param quote_       请求参数
  */
  function convertDown(uint8 channel_,SwapQuote calldata quote_) external onlyRole(OPERATOR_ROLE) nonReentrant{
    require(quote_.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
    require(quote_.buyToken==address(stableToken),WRONG_BUY_TOKEN);
    require(totalReserve / 4  == quote_.sellAmount,WRONG_PARAMETER);
    uint256 buyAmount = quote_.sellAmount * getPrice(address(reserveToken)) / 1e18;
    //console.log("buyAmount=",buyAmount);
    totalReserve -= quote_.sellAmount;
    matchedA -= buyAmount;
    pooledA += buyAmount;
    swap(channel_,quote_);
    emit ConvertDown(matchedA, totalReserve, block.timestamp);
  }

  /**
  * @notice               变基,aToken的已配对资金增加
  */
  function rebase() external nonReentrant{
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
      //matchedA的总获利的1/10作为金库的抽成
      uint256 commission = matchedA * rewardRate / (REWARD_RATE_DENOMINATOR * 10);
      //wstETH的增值部分的1/10作为金库的抽成
      uint256 stakeCommission = totalReserve * getPrice(address(reserveToken)) * stakeRewardRate / (1e18 * REWARD_RATE_DENOMINATOR * 10);
      totalCommission += (commission + stakeCommission);
      totalReserve -= (commission + stakeCommission) * 1e18 / getPrice(address(reserveToken));
      //matchedA的总获利的9/10作为aToken的获利
      matchedA += matchedA * rewardRate * 9 / (REWARD_RATE_DENOMINATOR * 10);
      lastRebaseTime += 86400;
    }
  }

  /**
  * @notice     设置pooledA每天的回报率
  */
  function setRewardRate(uint16 rewardRate_,uint256 deadLine_) external detector(rewardRate_,MAX_REWARD_RATE) onlyRole(OPERATOR_ROLE) nonReentrant{
    changeList[0] = ChangeData(rewardRate_, deadLine_);
  }

  /**
  * @notice     设置reserveToken每天的质押奖励
  */
  function setStakeRewardRate(uint16 stakeRewardRate_) external detector(stakeRewardRate_,MAX_STAKE_REWARD_RATE) onlyRole(OPERATOR_ROLE) nonReentrant{
    stakeRewardRate = stakeRewardRate_;
    emit Change(3,stakeRewardRate,block.timestamp);
  }

  /**
  * @notice                     设置赎回aToken的手续费费率
  * @param redeemFeeRateA_      手续费费率
  */
  function setRedeemFeeRateA(uint16 redeemFeeRateA_,uint256 deadLine_) external detector(redeemFeeRateA_,MAX_REDEEM_FEE_RATE_A) onlyRole(OPERATOR_ROLE) nonReentrant{
    changeList[1] = ChangeData(redeemFeeRateA_, deadLine_);
  }

  /**
  * @notice                     设置赎回bToken的手续费费率
  * @param redeemFeeRateB_      手续费费率
  */
  function setRedeemFeeRateB(uint16 redeemFeeRateB_,uint256 deadLine_) external detector(redeemFeeRateB_,MAX_REDEEM_FEE_RATE_B) onlyRole(OPERATOR_ROLE) nonReentrant{
    changeList[2] = ChangeData(redeemFeeRateB_, deadLine_);
  }

  /**
  * @notice     管理员提取佣金
  */
  function withdraw(uint256 amount,uint8 channel_,SwapQuote calldata quote_) external onlyRole(GOVERNOR_ROLE) nonReentrant{
    require(amount<=totalCommission,WRONG_AMOUNT);
    uint256 balance = stableToken.balanceOf(address(this));
    uint256 receiveAmount = amount;
    if(amount + pooledA>balance){
      //将金库中的reserveToken换成stableToken
      require(quote_.sellToken==address(reserveToken),WRONG_SELL_TOKEN);
      require(quote_.buyToken==address(stableToken),WRONG_BUY_TOKEN);
      require(quote_.sellAmount == amount * 1e18 / getPrice(address(reserveToken)),WRONG_AMOUNT);
      receiveAmount = swap(channel_,quote_);
    }
    totalCommission -= amount;
    stableToken.safeTransfer(msg.sender, receiveAmount);
  }

  /**
  * @notice             设置主合约对0x或者1inch的授信额度
  * @param token        授信操作的token
  * @param channel      0为0x,1为1inch
  * @param amount       授信额度
  */
  function setApprove(IERC20MetadataUpgradeable token,uint8 channel,uint256 amount) external onlyRole(OPERATOR_ROLE) nonReentrant{
    if(channel==0){
      token.approve(ZEROEX_ADDRESS, amount);
    }else if(channel==1){
      token.approve(ONEINCH_ADDRESS, amount);
    }else{
      revert(WRONG_PARAMETER);
    }
  }

}

