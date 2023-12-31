// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./Pausable.sol";

import "./IGarbiswapFeeMachine.sol";
import "./IGarbiswapWhitelist.sol";
import "./IGarbiTimeLock.sol";
import "./IGarbiOracle.sol";

contract GarbiswapTradeDAIUSDC is ERC20Burnable, Ownable, Pausable {
    
    using SafeMath for uint256;

    IERC20 public base; // Stable coin base token (USDC)
    IERC20 public token; // Token to trade in this pair

    // Fee Machine Contract.
    IGarbiswapFeeMachine public feeMachineContract; 

    IGarbiswapWhitelist public whitelistContract; 

    IGarbiTimeLock public garbiTimeLockContract;

    IGarbiOracle public garbiOracle;

    uint256 public TRADE_FEE = 10; //0.01% 35/100000

    uint256 public PLATFORM_FEE = 25; //2.5% 25/1000

    address public platformFundAddress;

    modifier onlyWhitelist()
    {
        if (msg.sender != tx.origin) {
            require(whitelistContract.whitelisted(msg.sender) == true, 'INVALID_WHITELIST');
        }
        _;
    }

    // Events

    event onSwapBaseToTokenWithBaseInput(address sender, uint256 minTokenOutput, uint256 baseInputAmount, uint256 tokenOutputAmount, uint256 poolBaseBalance, uint256 poolTokenBalance);
    event onSwapBaseToTokenWithTokenOutput(address sender, uint256 maxBaseInput, uint256 baseInputAmount, uint256 tokenOutputAmount, uint256 poolBaseBalance, uint256 poolTokenBalance);
    
    event onSwapTokenToBaseWithTokenInput(address sender, uint256 minBaseOutput, uint256 tokenInputAmount, uint256 baseOutputAmount, uint256 poolBaseBalance, uint256 poolTokenBalance);
    event onSwapTokenToBaseWithBaseOutput(address sender, uint256 maxTokenInput, uint256 tokenInputAmount, uint256 baseOutputAmount, uint256 poolBaseBalance, uint256 poolTokenBalance);

    event onAddLP(address sender, uint256 mintLP, uint256 baseInputAmount, uint256 tokenInputAmount, uint256 poolBaseBalance, uint256 poolTokenBalance);
    event onRemoveLP(address sender, uint256 amountLP, uint256 baseOutputAmout, uint256 tokenOutputAmount, uint256 poolBaseBalance, uint256 poolTokenBalance);

    constructor(
        IERC20 _base,
        IERC20 _token,
        IGarbiTimeLock _garbiTimeLockContract,
        IGarbiswapFeeMachine _feeMachineContract,
        IGarbiswapWhitelist _whitelistContract,
        IGarbiOracle _garbiOracle,
        string memory name, 
        string memory symbol
        ) ERC20(name, symbol) {
        base = _base;
        token = _token;
        garbiTimeLockContract = _garbiTimeLockContract;
        whitelistContract = _whitelistContract;
        feeMachineContract = _feeMachineContract;
        garbiOracle = _garbiOracle;
        platformFundAddress = _msgSender();
    }

    function setWhitelistContract() public onlyOwner {
        require(garbiTimeLockContract.isQueuedTransaction(address(this), 'setWhitelistContract'), "INVALID_PERMISSION");

        address _whitelistContract = garbiTimeLockContract.getAddressChangeOnTimeLock(address(this), 'setWhitelistContract', 'whitelistContract');

        require(_whitelistContract != address(0), "INVALID_ADDRESS");

        whitelistContract = IGarbiswapWhitelist(_whitelistContract);

        garbiTimeLockContract.clearFieldValue('setWhitelistContract', 'whitelistContract', 1);
        garbiTimeLockContract.doneTransactions('setWhitelistContract');
    }

    function setFeeMachineContract() public onlyOwner {

        require(garbiTimeLockContract.isQueuedTransaction(address(this), 'setFeeMachineContract'), "INVALID_PERMISSION");

        address _feeMachineContract = garbiTimeLockContract.getAddressChangeOnTimeLock(address(this), 'setFeeMachineContract', 'feeMachineContract');

        require(_feeMachineContract != address(0), "INVALID_ADDRESS");

        feeMachineContract = IGarbiswapFeeMachine(_feeMachineContract);

        garbiTimeLockContract.clearFieldValue('setFeeMachineContract', 'feeMachineContract', 1);
        garbiTimeLockContract.doneTransactions('setFeeMachineContract');
    }

    function setTradeFee() public onlyOwner {

        require(garbiTimeLockContract.isQueuedTransaction(address(this), 'setTradeFee'), "INVALID_PERMISSION");

        uint256 _tradeFee = garbiTimeLockContract.getUintChangeOnTimeLock(address(this), 'setTradeFee', 'tradeFee');

        TRADE_FEE = _tradeFee;

        garbiTimeLockContract.clearFieldValue('setTradeFee', 'tradeFee', 2);
        garbiTimeLockContract.doneTransactions('setTradeFee');
    }

    function setPlatformFee() public onlyOwner {

        require(garbiTimeLockContract.isQueuedTransaction(address(this), 'setPlatformFee'), "INVALID_PERMISSION");

        uint256 _platformFee = garbiTimeLockContract.getUintChangeOnTimeLock(address(this), 'setPlatformFee', 'platformFee');

        PLATFORM_FEE = _platformFee;

        garbiTimeLockContract.clearFieldValue('setPlatformFee', 'platformFee', 2);
        garbiTimeLockContract.doneTransactions('setPlatformFee');
    }

    function setPlatformFundAdress(address newAddress) public onlyOwner {
        platformFundAddress = newAddress;
    }

    function getK() public view returns(uint256) {
        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        uint256 k = tokenReserve.mul(baseReserve);
        return k;
    }

    function getTokenOutput(uint256 baseInputAmount) public view returns (uint256) {
        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();

        baseInputAmount = convertDecimal6to18(baseInputAmount);

        uint256 tradeFee = baseInputAmount.mul(TRADE_FEE).div(100000);
        uint256 baseInputAmountAfterFee = baseInputAmount.sub(tradeFee); // cut the TRADE_FEE from base input

        uint256 tokenOutputAmount = getTokenOutputAmountFromBaseInput(baseInputAmountAfterFee, baseReserve, tokenReserve);
        return tokenOutputAmount;
    }

    function getBaseOutput(uint256 tokenInputAmount) public view returns (uint256) {
        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();

        uint256 tradeFee = tokenInputAmount.mul(TRADE_FEE).div(100000);
        uint256 tokenInputAmountAfterFee = tokenInputAmount.sub(tradeFee); // cut the TRADE_FEE from token input

        uint256 baseOutputAmount = getBaseOutputAmountFromTokenInput(tokenInputAmountAfterFee, baseReserve, tokenReserve);
        baseOutputAmount = convertDecimal18to6(baseOutputAmount);
        return baseOutputAmount;
    }

    function getDataFromBaseInputToAddLp(uint256 baseInputAmount) public view returns (uint256, uint256) {
        uint256 totalSupply = totalSupply();
        uint256 mintLP = 0;
        uint256 tokenInputAmount = 0;
        
         baseInputAmount = convertDecimal6to18(baseInputAmount);

        if(totalSupply == 0) {
            mintLP = baseInputAmount;
            tokenInputAmount = baseInputAmount;
        }
        else { 
            // tokenReserve/baseReserve = (tokenReserve+tokenInputAmount)/(baseReserve+baseInputAmount)
            // => tokenReserve+tokenInputAmount = tokenReserve*(baseReserve+baseInputAmount)/baseReserve
            // => tokenInputAmount = tokenReserve*(baseReserve+baseInputAmount)/baseReserve - tokenReserve;
            uint256 baseReserve = 0;
            uint256 tokenReserve = 0;
            (baseReserve, tokenReserve) = getTotalReserve();
            tokenInputAmount = tokenReserve.mul(baseReserve.add(baseInputAmount)).div(baseReserve).sub(tokenReserve);

            uint256 platformFeeOnBase = baseInputAmount.mul(PLATFORM_FEE).div(1000);

            // mintLP/totalLP =  baseInputAmount/baseReserve
            // mintLP = totalLP*baseInputAmount/baseReserve
            mintLP = totalSupply.mul(baseInputAmount.sub(platformFeeOnBase)).div(baseReserve);
        }
        return (mintLP, tokenInputAmount);
    }

    function getDataFromTokenInputToAddLp(uint256 tokenInputAmount) public view returns (uint256, uint256) {
        uint256 totalSupply = totalSupply();
        uint256 mintLP;
        uint256 baseInputAmount;
        if(totalSupply == 0) {
            mintLP = tokenInputAmount;
            baseInputAmount = tokenInputAmount;
        }
        else { 
            // tokenReserve/baseReserve = (tokenReserve+tokenInputAmount)/(baseReserve+baseInputAmount)
            // => (baseReserve+baseInputAmount) = (tokenReserve+tokenInputAmount) * baseReserve / tokenReserve
            //  => baseInputAmount = (tokenReserve+tokenInputAmount) * baseReserve / tokenReserve - baseReserve
            uint256 baseReserve = 0;
            uint256 tokenReserve = 0;
            (baseReserve, tokenReserve) = getTotalReserve();

            baseInputAmount = baseReserve.mul(tokenReserve.add(tokenInputAmount)).div(tokenReserve).sub(baseReserve);

            uint256 platformFeeOnBase = baseInputAmount.mul(PLATFORM_FEE).div(1000);

            // mintLP/totalLP =  baseInputAmount/baseReserve
            // mintLP = totalLP*baseInputAmount/baseReserve
            mintLP = totalSupply.mul(baseInputAmount.sub(platformFeeOnBase)).div(baseReserve);
        }
        return (mintLP, convertDecimal18to6(baseInputAmount));
    }

    function getDataToRemoveLP(uint256 amountLP) public view returns (uint256, uint256){
        
        uint256 totalSupply = totalSupply();

        if (amountLP > totalSupply) {
            amountLP = totalSupply;
        } 
        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        
        // amountLP/totalSupply = baseOutputAmount/baseReserve
        // => baseOutputAmount = amountLP*baseReserve/totalSupply
        uint256 baseOutputAmount = amountLP.mul(baseReserve).div(totalSupply);
        uint256 tokenOutputAmount = amountLP.mul(tokenReserve).div(totalSupply);
        
        uint256 platformFeeOnBase = baseOutputAmount.mul(PLATFORM_FEE).div(1000);
        uint256 platformFeeOnToken = tokenOutputAmount.mul(PLATFORM_FEE).div(1000);
        
        baseOutputAmount = baseOutputAmount.sub(platformFeeOnBase);
        tokenOutputAmount = tokenOutputAmount.sub(platformFeeOnToken);
        
        return (convertDecimal18to6(baseOutputAmount), tokenOutputAmount);
    }
    
    //tokenOutputAmount/baseInputAmount = tokenPriceFromOracle/basePriceFromOracle
    //tokenOutputAmount = baseInputAmount*tokenPriceFromOracle/basePriceFromOracle
    function getTokenOutputAmountFromBaseInput(uint256 baseInputAmount, uint256 baseReserve, uint256 tokenReserve) public view returns (uint256) {
      require(baseReserve > 0 && tokenReserve > 0, "INVALID_VALUE");
      uint256 tokenPriceFromOracle = garbiOracle.getLatestPrice(address(token));
      uint256 basePriceFromOracle = garbiOracle.getLatestPrice(address(base));
      uint256 tokenOutputAmount = baseInputAmount.mul(tokenPriceFromOracle).div(basePriceFromOracle);
      return tokenOutputAmount;
    }
    
    //tokenOutputAmount/baseInputAmount = tokenPriceFromOracle/basePriceFromOracle
    //baseInputAmount = tokenOutputAmount*basePriceFromOracle/tokenPriceFromOracle
    function getBaseInputAmountFromTokenOutput(uint256 tokenOutputAmount, uint256 baseReserve, uint256 tokenReserve) public view  returns (uint256) {
      require(baseReserve > 0 && tokenReserve > 0, "INVALID_VALUE");
      uint256 tokenPriceFromOracle = garbiOracle.getLatestPrice(address(token));
      uint256 basePriceFromOracle = garbiOracle.getLatestPrice(address(base));
      uint256 baseInputAmount = tokenOutputAmount.mul(basePriceFromOracle).div(tokenPriceFromOracle);
      return baseInputAmount;
    }
    
    //tokenInputAmount/baseOutputAmount = tokenPriceFromOracle/basePriceFromOracle
    //baseOutputAmount = tokenInputAmount*basePriceFromOracle/tokenPriceFromOracle
    function getBaseOutputAmountFromTokenInput(uint256 tokenInputAmount, uint256 baseReserve, uint256 tokenReserve) public view returns (uint256) {
      require(baseReserve > 0 && tokenReserve > 0, "INVALID_VALUE");
      uint256 tokenPriceFromOracle = garbiOracle.getLatestPrice(address(token));
      uint256 basePriceFromOracle = garbiOracle.getLatestPrice(address(base));
      uint256 baseOutputAmount = tokenInputAmount.mul(basePriceFromOracle).div(tokenPriceFromOracle);
      return baseOutputAmount;
    }

    //tokenInputAmount/baseOutputAmount = tokenPriceFromOracle/basePriceFromOracle
    //tokenInputAmount = baseOutputAmount*tokenPriceFromOracle/basePriceFromOracle
    function getTokenInputAmountFromBaseOutput(uint256 baseOutputAmount, uint256 baseReserve, uint256 tokenReserve) public view returns (uint256) {
      require(baseReserve > 0 && tokenReserve > 0, "INVALID_VALUE");
      uint256 tokenPriceFromOracle = garbiOracle.getLatestPrice(address(token));
      uint256 basePriceFromOracle = garbiOracle.getLatestPrice(address(base));
      uint256 tokenInputAmount = baseOutputAmount.mul(tokenPriceFromOracle).div(basePriceFromOracle);
      return tokenInputAmount;
    }

    function swapBaseToTokenWithBaseInput(uint256 baseInputAmount, uint256 minTokenOutput, uint256 deadline) public onlyWhitelist whenNotPaused{
        require(deadline >= block.timestamp, 'INVALID_DEADLINE');
        require(baseInputAmount > 0, 'INVALID_BASE_INPUT');
        require(minTokenOutput > 0, 'INVALID_MIN_TOKEN_OUTPUT');
        require(baseInputAmount <= base.balanceOf(msg.sender), 'BASE_INPUT_HIGHER_USER_BALANCE');
        
        baseInputAmount = convertDecimal6to18(baseInputAmount);

        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        require(minTokenOutput < tokenReserve, "MIN_TOKEN_HIGHER_POOL_TOKEN_BALANCE");
        
        uint256 tradeFee = baseInputAmount.mul(TRADE_FEE).div(100000);
        uint256 baseInputAmountAfterFee = baseInputAmount.sub(tradeFee); // cut the TRADE_FEE from base input
        
        uint256 tokenOutputAmount = getTokenOutputAmountFromBaseInput(baseInputAmountAfterFee, baseReserve, tokenReserve);

        require(tokenOutputAmount >= minTokenOutput, 'CAN_NOT_MAKE_TRADE');
        require(tokenOutputAmount < tokenReserve, 'TOKEN_OUTPUT_HIGHER_POOL_TOKEN_BALANCE');
        require(tokenOutputAmount < token.balanceOf(address(this)), 'TOKEN_OUTPUT_HIGHER_CURRENT_TRADE_BALANCE'); // output is higher than the trade contract balance
        
        //make trade
        baseInputAmount = convertDecimal18to6(baseInputAmount);
        base.transferFrom(msg.sender, address(this), baseInputAmount);

        token.transfer(msg.sender, tokenOutputAmount);

        //transfer fee
        tradeFee = convertDecimal18to6(tradeFee);
        base.transfer(address(feeMachineContract), tradeFee);
        feeMachineContract.processTradeFee(base, msg.sender); 

        emit onSwapBaseToTokenWithBaseInput(msg.sender, minTokenOutput, baseInputAmount, tokenOutputAmount, convertDecimal18to6(baseReserve), tokenReserve);
    }

    function swapBaseToTokenWithTokenOutput(uint256 maxBaseInput, uint256 tokenOutputAmount, uint256 deadline) public onlyWhitelist whenNotPaused{
        require(deadline >= block.timestamp, 'INVALID_DEADLINE');
        require(maxBaseInput > 0, 'INVALID_MAX_BASE_INPUT');
        require(tokenOutputAmount > 0, 'INVALID_TOKEN_OUTPUT');
        require(tokenOutputAmount < token.balanceOf(address(this)), 'TOKEN_OUTPUT_HIGHER_CURRENT_TRADE_BALANCE'); // output is higher than the trade contract balance
        
        maxBaseInput = convertDecimal6to18(maxBaseInput);

        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        require(tokenOutputAmount < tokenReserve, "TOKEN_OUTPUT_HIGHER_POOL_TOKEN_BALANCE");

        uint256 baseInputAmount = getBaseInputAmountFromTokenOutput(tokenOutputAmount, baseReserve, tokenReserve);
        
        uint256 tradeFee = baseInputAmount.mul(TRADE_FEE).div(100000);
        baseInputAmount = baseInputAmount.add(tradeFee); // add the TRADE_FEE to base input

        require(baseInputAmount <= maxBaseInput, 'CAN_NOT_MAKE_TRADE');
        require(baseInputAmount > 0, 'INVALID_BASE_INPUT');
        require(baseInputAmount <= convertDecimal6to18(base.balanceOf(msg.sender)), 'BASE_INPUT_HIGHER_USER_BALANCE');
        
        //make trade
        baseInputAmount = convertDecimal18to6(baseInputAmount);
        base.transferFrom(msg.sender, address(this), baseInputAmount);

        token.transfer(msg.sender, tokenOutputAmount);

        //transfer fee
        tradeFee = convertDecimal18to6(tradeFee);
        base.transfer(address(feeMachineContract), tradeFee);
        feeMachineContract.processTradeFee(base, msg.sender);

        emit onSwapBaseToTokenWithTokenOutput(msg.sender, convertDecimal18to6(maxBaseInput), baseInputAmount, tokenOutputAmount, convertDecimal18to6(baseReserve), tokenReserve);
    }

    function swapTokenToBaseWithTokenInput(uint256 tokenInputAmount, uint256 minBaseOutput, uint256 deadline) public onlyWhitelist whenNotPaused{
        require(deadline >= block.timestamp, 'INVALID_DEADLINE');
        require(minBaseOutput > 0, 'INVALID_MIN_BASE_OUTPUT');
        require(tokenInputAmount > 0, 'INVALID_TOKEN_INPUT');
        require(tokenInputAmount <= token.balanceOf(msg.sender), 'TOKEN_INPUT_HIGHER_USER_BALANCE');

        minBaseOutput = convertDecimal6to18(minBaseOutput);

        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        require(minBaseOutput < baseReserve, 'MIN_BASE_OUTPUT_HIGHER_POOL_BASE_BALANCE');

        uint256 tradeFee = tokenInputAmount.mul(TRADE_FEE).div(100000);
        uint256 tokenInputAmountAfterFee = tokenInputAmount.sub(tradeFee); // cut the TRADE_FEE from token input
        
        uint256 baseOutputAmount = getBaseOutputAmountFromTokenInput(tokenInputAmountAfterFee, baseReserve, tokenReserve);

        require(baseOutputAmount >= minBaseOutput, 'CAN_NOT_MAKE_TRADE');
        require(baseOutputAmount < baseReserve, 'BASE_OUTPUT_HIGHER_POOL_BASE_BALANCE');
        require(baseOutputAmount < convertDecimal6to18(base.balanceOf(address(this))), 'BASE_OUTPUT_HIGHER_CURRENT_TRADE_BALANCE'); // output is higher than the trade contract balance

        //make trade
        token.transferFrom(msg.sender, address(this), tokenInputAmount);

        baseOutputAmount = convertDecimal18to6(baseOutputAmount);
        base.transfer(msg.sender, baseOutputAmount);

        //transfer fee
        token.transfer(address(feeMachineContract), tradeFee);
        feeMachineContract.processTradeFee(token, msg.sender);

        emit onSwapTokenToBaseWithTokenInput(msg.sender, convertDecimal18to6(minBaseOutput), tokenInputAmount, baseOutputAmount, convertDecimal18to6(baseReserve), tokenReserve);
    }

    function swapTokenToBaseWithBaseOutput(uint256 maxTokenInput, uint256 baseOutputAmount, uint256 deadline) public onlyWhitelist whenNotPaused{
        require(deadline >= block.timestamp, 'INVALID_DEADLINE');
        require(maxTokenInput > 0, 'INVALID_MAX_TOKEN_INPUT');
        require(baseOutputAmount > 0, 'INVALID_BASE_OUTPUT');
        require(baseOutputAmount < base.balanceOf(address(this)), 'BASE_OUTPUT_HIGHER_CURRENT_TRADE_BALANCE'); // output is higher than the trade contract balance
        
        baseOutputAmount = convertDecimal6to18(baseOutputAmount);

        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        require(baseOutputAmount < baseReserve, 'BASE_OUTPUT_HIGHER_POOL_BASE_BALANCE');

        uint256 tokenInputAmount = getTokenInputAmountFromBaseOutput(baseOutputAmount, baseReserve, tokenReserve);
        
        uint256 tradeFee = tokenInputAmount.mul(TRADE_FEE).div(100000);
        tokenInputAmount = tokenInputAmount.add(tradeFee); // add the TRADE_FEE to token input

        require(tokenInputAmount <= maxTokenInput, 'CAN_NOT_MAKE_TRADE');
        require(tokenInputAmount > 0, 'INVALID_TOKEN_INPUT');
        require(tokenInputAmount <= token.balanceOf(msg.sender), 'TOKEN_INPUT_HIGHER_USER_BALANCE');

        //make trade
        token.transferFrom(msg.sender, address(this), tokenInputAmount);
        
        baseOutputAmount = convertDecimal18to6(baseOutputAmount);
        base.transfer(msg.sender, baseOutputAmount);

        //transfer fee
        token.transfer(address(feeMachineContract), tradeFee);
        feeMachineContract.processTradeFee(token, msg.sender);

        emit onSwapTokenToBaseWithBaseOutput(msg.sender, maxTokenInput, tokenInputAmount, baseOutputAmount, convertDecimal18to6(baseReserve), tokenReserve);
    }

    function addLP(uint256 minLP, uint256 baseInputAmount, uint256 maxTokenInputAmount, uint256 deadline) public onlyWhitelist returns (uint256) {
        require(deadline >= block.timestamp, 'INVALID_DEADLINE');
        require(minLP > 0, 'INVALID_MIN_LP');
        require(baseInputAmount > 0, 'INVALID_BASE_INPUT');
        require(maxTokenInputAmount > 0, 'INVALID_MAX_TOKEN_INPUT');
        
        uint256 totalSupply = totalSupply();
        if(totalSupply == 0) {
            base.transferFrom(msg.sender, address(this), baseInputAmount);
            token.transferFrom(msg.sender, address(this), maxTokenInputAmount);

            baseInputAmount = convertDecimal6to18(baseInputAmount);

            uint256 platformFeeOnBase = baseInputAmount.mul(PLATFORM_FEE).div(1000);
            uint256 platformFeeOnToken = maxTokenInputAmount.mul(PLATFORM_FEE).div(1000);
            
            uint256 initLP = baseInputAmount.sub(platformFeeOnBase);

            platformFeeOnBase = convertDecimal18to6(platformFeeOnBase);
            base.transfer(platformFundAddress, platformFeeOnBase);
            token.transfer(platformFundAddress, platformFeeOnToken);
            
            _mint(msg.sender, initLP);
            emit onAddLP(msg.sender, initLP, convertDecimal18to6(baseInputAmount), maxTokenInputAmount, base.balanceOf(address(this)), token.balanceOf(address(this)));
            return initLP;
        }
        else {
            baseInputAmount = convertDecimal6to18(baseInputAmount);
            // tokenReserve/baseReserve = (tokenReserve+tokenInputAmount)/(baseReserve+baseInputAmount)
            // => tokenReserve+tokenInputAmount = tokenReserve*(baseReserve+baseInputAmount)/baseReserve
            // => tokenInputAmount = tokenReserve*(baseReserve+baseInputAmount)/baseReserve - tokenReserve;
            uint256 baseReserve = 0;
            uint256 tokenReserve = 0;
            (baseReserve, tokenReserve) = getTotalReserve();
            uint256 tokenInputAmount = tokenReserve.mul(baseReserve.add(baseInputAmount)).div(baseReserve).sub(tokenReserve);

            uint256 platformFeeOnBase = baseInputAmount.mul(PLATFORM_FEE).div(1000);
            uint256 platformFeeOnToken = tokenInputAmount.mul(PLATFORM_FEE).div(1000);

            // mintLP/totalLP =  baseInputAmount/baseReserve
            // mintLP = totalLP*baseInputAmount/baseReserve
            uint256 mintLP = totalSupply.mul(baseInputAmount.sub(platformFeeOnBase)).div(baseReserve);
            
            require(tokenInputAmount > 0, 'INVALID_TOKEN_INPUT');
            require(tokenInputAmount <= maxTokenInputAmount, 'INVALID_TOKEN_INPUT');
            require(mintLP >= minLP, "INVALID_MINT_LP");
            
            baseInputAmount = convertDecimal18to6(baseInputAmount);
            base.transferFrom(msg.sender, address(this), baseInputAmount);
            token.transferFrom(msg.sender, address(this), tokenInputAmount);

            platformFeeOnBase = convertDecimal18to6(platformFeeOnBase);
            base.transfer(platformFundAddress, platformFeeOnBase);
            token.transfer(platformFundAddress, platformFeeOnToken);

            _mint(msg.sender, mintLP);
            emit onAddLP(msg.sender, mintLP, baseInputAmount, tokenInputAmount, base.balanceOf(address(this)), token.balanceOf(address(this)));
            return mintLP;
        }
    }

    function removeLP(uint256 amountLP, uint256 minBaseOutput, uint256 minTokenOutput, uint256 deadline) public onlyWhitelist returns (uint256, uint256){
        require(deadline >= block.timestamp, 'INVALID_DEADLINE');
        require(amountLP > 0, 'INVALID_AMOUNT_LP');
        require(minBaseOutput > 0, 'INVALID_MIN_BASE_OUTPUT');
        require(minTokenOutput > 0, 'INVALID_MIN_TOKEN_OUTPUT');
        
        minBaseOutput = convertDecimal6to18(minBaseOutput);

        uint256 totalSupply = totalSupply();
        
        uint256 userLPbalance = balanceOf(msg.sender);
        if(amountLP > userLPbalance) {
            amountLP = userLPbalance;
        }

        require(amountLP <= totalSupply, 'INVALID_AMOUNT_LP_TOTAL_SUPPLY');
         
        uint256 baseReserve = 0;
        uint256 tokenReserve = 0;
        (baseReserve, tokenReserve) = getTotalReserve();
        
        // amountLP/totalSupply = baseOutputAmount/baseReserve
        // => baseOutputAmount = amountLP*baseReserve/totalSupply
        uint256 baseOutputAmount = amountLP.mul(baseReserve).div(totalSupply);
        uint256 tokenOutputAmount = amountLP.mul(tokenReserve).div(totalSupply);

        uint256 platformFeeOnBase = baseOutputAmount.mul(PLATFORM_FEE).div(1000);
        uint256 platformFeeOnToken = tokenOutputAmount.mul(PLATFORM_FEE).div(1000);
        
        baseOutputAmount = baseOutputAmount.sub(platformFeeOnBase);
        tokenOutputAmount = tokenOutputAmount.sub(platformFeeOnToken);

        require(baseOutputAmount >= minBaseOutput, "INVALID_BASE_OUTPUT");
        require(tokenOutputAmount >= minTokenOutput, "INVALID_TOKEN_OUTPUT");
        require(baseOutputAmount <= baseReserve, "BASE_OUTPUT_HIGHER_BASE_BALANCE");
        require(tokenOutputAmount <= tokenReserve, "TOKEN_OUTPUT_HIGHER_TOKEN_BALANCE");

        _burn(msg.sender, amountLP);
        
        baseOutputAmount = convertDecimal18to6(baseOutputAmount);
        base.transfer(msg.sender, baseOutputAmount);

        token.transfer(msg.sender, tokenOutputAmount);

        platformFeeOnBase = convertDecimal18to6(platformFeeOnBase);
        base.transfer(platformFundAddress, platformFeeOnBase);

        token.transfer(platformFundAddress, platformFeeOnToken);

        emit onRemoveLP(msg.sender, amountLP, baseOutputAmount, tokenOutputAmount, base.balanceOf(address(this)), token.balanceOf(address(this)));
        return (baseOutputAmount, tokenOutputAmount);
    }

    function getTotalReserve() public view returns (uint256, uint256) { 
        uint256 baseReserve = base.balanceOf(address(this));
        baseReserve = convertDecimal6to18(baseReserve);

        uint256 tokenReserve = token.balanceOf(address(this));

        return (baseReserve, tokenReserve);
    }

    function convertDecimal6to18(uint256 number) public pure returns (uint256) { 
        number = number.mul(1e18).div(1e6);
        return number;
    }

    function convertDecimal18to6(uint256 number) public pure returns (uint256) { 
        number = number.mul(1e6).div(1e18);
        return number;
    }

    function pause() public onlyOwner {
        _pause();
    }
    
    function unpause() public onlyOwner {
        _unpause();
    }
}
