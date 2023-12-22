// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

// propose pools to users according to their balances on front-end
// change router into allowancetarget to be more parametric in case router changes
// add withdraw functions to withdraw any balance left (ETH and ERC20)

// solidly : change ISwapPair

import "./ISwapPair.sol";
import "./SwapPair.sol";
import "./Babylonian.sol";
//import "@openzeppelin/contracts/Math/SafeMath.sol";

interface IRouter {
    function WETH() external returns (address);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}


interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint amount) external returns (bool success);
}

contract Zap {

    //using SafeMath for uint256;

    address public immutable router;
    address public immutable factory;

    constructor(address _router, address _factory) {
        router = _router;
        factory = _factory;
    }

    event zappedOut(address indexed _zapper, address indexed _pool, address indexed _token, uint256 _amountOut);
    event zappedIn(address indexed _zapper, address indexed _pool, address indexed _token, uint256 _poolTokens );
    



    // ***** ZAP METHODS *****

    /// @notice Zap a token or ETH into a predetermined pool
    /// @param _token           The token to zap
    /// @param _amount          The amount of token to zap
    /// @param _pool            The pool to zap into
    /// @param _minPoolTokens   The minimum amount of LP tokens the user agrees to receive
    /// @param _swapData        Data to be passed to each swap. Calculated on front-end according to caller's choice
    /// @return poolTokens  The amount of LP tokens received by the caller 
    function zapIn(
        address _token,
        uint256 _amount,
        address _pool,
        uint256 _minPoolTokens,
        bytes memory _swapData
    ) public virtual payable returns (uint256 poolTokens) {
        uint256 toInvest_;

        if (_token == address(0)) {
            require(msg.value > 0, "no ETH sent");
            toInvest_ = msg.value;
        } else {
            require(msg.value == 0, "ETH sent");
            require(_amount > 0, "invalid amount");
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
            toInvest_ = _amount;
        }

        (address token0_, address token1_) = _getTokens(_pool);

        address tempToken_;
        uint256 tempAmount_;
        if (_token != token0_ && _token != token1_) {
            (tempToken_, tempAmount_) = _swapIn(
                _token,
                _pool,
                toInvest_,
                _swapData
                ); 
        } else {
            (tempToken_, tempAmount_) = (_token, _amount);
        }

        (uint256 amount0_, uint256 amount1_) = _swapOptimalAmount(
            tempToken_,
            token0_,
            token1_,
            tempAmount_
            );
        poolTokens = _provideLiquidity(
            token0_,
            token1_,
            amount0_,
            amount1_
            );
        require(poolTokens >= _minPoolTokens, "not enough LP tokens received");
        emit zappedIn(msg.sender, _pool, _token, poolTokens);
    }

    /// @notice Unzap from predetermined pool to a token or ETH
    /// @param _tokenOut        The token to unzap to
    /// @param _pool            The pool to unzap from
    /// @param _poolTokens      The amount of LP tokens the caller wants to burn
    /// @param _amountOutMin    The minimum amount of tokens the caller agrees to receive
    /// @param _swapData        An array of data to be passed to each swap. Calculated on front-end according to caller's choice
    /// @return amountOut The amount of tokens received
    function zapOut(
        address _tokenOut,
        address _pool,
        uint256 _poolTokens,
        uint256 _amountOutMin,
        bytes[] memory _swapData
    ) public virtual returns (uint amountOut) {
        (uint256 amount0_, uint256 amount1_) = _withdrawLiquidity(_pool, _poolTokens);
        amountOut = _swapTokens(
            _pool,
            amount0_,
            amount1_,
            _tokenOut,
            _swapData
            );
        require(amountOut >= _amountOutMin, "high slippage");

        if (_tokenOut == address(0)) {
            payable(msg.sender).transfer(amountOut);
        } else {
            IERC20(_tokenOut).transfer(msg.sender, amountOut);
        }
        emit zappedOut(msg.sender, _pool, _tokenOut, amountOut);
    }

    
    // ***** INTERNAL *****

    function _getTokens(address _pool) internal view returns (address token0, address token1) {
        ISwapPair pool_ = ISwapPair(_pool);
        (token0, token1) = pool_.tokens();
    }

    function _getOptimalAmount(uint r, uint a) internal pure returns (uint) {
        return (Babylonian.sqrt(r * (r * 398920729 + a * 398920000)) - r * (19973)) / 19946;
    }

    function _swapOptimalAmount(
        address _tokenIn,
        address _token0,
        address _token1,
        uint256 _amount
    ) internal returns (uint256 amount0, uint256 amount1) {
        ISwapPair pair = ISwapPair(IFactory(factory).getPair(_token0, _token1));
        (uint256 reserve0_, uint256 reserve1_, ) = pair.getReserves();
        if (_tokenIn == _token0) {
            uint256 optimalAmount = _getOptimalAmount(reserve0_, _amount);
            if (optimalAmount <= 0) {
                // If no reserve or a new pair is created
                optimalAmount = _amount / 2;
                amount0 = _swapTokensForTokens(
                    _tokenIn,
                    _token1,
                    optimalAmount
                    );
            amount0 = _amount - optimalAmount;
            }
        } else {
            uint256 optimalAmount = _getOptimalAmount(reserve1_, _amount);
            if (optimalAmount <= 0) {
                // If no reserve or a new pair is created
                optimalAmount = _amount / 2;
                amount1 = _swapTokensForTokens(
                    _tokenIn,
                    _token0,
                    optimalAmount
                    );
            amount1 = _amount - optimalAmount;
            }
        }
    }

    function _swapIn(
        address _token,
        address _pool,
        uint256 _amount,
        bytes memory _swapData
    ) internal returns (address tokenOut, uint256 amountOut) {
        uint256 value_;
        IERC20 token_ = IERC20(_token);
        if (_token == address(0)) {
            value_ = _amount;
        } else {
            token_.approve(address(router), 0);
            token_.approve(address(router), _amount);
        }
        (address token0_, address token1_) = _getTokens(_pool);
        IERC20 token0 = IERC20(token0_);
        uint256 preBalance0 = token0.balanceOf(address(this));
        // _to parameter in _swapData MUST be set to the address of this contract
        (bool success, bytes memory data) = address(router).call{value: value_}(_swapData);
        require(success, "error swapping");
        uint256[] memory out = abi.decode(data, (uint256[]));
        amountOut = out[out.length - 1];
        require(amountOut > 0, "error swapping");
        uint256 postBalance0 = token0.balanceOf(address(this));
        preBalance0 != postBalance0 ? tokenOut = token0_ : tokenOut = token1_;
    }

    function _swapOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        bytes memory _swapData
    ) internal returns (uint256 amountOut) {
        if (_tokenIn == IRouter(router).WETH() && _tokenOut == address(0)) {
            IWETH(IRouter(router).WETH()).withdraw(_amount);
            return _amount;
        }
        uint256 value_;
        if (_tokenIn == address(0)) {
            value_ = _amount;
        } else {
            IERC20(_tokenIn).approve(address(router), _amount);
        }
        uint256 preBalance = IERC20(_tokenOut).balanceOf(address(this));

        (bool success, ) = address(router).call{value: value_}(_swapData);
        require(success, "error swapping tokens");

        amountOut = IERC20(_tokenOut).balanceOf(address(this)) - preBalance;
        require(amountOut > 0, "wapped to Invalid Intermediate");
    }

    function _swapTokens(
        address _pool,
        uint256 _amount0,
        uint256 _amount1,
        address _tokenOut,
        bytes[] memory _swapData
    ) internal returns (uint256 amountOut) {
        (address token0_, address token1_) = _getTokens(_pool);
        if (token0_ == _tokenOut) {
            amountOut = amountOut + _amount0;
        } else {
            amountOut = amountOut + _swapOut(
                token0_,
                _tokenOut,
                _amount0,
                _swapData[0]
                );
        }

        if (token1_ == _tokenOut) {
            amountOut = amountOut + _amount1;
        } else {
            amountOut = amountOut + _swapOut(
                token1_,
                _tokenOut,
                _amount1,
                _swapData[1]
                );
        }
    }

    function _swapTokensForTokens(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) internal returns (uint256 amountOut) {
        require(_tokenIn != _tokenOut, "tokens are the same");
        require(IFactory(factory).getPair(_tokenIn, _tokenOut) != address(0), "pair does not exist");
        IERC20(_tokenIn).approve(address(router), 0);
        IERC20(_tokenIn).approve(address(router), _amount);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        amountOut = IRouter(router).swapExactTokensForTokens(
            _amount,
            1,
            path,
            address(this),
            block.timestamp
        )[path.length - 1];
        require(amountOut > 0, "error swapping");
    }

    function _provideLiquidity(
        address _token0,
        address _token1,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256) {
        IERC20(_token0).approve(address(router), 0);
        IERC20(_token1).approve(address(router), 0);
        IERC20(_token0).approve(address(router), _amount0);
        IERC20(_token1).approve(address(router), _amount1);
        (uint256 amountA, uint256 amountB, uint256 poolTokens) = IRouter(router).addLiquidity(
            _token0,
            _token1,
            _amount0,
            _amount1,
            1,
            1,
            msg.sender,
            block.timestamp
        );
        // Returning Residue in token0, if any
        if (_amount0 - amountA > 0) {
            IERC20(_token0).transfer(msg.sender, _amount0 - amountA);
        }
        // Returning Residue in token1, if any
        if (_amount1 - amountB > 0) {
            IERC20(_token1).transfer(msg.sender, _amount1 - amountB);
        }
        return poolTokens;
    }

    function _withdrawLiquidity(
        address _pool,
        uint256 _poolTokens
    ) internal returns (uint256 amount0, uint256 amount1) {
        require(_pool != address(0), "this pool does not exist");
        (address token0_, address token1_) = _getTokens(_pool);
        IERC20(_pool).approve(router, _poolTokens);
        (amount0, amount1) = IRouter(router).removeLiquidity(
            token0_,
            token1_,
            _poolTokens,
            1,
            1,
            address(this),
            block.timestamp
        );
        require(amount0 > 0 && amount1 > 0, "removed insufficient liquidity");
    }

    function withdraw() public {
    }
}

