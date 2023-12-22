// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./IUniswapV2ERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";

import "./Ownable.sol";

// This contract handles "serving up" rewards for xCell holders 
// by trading tokens collected from fees for Cell.
// devCut basis points aka parts are calculated as 1 per 10,000 so 5000 equals 50%

contract Scientist is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public immutable factory;

    address public immutable researchfacility;
    address private immutable govToken;
    address private immutable weth;
    uint256 public devCut = 0;
    address public devAddr;

    mapping(address => bool) public isAuth;
    address[] public authorized;
    bool public anyAuth = false;

    modifier onlyAuth() {
        require(isAuth[msg.sender] || anyAuth, "Scientist: FORBIDDEN");
        _;
    }

    mapping(address => address) internal _bridges;

    event SetDevAddr(address _addr);
    event SetDevCut(uint256 _amount);
    event SetSwapFee(uint256 _amount);
    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountGovToken
    );

    constructor(
        address _factory,
        address _researchfacility,
        address _govToken,
        address _weth
    ) public {
        factory = IUniswapV2Factory(_factory);
        researchfacility = _researchfacility;
        govToken = _govToken;
        weth = _weth;
        devAddr = msg.sender;
        isAuth[msg.sender] = true;
        authorized.push(msg.sender);
    }

    function addAuth(address _auth) external onlyOwner {
        isAuth[_auth] = true;
        authorized.push(_auth);
    }

    function revokeAuth(address _auth) external onlyOwner {
        isAuth[_auth] = false;
    }

    function setAnyAuth(bool access) external onlyOwner {
        anyAuth = access;
    }

    function setBridge(address token, address bridge) external onlyOwner {
        require(token != govToken && token != weth && token != bridge, "Scientist: Invalid bridge");

        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    function setDevCut(uint256 _amount) external onlyOwner {
        require(_amount <= 5000, "setDevCut: cut too high");
        devCut = _amount;

        emit SetDevCut(_amount);
    }

    function setDevAddr(address _addr) external onlyOwner {
        require(_addr != address(0), "setDevAddr, address cannot be zero address");
        devAddr = _addr;

        emit SetDevAddr(_addr);
    }
    
    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Scientist: must use EOA");
        _;
    }

    function convert(address token0, address token1) external onlyEOA onlyAuth {
        _convert(token0, token1);
    }

    function convertMultiple(address[] calldata token0, address[] calldata token1) external onlyEOA onlyAuth {
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    function _convert(address token0, address token1) internal {
        uint256 amount0;
        uint256 amount1;

        if (token0 == token1) {
            amount0 = IERC20(token0).balanceOf(address(this));
            amount1 = 0;
        } else {
            IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
            require(address(pair) != address(0), "Scientist: Invalid pair");

            IERC20(address(pair)).safeTransfer(address(pair), pair.balanceOf(address(this)));

            uint256 tok0bal = IERC20(token0).balanceOf(address(this));
            uint256 tok1bal = IERC20(token1).balanceOf(address(this));

            pair.burn(address(this));

            amount0 = IERC20(token0).balanceOf(address(this)).sub(tok0bal);
            amount1 = IERC20(token1).balanceOf(address(this)).sub(tok1bal);
        }
        emit LogConvert(msg.sender, token0, token1, amount0, amount1, _convertStep(token0, token1, amount0, amount1));
    }

    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 govTokenOut) {
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == govToken) {
                IERC20(govToken).safeTransfer(researchfacility, amount);
                govTokenOut = amount;
            } else if (token0 == weth) {
                govTokenOut = _toGovToken(weth, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                govTokenOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == govToken) {
            IERC20(govToken).safeTransfer(researchfacility, amount0);
            govTokenOut = _toGovToken(token1, amount1).add(amount0);
        } else if (token1 == govToken) {
            IERC20(govToken).safeTransfer(researchfacility, amount1);
            govTokenOut = _toGovToken(token0, amount0).add(amount1);
        } else if (token0 == weth) {
            govTokenOut = _toGovToken(weth, _swap(token1, weth, amount1, address(this)).add(amount0));
        } else if (token1 == weth) {
            govTokenOut = _toGovToken(weth, _swap(token0, weth, amount0, address(this)).add(amount1));
        } else {
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                govTokenOut = _convertStep(bridge0, token1, _swap(token0, bridge0, amount0, address(this)), amount1);
            } else if (bridge1 == token0) {
                govTokenOut = _convertStep(token0, bridge1, amount0, _swap(token1, bridge1, amount1, address(this)));
            } else {
                govTokenOut = _convertStep(
                    bridge0,
                    bridge1,
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "Scientist: Cannot convert");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveInput, uint256 reserveOutput) = fromToken == pair.token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        IERC20(fromToken).safeTransfer(address(pair), amountIn);
        uint256 amountInput = IERC20(fromToken).balanceOf(address(pair)).sub(reserveInput);
        
        amountOut = getAmountOut(amountInput, reserveInput, reserveOutput);
        (uint256 amount0Out, uint256 amount1Out) = fromToken == pair.token0()
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        pair.swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _toGovToken(address token, uint256 amountIn) internal returns (uint256 amountOut) {
        uint256 amount = amountIn;
        if (devCut > 0) {
            amount = amount.mul(devCut).div(10000);
            IERC20(token).safeTransfer(devAddr, amount);
            amount = amountIn.sub(amount);
        }
        amountOut = _swap(token, govToken, amount, researchfacility);
    }
    
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "Scientist: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Scientist: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}
