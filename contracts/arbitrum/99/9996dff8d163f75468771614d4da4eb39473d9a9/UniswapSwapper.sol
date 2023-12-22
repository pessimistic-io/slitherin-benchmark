// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Pausable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3PoolState.sol";
import "./ReentrancyGuard.sol";
import "./ISwapper.sol";
import "./FullMath.sol";
// import "hardhat/console.sol";


contract UniswapSwapper is Pausable, AccessControl, ReentrancyGuard, ISwapper {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BLACKLISTED_USER_ROLE = keccak256("BLACKLISTED_USER_ROLE");
    bytes32 public constant TEST_SWAPPER_ROLE = keccak256("TEST_SWAPPER_ROLE");

    address public constant uniswapSwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant uniswapPoolFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    mapping (address => mapping (address => uint24) ) public registeredPoolFees;

    mapping (address => mapping (address => address[]) ) public registeredSwapPaths;
    function fillDefaultPools() private {
        address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        address wstETH = 0x5979D7b546E38E414F7E9822514be443A4800529;

        // WETH / USDC
        registerUniswapPool(WETH, USDC, 500); //works

        // WBTC / WETH
        registerUniswapPool(WBTC, WETH, 500); //works

        // WETH / USDT
        registerUniswapPool(WETH, USDT, 500); //works

        // USDC / USDT
        registerUniswapPool(USDC, USDT, 100); //works

        registerUniswapPool(wstETH, WETH, 100);


        // WETH
        registeredSwapPaths[WETH][USDT].push(USDT);

        registeredSwapPaths[WETH][WBTC].push(WBTC);

        registeredSwapPaths[WETH][USDC].push(USDC);

        registeredSwapPaths[WETH][wstETH].push(wstETH);


        // USDT
        registeredSwapPaths[USDT][WETH].push(WETH);

        registeredSwapPaths[USDT][USDC].push(USDC);

        registeredSwapPaths[USDT][WBTC].push(WETH);
        registeredSwapPaths[USDT][WBTC].push(WBTC);

        registeredSwapPaths[USDT][wstETH].push(WETH);
        registeredSwapPaths[USDT][wstETH].push(wstETH);

        // USDC
        registeredSwapPaths[USDC][WETH].push(WETH);

        registeredSwapPaths[USDC][USDT].push(USDT);

        registeredSwapPaths[USDC][WBTC].push(WETH);
        registeredSwapPaths[USDC][WBTC].push(WBTC);

        registeredSwapPaths[USDC][wstETH].push(WETH);
        registeredSwapPaths[USDC][wstETH].push(wstETH);

        // WBTC
        registeredSwapPaths[WBTC][WETH].push(WETH);

        registeredSwapPaths[WBTC][USDC].push(WETH);
        registeredSwapPaths[WBTC][USDC].push(USDC);

        registeredSwapPaths[WBTC][USDT].push(WETH);
        registeredSwapPaths[WBTC][USDT].push(USDT);

        registeredSwapPaths[WBTC][wstETH].push(WETH);
        registeredSwapPaths[WBTC][wstETH].push(wstETH);

        // wstETH
        registeredSwapPaths[wstETH][WETH].push(WETH);

        registeredSwapPaths[wstETH][USDC].push(WETH);
        registeredSwapPaths[wstETH][USDC].push(USDC);

        registeredSwapPaths[wstETH][USDT].push(WETH);
        registeredSwapPaths[wstETH][USDT].push(USDT);

        registeredSwapPaths[wstETH][WBTC].push(WETH);
        registeredSwapPaths[wstETH][WBTC].push(WBTC);
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        fillDefaultPools();
    }
    
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    error UnknownPool(address token0, address token1);
    error UnknownPath(address token0, address token1);


    function registerUniswapPool(address token1, address token2, uint24 fee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(uint160(token1) > uint160(token2)) {
            (token1, token2) = (token2, token1);
        }
        //check uniswap factory here to unsure that we have a pool deployed
        if(IUniswapV3Factory(uniswapPoolFactory).getPool(token1, token2, fee) == address(0)) {
            revert UnknownPool(token1, token2);
        }
        registeredPoolFees[token1][token2] = fee;
    }

    function registerUniswapSwapPath(address token1, address token2, address[] calldata path) public onlyRole(DEFAULT_ADMIN_ROLE) {
        registeredSwapPaths[token1][token2] = path;
    }

    function findSwapPath(address tokenFrom, address tokenTo) public view returns (address[] memory ret){
        return registeredSwapPaths[tokenFrom][tokenTo];
    }

    function swapReceiveExact(address tokenFrom, address tokenTo, uint256 amount, uint256 maxSpendAmount) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256)  {
        return _swap(tokenFrom, tokenTo, amount, maxSpendAmount, true);
    }

    function swapSendExact(address tokenFrom, address tokenTo, uint256 amount, uint256 minReceiveAmount) public onlyRole(DEFAULT_ADMIN_ROLE)  returns (uint256) {
        return _swap(tokenFrom, tokenTo, amount, minReceiveAmount, false);
    }

    function _swap(address tokenFrom, address tokenTo, uint256 amount, uint256 limitAmount, bool trueIfExactOutput) private nonReentrant() returns (uint256)  {
        address payerAddress = msg.sender;

        uint256 value;
        if(!trueIfExactOutput) {
            value = amount;
        } else {
            value = limitAmount;
        }
        SafeERC20.safeTransferFrom(IERC20(tokenFrom), payerAddress, address(this), value);
        

        address[] memory pathConfig  = findSwapPath(tokenFrom, tokenTo);
        if(pathConfig.length == 0) {
            revert UnknownPath(tokenFrom, tokenTo);
        }

        bytes memory path = abi.encodePacked(tokenFrom);
        address prevToken = tokenFrom;
        for(uint i = 0; i < pathConfig.length; i ++) {
            address tokenToAppend = pathConfig[i];
            
            uint24 fee = uint160(prevToken) > uint160(tokenToAppend) ? registeredPoolFees[tokenToAppend][prevToken] : registeredPoolFees[prevToken][tokenToAppend];
            if(fee == 0) {
                revert UnknownPool(tokenFrom, tokenToAppend);
            }
            path = abi.encodePacked(path, fee, tokenToAppend);
            prevToken = tokenToAppend;
        }
        

        if(!trueIfExactOutput) {
            ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: payerAddress,
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: limitAmount
            });
            
            SafeERC20.safeApprove(IERC20(tokenFrom), address(uniswapSwapRouter), amount);
            
            return ISwapRouter(uniswapSwapRouter).exactInput(params);
        } else {
            ISwapRouter.ExactOutputParams memory params =
            ISwapRouter.ExactOutputParams({
                path: path,
                recipient: payerAddress,
                deadline: block.timestamp,
                amountOut: amount,
                amountInMaximum: limitAmount
            });
            
            SafeERC20.safeApprove(IERC20(tokenFrom), address(uniswapSwapRouter), limitAmount);
            uint256 inputAmount = ISwapRouter(uniswapSwapRouter).exactOutput(params);

            
            uint256 delta = limitAmount - inputAmount;
            if(delta > 0) {
                SafeERC20.safeTransfer(IERC20(tokenFrom), payerAddress, delta);
            }
            
            return inputAmount;
        }
    }
    function getPriceSingle(address tokenFrom, address tokenTo, uint128 amount) view public returns (uint256) {

        
        uint24 fee = uint160(tokenFrom) > uint160(tokenTo) ? registeredPoolFees[tokenTo][tokenFrom] : registeredPoolFees[tokenFrom][tokenTo];
        if(fee == 0) {
            revert UnknownPool(tokenFrom, tokenTo);
        }
        address poolAddress = IUniswapV3Factory(uniswapPoolFactory).getPool(tokenFrom, tokenTo, fee);
        if(poolAddress == address(0)) {
            revert UnknownPool(tokenFrom, tokenTo);
        }
        IUniswapV3PoolState pool = IUniswapV3PoolState(poolAddress);
        (uint160 sqrtPriceX96, , , , , ,) = pool.slot0();

        bool inverse = uint160(tokenFrom) > uint160(tokenTo);

        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return !inverse
                ? FullMath.mulDiv(ratioX192, amount, 1 << 192)
                : FullMath.mulDiv(1 << 192, amount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtPriceX96,
                sqrtPriceX96,
                1 << 64
            );
            return !inverse
                ? FullMath.mulDiv(ratioX128, amount, 1 << 128)
                : FullMath.mulDiv(1 << 128, amount, ratioX128);
        }
    }
    function getPrice(address tokenFrom, address tokenTo, uint128 amount) view public returns (uint128) {
        address[] memory pathConfig  = findSwapPath(tokenFrom, tokenTo);
        if(pathConfig.length == 0) {
            revert UnknownPath(tokenFrom, tokenTo);
        }

        address prevToken = tokenFrom;
        uint128 prevConvertedAmount = amount;
        for(uint i = 0; i < pathConfig.length; i ++) {
            address tokenToConvertTo = pathConfig[i];
            
            uint256 r = getPriceSingle(prevToken, tokenToConvertTo, prevConvertedAmount);
            require(r < type(uint128).max);
            prevConvertedAmount = uint128(r);
            prevToken = tokenToConvertTo;
        }

        return uint128(prevConvertedAmount);
    }
}


