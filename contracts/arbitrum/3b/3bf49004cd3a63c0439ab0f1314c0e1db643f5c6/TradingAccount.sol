// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Pausable.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";
import "./AggregatorV3Interface.sol";

//import "./interfaces/IOracle.sol";

contract TradingAccount is Pausable, Ownable {

    uint256 private constant MAX_INT = ~uint256(0);
    uint256 private constant SLIPPAGE_PRECISION = 1e6;

    //8
    uint8 private price_precision;

    AggregatorV3Interface private priceFeed;
    ISwapRouter private  swapRouter;


    //交易对
    address public  usd;
    address public  token;
    

    //网格数目
    uint256 public gridLevels;

    //每一格的实际购买的资产数量
    uint256[] public amountPerGrid;

    //usd,理论值，怎么转化成实际值，确保交易成功
    //（1）需预留交易手续费，
    //价格间隔
    uint256 public gridInterval;
    uint256 public openTradePrice;


    //当前网格位置
    uint256 public currentLevel;
    uint256 public currentLevelPrice;

    //交易手续费 精度 1000000
    //the fee for a pool at the 0.3% tier is 3000; the fee for a pool at the 0.01% tier is 100
    uint24 public poolFee = 3000;
    //滑点 1%
    uint256 public slipPageTolerance = 10000;
    
    //交易金额
    uint256 public tradeAmount;

    /// @notice Emitted when the trade is finished
    /// @param inAmount The amount of tokenIn for trade
    /// @param outAmount The amount of tokenOut we got
    /// @param price the current price that trigger off the trade
    /// @param tradetype true for buy, false for sell
    event TradeFinished(uint256 indexed inAmount, uint256 indexed outAmount, uint256 indexed price, bool tradetype);

    constructor(address _usd, address _token, address _swapRouter, address _oracleAddress){
       
        _setTradePair(_usd, _token, _swapRouter, _oracleAddress);
        _pause();
    }


    function _setTradePair(address _usd, address _token, address _swapRouter, address _oracleAddress) internal{
        usd = _usd;
        token = _token;
        swapRouter = ISwapRouter(_swapRouter);

        /**
        * Network: Sepolia
        * Aggregator: BTC/USD
        * Address: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        */
        priceFeed = AggregatorV3Interface(_oracleAddress);
        price_precision = getDecimals();

    }

    function setTradePair(address _usd, address _token, address _swapRouter, address _oracleAddress) external onlyOwner whenPaused{
         _setTradePair(_usd, _token, _swapRouter, _oracleAddress);
    }

    function initGrid( uint256 _levels, uint256 _Interval,uint256 _amount) external onlyOwner whenPaused{
        _initGrid(_levels,  _Interval, _amount);
        
    }


    //interval 精度8，amount 精度 6
    function _initGrid( uint256 _levels, uint256 _Interval,uint256 _amount) internal {
        require(_levels%2==0,"not right levels");
        require(_Interval>0,"not right interval ");
        
        //reinit the grid array
        _autoAdjustGridArray(_levels+1);
        _clearAllGrid();


        openTradePrice = getLatestPrice();
        currentLevelPrice = openTradePrice;

        gridInterval = _Interval;
        gridLevels = _levels;

        tradeAmount = _amount;

  
        //初始仓位的大小
        currentLevel = _levels/2;
        uint256 usdAmount = currentLevel*tradeAmount;

        //授权合约
        IERC20(usd).approve(address(swapRouter), MAX_INT);
        IERC20(token).approve(address(swapRouter), MAX_INT);
        
        //初始仓位
        uint256 initAmountOut = _swap(usdAmount, openTradePrice,true);
        for(uint256 i=1; i< currentLevel+1; i++){
            amountPerGrid[i] = initAmountOut/currentLevel;
        }

        _unpause();
    }

    function _swap(uint256 _amount,uint256 _price, bool _tradeType) internal returns(uint256 amountOut){
        if(_tradeType){//buy
             amountOut = _swap(_amount, usd,token);
          
        }else{//sell
        
            amountOut = _swap(_amount, token,usd);
            
        }
        emit TradeFinished(_amount, amountOut, _price , _tradeType);
    }

    function _swap(uint256 _usdAmount, address _tokenIn, address _tokenOut)internal returns(uint256 amountOut){

        //这里需要计算,未计算滑点
        uint256 outMinimum = 0;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp+60,
                amountIn: _usdAmount,
                amountOutMinimum: outMinimum,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);

    }



    function checkPrice() public view returns(bool result){
        uint256 current_price = getLatestPrice();

        bool buyState =(current_price <= currentLevelPrice - gridInterval) && (currentLevel < gridLevels);
        bool sellState=(current_price >= currentLevelPrice + gridInterval) && (currentLevel !=0);

        result = buyState||sellState;
    }

    function buyTest() public onlyOwner{
        
        uint256 current_price = getLatestPrice();
         //交易 买
           uint256 amount =  _swap(tradeAmount,current_price, true);
        
            //更新状态
           amountPerGrid[currentLevel +1 ] = amount;
           currentLevel = currentLevel +1;
           currentLevelPrice = currentLevelPrice - gridInterval;

    }

    function sellTest() public onlyOwner{
         uint256 current_price = getLatestPrice();
        //售卖b token的数量,滑点需要考虑
            uint256 sellAmount = amountPerGrid[currentLevel];
            //卖
            _swap(sellAmount,current_price, false);
            
            //更新状态
            amountPerGrid[currentLevel] = 0;
            currentLevel = currentLevel -1;
            currentLevelPrice = currentLevelPrice + gridInterval;
    }

    function trading() public whenNotPaused{

        require(checkPrice(),"no need to trade!");
        uint256 current_price = getLatestPrice();

        if((current_price <= currentLevelPrice - gridInterval) && (currentLevel < gridLevels)){
            //交易 买
           uint256 amount =  _swap(tradeAmount,current_price, true);
        
            //更新状态
           amountPerGrid[currentLevel +1 ] = amount;
           currentLevel = currentLevel +1;
           currentLevelPrice = currentLevelPrice - gridInterval;
        }

        if((current_price >= currentLevelPrice + gridInterval) && (currentLevel !=0)){
            
            //售卖b token的数量,滑点需要考虑
            uint256 sellAmount = amountPerGrid[currentLevel];
            //卖
            _swap(sellAmount,current_price, false);
            
            //更新状态
            amountPerGrid[currentLevel] = 0;
            currentLevel = currentLevel -1;
            currentLevelPrice = currentLevelPrice + gridInterval;
           

        }

    }


     /**
     * Returns the latest price.
     */
    function getLatestPrice() public view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int256 price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        if(price >0){
            return uint256(price);
        }else{
            return 0;
        }
        
    }

    function getDecimals() public view returns (uint8) {
       return priceFeed.decimals();   
    }


    //deposit
    function _deposit(
        address _token,
        uint256 _amount
    ) internal  {
        require(_token==usd||_token==token,"not the right token assets!");
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        
    }

    function deposit(
        address _token,
        uint256 _amount
    ) external{
        _deposit(_token, _amount);
    }

    //withdraw
    function _withdraw(
        address _token,
        address _to,
        uint256 _amount
    )internal {
        require(IERC20(_token).balanceOf(address(this))>=_amount, "not engouth assets!");
        IERC20(_token).transfer(_to, _amount);
    }


    //withdraw
    function withdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner{
        _withdraw(_token, _to, _amount);
    }


    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function getAmountPerGrid(uint256 i) public view returns (uint256) {
        return amountPerGrid[i];
    }

    function getGridLength()public view returns (uint256) {
        return amountPerGrid.length;
    }

    function getGrids() public view returns (uint256[] memory) {
        return amountPerGrid;
    }

    //将仓位都卖掉
    function liquidation() public onlyOwner{

        uint256 current_price = getLatestPrice();
        uint256 tokenAmount  =  IERC20(token).balanceOf(address(this));

        if(tokenAmount > 0){
            _swap(tokenAmount, current_price,false);
        }

        _pause();
        
    }
   function _autoAdjustGridArray(uint256 _n) internal{
        uint256 length = amountPerGrid.length;
        uint256 i = 0;
        if(_n > length){
            for(i = length;i<_n;i++){
                amountPerGrid.push(0);
            }
        }else if(_n<length){
            for(i=_n;i<length;i++){
                amountPerGrid.pop();
            }
        }
    }

    function _clearAllGrid() internal{
        for(uint256 i=0; i<amountPerGrid.length;i++){
            amountPerGrid[i] = 0;
        }

    }

    function _calculateMinOutAmount(uint256 _inAmount, uint256 _price) internal view returns(uint256 minOutAmount){
        minOutAmount = _inAmount * price_precision*(SLIPPAGE_PRECISION - slipPageTolerance)/(_price*SLIPPAGE_PRECISION);
    }
}
