// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./ISwapRouter.sol";
import "./IPeripheryPaymentsWithFee.sol";
import "./IQuoter.sol";
import "./TransferHelper.sol";
import "./IFiat24Account.sol";

error Fiat24CryptoDeposit__NotOperator(address sender);
error Fiat24CryptoDeposit__NotRateUpdater(address sender);
error Fiat24CryptoDeposit__Paused();
error Fiat24CryptoDeposit__NotValidOutputToken(address token);
error Fiat24CryptoDeposit__NotValidInputToken(address token);
error Fiat24CryptoDeposit__ValueZero();
error Fiat24CryptoDeposit__EthRefundFailed();
error Fiat24CryptoDeposit__SwapOutputAmountZero();
error Fiat24CryptoDeposit__UsdcAmountHigherMaxDepositAmount(uint256 usdcAmount, uint256 maxAmount);
error Fiat24CryptoDeposit__NoPoolAvailable(address tokenA, address tokenB);
error Fiat24CryptoDeposit__ExchangeRateNotAvailable(address inputToken, address outputToken);

contract Fiat24CryptoDeposit is Initializable, AccessControlUpgradeable, PausableUpgradeable {

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RATES_UPDATER_OPERATOR_ROLE = keccak256("RATES_UPDATER_OPERATOR_ROLE");
    bytes32 public constant RATES_UPDATER_ROBOT_ROLE = keccak256("RATES_UPDATER_ROBOT_ROLE");

    uint256 public constant USDC_DIVISOR = 10000;
    uint256 public constant XXX24_DIVISOR = 10000;

    uint256 public constant CRYPTO_DESK = 9105;
    uint256 public constant TREASURY_DESK = 9100;

    //UNISWAP ADDRESSES ARBITRUM MAINNET
    address public constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNISWAP_PERIPHERY_PAYMENTS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    address public fiat24account;
    address public usd24;
    address public eur24;
    address public chf24;
    address public gbp24;
    address public usdc;
    address public weth;

    uint256 public slippage;

    //Max USDC top-up amount
    uint256 public maxDepositAmount;

    mapping (address => bool) public validXXX24Tokens;
    mapping (address => mapping(address => uint256)) public exchangeRates;

    bool public marketClosed;
    uint256 public exchangeSpread;
    uint256 public marketClosedSpread;

    event DepositedEth(address indexed sender, address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount);
    event DepositedTokenViaUsd(address indexed sender, address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount);
    event DepositedTokenViaEth(address indexed sender, address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount);
    event MoneyExchanged(address indexed sender, address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount);
    event ExchangeRatesUpdatedByOperator(address indexed sender, uint256 usdeur, uint256 usdchf, uint256 usdgbp, bool marketClosed);
    event ExchangeRatesUpdatedByRobot(address indexed sender, uint256 usdeur, uint256 usdchf, uint256 usdgbp, bool marketClosed);

    function initialize(address _fiat24account, 
                        address _usd24,
                        address _eur24,
                        address _chf24,
                        address _gbp24,
                        address _usdc,
                        address _weth) public initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        fiat24account = _fiat24account;
        usd24 = _usd24;
        eur24 = _eur24;
        chf24 = _chf24;
        gbp24 = _gbp24;
        usdc = _usdc;
        weth = _weth;
        maxDepositAmount = 100000;
        slippage = 5;

        validXXX24Tokens[_usd24] = true;
        validXXX24Tokens[_eur24] = true;
        validXXX24Tokens[_chf24] = true;
        validXXX24Tokens[_gbp24] = true;

        exchangeRates[usd24][usd24] = 10000;
        exchangeRates[usd24][eur24] = 9222;
        exchangeRates[usd24][chf24] = 9130;
        exchangeRates[usd24][gbp24] = 7239;
        
        marketClosed = false;
        exchangeSpread = 9900;
        marketClosedSpread = 9995;
    }

    function depositETH(address _outputToken) external payable returns(uint256) {
        if(paused()) revert Fiat24CryptoDeposit__Paused();
        if(msg.value == 0) revert Fiat24CryptoDeposit__ValueZero();
        if(!validXXX24Tokens[_outputToken]) revert Fiat24CryptoDeposit__NotValidOutputToken(_outputToken);

        // ETH->USDC
        uint24 poolFee = getPoolFeeOfMostLiquidPool(weth, usdc);
        if(poolFee == 0) revert Fiat24CryptoDeposit__NoPoolAvailable(weth, usdc);
        uint256 amountOutMininumUSDC = getQuote(weth, usdc, poolFee, msg.value);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: usdc,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: msg.value,
                amountOutMinimum: amountOutMininumUSDC - (amountOutMininumUSDC * slippage / 100),
                sqrtPriceLimitX96: 0
            });
        uint256 usdcAmount = ISwapRouter(UNISWAP_ROUTER).exactInputSingle{value: msg.value}(params);
        IPeripheryPaymentsWithFee(UNISWAP_PERIPHERY_PAYMENTS).refundETH();
        bool success = payable(_msgSender()).send(address(this).balance);
        if(!success) revert Fiat24CryptoDeposit__EthRefundFailed();

        if(usdcAmount == 0) revert Fiat24CryptoDeposit__SwapOutputAmountZero();
        if(usdcAmount > maxDepositAmount) revert Fiat24CryptoDeposit__UsdcAmountHigherMaxDepositAmount(usdcAmount, maxDepositAmount);

        TransferHelper.safeTransfer(usdc, IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), usdcAmount);
        uint256 totalSpread = marketClosed ? exchangeSpread * marketClosedSpread / 10000 : exchangeSpread;
        uint256 outputAmount = usdcAmount / USDC_DIVISOR * exchangeRates[usd24][_outputToken] / XXX24_DIVISOR * totalSpread / XXX24_DIVISOR;
        TransferHelper.safeTransferFrom(_outputToken, IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), _msgSender(), outputAmount);
        
        emit DepositedEth(_msgSender(), 
                          weth,
                          _outputToken, 
                          msg.value, 
                          outputAmount);
        return outputAmount;
    }

    function depositTokenViaUsdc(address _inputToken, address _outputToken, uint256 _amount) external returns(uint256) {
        if(paused()) revert Fiat24CryptoDeposit__Paused();
        if(_amount == 0) revert Fiat24CryptoDeposit__ValueZero();
        if(!validXXX24Tokens[_outputToken]) revert Fiat24CryptoDeposit__NotValidOutputToken(_outputToken);

        TransferHelper.safeTransferFrom(_inputToken, _msgSender(), address(this), _amount);
        TransferHelper.safeApprove(_inputToken, UNISWAP_ROUTER, _amount);

        uint256 usdcAmount;
        // inputToken->USDC
        if(_inputToken != usdc) {
            uint24 poolFee = getPoolFeeOfMostLiquidPool(_inputToken, usdc);
            if(poolFee == 0) revert Fiat24CryptoDeposit__NoPoolAvailable(_inputToken, usdc);
            uint256 amountOutMininumUSDC = getQuote(_inputToken, usdc, poolFee, _amount);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: _inputToken,
                    tokenOut: usdc,
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: _amount,
                    amountOutMinimum: amountOutMininumUSDC - (amountOutMininumUSDC * slippage / 100),
                    sqrtPriceLimitX96: 0
                });
            usdcAmount = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
        } else {
            usdcAmount = _amount;
        }

        if(usdcAmount == 0) revert Fiat24CryptoDeposit__SwapOutputAmountZero();
        if(usdcAmount > maxDepositAmount) revert Fiat24CryptoDeposit__UsdcAmountHigherMaxDepositAmount(usdcAmount, maxDepositAmount);

        TransferHelper.safeTransfer(usdc, IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), usdcAmount);
        uint256 totalSpread = marketClosed ? exchangeSpread * marketClosedSpread / 10000 : exchangeSpread;
        uint256 outputAmount = usdcAmount / USDC_DIVISOR * exchangeRates[usd24][_outputToken] / XXX24_DIVISOR * totalSpread / XXX24_DIVISOR;
        TransferHelper.safeTransferFrom(_outputToken, IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), _msgSender(), outputAmount);
        
        emit DepositedTokenViaUsd(_msgSender(), 
                                  _inputToken, 
                                  _outputToken, 
                                  _amount, 
                                  outputAmount);
        return outputAmount;
    }

    function depositTokenViaEth(address _inputToken, address _outputToken, uint256 _amount) external returns(uint256) {
        if(paused()) revert Fiat24CryptoDeposit__Paused();
        if(_amount == 0) revert Fiat24CryptoDeposit__ValueZero();
        if(!validXXX24Tokens[_outputToken]) revert Fiat24CryptoDeposit__NotValidOutputToken(_outputToken);

        TransferHelper.safeTransferFrom(_inputToken, _msgSender(), address(this), _amount);
        TransferHelper.safeApprove(_inputToken, UNISWAP_ROUTER, _amount);

        // inputToken->ETH
        uint24 poolFee = getPoolFeeOfMostLiquidPool(_inputToken, weth);
        if(poolFee == 0) revert Fiat24CryptoDeposit__NoPoolAvailable(_inputToken, weth);
        uint256 amountOutMininumETH = getQuote(_inputToken, weth, poolFee, _amount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _inputToken,
                tokenOut: weth,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: _amount,
                amountOutMinimum: amountOutMininumETH - (amountOutMininumETH * slippage / 100),
                sqrtPriceLimitX96: 0
            });
        uint256 outputAmount = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
        if(outputAmount == 0) revert Fiat24CryptoDeposit__SwapOutputAmountZero();

        // ETH->USDC
        TransferHelper.safeApprove(weth, UNISWAP_ROUTER, outputAmount);
        poolFee = getPoolFeeOfMostLiquidPool(weth, usdc);
        if(poolFee == 0) revert Fiat24CryptoDeposit__NoPoolAvailable(weth, usdc);
        uint256 amountOutMininumUSDC = getQuote(weth, usdc, poolFee, outputAmount);
        params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: usdc,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: outputAmount,
                amountOutMinimum: amountOutMininumUSDC - (amountOutMininumUSDC * slippage / 100),
                sqrtPriceLimitX96: 0
            });
        outputAmount = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);

        if(outputAmount == 0) revert Fiat24CryptoDeposit__SwapOutputAmountZero();
        if(outputAmount > maxDepositAmount) revert Fiat24CryptoDeposit__UsdcAmountHigherMaxDepositAmount(outputAmount, maxDepositAmount);

        TransferHelper.safeTransfer(usdc, IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), outputAmount);
        uint256 totalSpread = marketClosed ? exchangeSpread * marketClosedSpread / 10000 : exchangeSpread;
        outputAmount = outputAmount / USDC_DIVISOR * exchangeRates[usd24][_outputToken] / XXX24_DIVISOR * totalSpread / XXX24_DIVISOR;
        TransferHelper.safeTransferFrom(_outputToken, IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), _msgSender(), outputAmount);
        
        emit DepositedTokenViaEth(_msgSender(), 
                                  _inputToken, 
                                  _outputToken, 
                                  _amount, 
                                  outputAmount);
        return outputAmount;
    }

    function moneyExchange(address _inputToken, address _outputToken, uint256 _amount) external returns(uint256) {
        if(paused()) revert Fiat24CryptoDeposit__Paused();
        if(_amount == 0) revert Fiat24CryptoDeposit__ValueZero();
        if(!validXXX24Tokens[_inputToken]) revert Fiat24CryptoDeposit__NotValidInputToken(_inputToken);
        if(!validXXX24Tokens[_outputToken]) revert Fiat24CryptoDeposit__NotValidOutputToken(_outputToken);
        
        if(exchangeRates[_inputToken][_outputToken] == 0 && exchangeRates[_outputToken][_inputToken] == 0) revert Fiat24CryptoDeposit__ExchangeRateNotAvailable(_inputToken, _outputToken);
        uint256 exchangeRate = exchangeRates[_inputToken][_outputToken] == 0 ? 10000**2 / exchangeRates[_inputToken][_outputToken] : exchangeRates[_inputToken][_outputToken];
        uint256 totalSpread = marketClosed ? exchangeSpread * marketClosedSpread / 10000 : exchangeSpread;
        TransferHelper.safeTransferFrom(_inputToken, _msgSender(), IFiat24Account(fiat24account).ownerOf(TREASURY_DESK), _amount);
        uint256 outputAmount = _amount * exchangeRate / XXX24_DIVISOR * totalSpread / XXX24_DIVISOR;
        TransferHelper.safeTransferFrom(_outputToken, IFiat24Account(fiat24account).ownerOf(CRYPTO_DESK), address(this), outputAmount);
        
        emit MoneyExchanged(_msgSender(), 
                            _inputToken, 
                            _outputToken, 
                            _amount, 
                            outputAmount);
        return outputAmount;
    }

    function updateExchangeRates(uint256 _usd_eur, uint256 _usd_chf, uint256 _usd_gbp, bool _isMarketClosed) external {
        if(hasRole(RATES_UPDATER_OPERATOR_ROLE, _msgSender())) {
            exchangeRates[usd24][eur24] = _usd_eur;
            exchangeRates[usd24][chf24] = _usd_chf;
            exchangeRates[usd24][gbp24] = _usd_gbp;
            marketClosed = _isMarketClosed;
            emit ExchangeRatesUpdatedByOperator(_msgSender(), 
                                                exchangeRates[usd24][eur24],
                                                exchangeRates[usd24][chf24], 
                                                exchangeRates[usd24][gbp24], 
                                                marketClosed);
        } else if((hasRole(RATES_UPDATER_ROBOT_ROLE, _msgSender()))) {
            uint256 rateDiff_usd_eur = (exchangeRates[usd24][eur24] > _usd_eur) ? (exchangeRates[usd24][eur24] - _usd_eur) : (_usd_eur - exchangeRates[usd24][eur24]);
            rateDiff_usd_eur = (rateDiff_usd_eur * XXX24_DIVISOR) / exchangeRates[usd24][eur24];
            uint256 rateDiff_usd_chf = (exchangeRates[usd24][chf24] > _usd_chf) ? (exchangeRates[usd24][chf24] - _usd_chf) : (_usd_chf - exchangeRates[usd24][chf24]);
            rateDiff_usd_chf = (rateDiff_usd_chf * XXX24_DIVISOR) / exchangeRates[usd24][chf24];
            uint256 rateDiff_usd_gbp = (exchangeRates[usd24][gbp24] > _usd_gbp) ? (exchangeRates[usd24][gbp24] - _usd_gbp) : (_usd_gbp - exchangeRates[usd24][gbp24]);
            rateDiff_usd_gbp = (rateDiff_usd_gbp * XXX24_DIVISOR) / exchangeRates[usd24][gbp24];
            if(rateDiff_usd_eur < 300) exchangeRates[usd24][eur24] = _usd_eur;
            if(rateDiff_usd_chf < 300) exchangeRates[usd24][chf24] = _usd_chf;
            if(rateDiff_usd_gbp < 300) exchangeRates[usd24][gbp24] = _usd_gbp;
            marketClosed = _isMarketClosed;
            emit ExchangeRatesUpdatedByRobot(_msgSender(), 
                                                exchangeRates[usd24][eur24],
                                                exchangeRates[usd24][chf24], 
                                                exchangeRates[usd24][gbp24], 
                                                marketClosed);
        } else { 
            revert Fiat24CryptoDeposit__NotRateUpdater((_msgSender()));
        }
    }

    function getQuote(address _inputToken, address _outputToken, uint24 _fee, uint256 _amount) public payable returns(uint256) {
        return IQuoter(UNISWAP_QUOTER).quoteExactInputSingle(
            _inputToken,
            _outputToken,
            _fee,
            _amount,
            0
        ); 
    }

    function getPoolFeeOfMostLiquidPool(address _inputToken, address _outputToken) public view returns(uint24) {
        uint24 feeOfMostLiquidPool = 0;
        uint128 highestLiquidity = 0;
        uint128 liquidity;
        IUniswapV3Pool pool;
        address poolAddress = IUniswapV3Factory(UNISWAP_FACTORY).getPool(_inputToken, _outputToken, 100);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 100;
            }
        }
        poolAddress = IUniswapV3Factory(UNISWAP_FACTORY).getPool(_inputToken, _outputToken, 500);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 500;
            }
        }
        poolAddress = IUniswapV3Factory(UNISWAP_FACTORY).getPool(_inputToken, _outputToken, 3000);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 3000;
            }
        }
        poolAddress = IUniswapV3Factory(UNISWAP_FACTORY).getPool(_inputToken, _outputToken, 10000);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 10000;
            }
        }
        return feeOfMostLiquidPool;
    }

    function changeMaxDepositAmount(uint256 _maxDepositAmount) external {
       if(!hasRole(OPERATOR_ROLE, _msgSender())) revert Fiat24CryptoDeposit__NotOperator(_msgSender());
       maxDepositAmount = _maxDepositAmount; 
    }

    function changeSlippage(uint256 _slippage) external {
        if(!hasRole(OPERATOR_ROLE, _msgSender())) revert Fiat24CryptoDeposit__NotOperator(_msgSender());
        slippage = _slippage;
    }

    function changeExchangeSpread(uint256 _exchangeSpread) external {
        if(!hasRole(OPERATOR_ROLE, _msgSender())) revert Fiat24CryptoDeposit__NotOperator(_msgSender());
        exchangeSpread = _exchangeSpread;
    }

    function changeMarketClosedSpread(uint256 _marketClosedSpread) external {
        if(!hasRole(OPERATOR_ROLE, _msgSender())) revert Fiat24CryptoDeposit__NotOperator(_msgSender());
        marketClosedSpread = _marketClosedSpread;
    }

    function pause() public {
        if(!hasRole(OPERATOR_ROLE, _msgSender())) revert Fiat24CryptoDeposit__NotOperator(_msgSender());
        _pause();
    }

    function unpause() public {
        if(!hasRole(OPERATOR_ROLE, _msgSender())) revert Fiat24CryptoDeposit__NotOperator(_msgSender());
        _unpause();
    }

    receive() payable external {}
}
