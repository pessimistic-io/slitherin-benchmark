// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IUniswapV3Pool.sol";
import "./TransferHelper.sol";

import "./Math.sol";
import "./FullMath.sol";
import "./Constants.sol";
import "./Events.sol";
import "./IAsymptoticPerpetual.sol";
import "./IERC1155Supply.sol";
import "./IHelper.sol";
import "./IPool.sol";
import "./IPoolFactory.sol";
import "./IWeth.sol";

contract Helper is Constants, IHelper, Events {
    uint internal constant SIDE_NATIVE = 0x000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;
    uint constant MAX_IN = 0;
    address internal immutable TOKEN;
    address internal immutable WETH;

    constructor(address token, address weth) {
        TOKEN = token;
        WETH = weth;
    }

    struct SwapParams {
        uint sideIn;
        address poolIn;
        uint sideOut;
        address poolOut;
        uint amountIn;
        address payer;
        address recipient;
    }

    function _packID(address pool, uint side) internal pure returns (uint id) {
        id = (side << 160) + uint160(pool);
    }

    // v(r)
    function _v(uint xk, uint r, uint R) internal pure returns (uint v) {
        if (r <= R >> 1) {
            return FullMath.mulDivRoundingUp(r, Q128, xk);
        }
        // TODO: denominator should be rounding up or down?
        uint denominator = FullMath.mulDiv(R - r, xk << 2, Q128);
        return FullMath.mulDivRoundingUp(R, R, denominator);
    }

    function _supply(uint side) internal view returns (uint s) {
        return IERC1155Supply(TOKEN).totalSupply(_packID(msg.sender, side));
    }

    function createPool(Params memory params, address factory) external payable returns (address pool) {
        IWeth(WETH).deposit{value : msg.value}();
        uint amount = IWeth(WETH).balanceOf(address(this));
        address poolAddress = IPoolFactory(factory).computePoolAddress(params);
        IWeth(WETH).transfer(poolAddress, amount);

        pool = IPoolFactory(factory).createPool(params);
    }

    function _swapMultiPool(SwapParams memory params, address TOKEN_R) internal returns (uint amountOut) {
        // swap poolIn/sideIn to poolIn/R
        bytes memory payload = abi.encode(
            uint(0),
            params.sideIn,
            SIDE_R,
            params.amountIn
        );

        (, amountOut) = IPool(params.poolIn).swap(
            params.sideIn,
            SIDE_R,
            address(this),
            payload,
            params.payer,
            address(this)
        );

        // TOKEN_R approve poolOut
        IERC20(TOKEN_R).approve(params.poolOut, amountOut);

        // swap (poolIn|PoolOut)/R to poolOut/SideOut
        payload = abi.encode(
            uint(0),
            SIDE_R,
            params.sideOut,
            amountOut
        );
        (, amountOut) = IPool(params.poolOut).swap(
            SIDE_R,
            params.sideOut,
            address(this),
            payload,
            address(0),
            params.recipient
        );

        // check leftOver
        uint leftOver = IERC20(TOKEN_R).balanceOf(address(this));
        if (leftOver > 0) {
            TransferHelper.safeTransfer(TOKEN_R, params.payer, leftOver);
        }

        emit Derivable(
            'Swap', // topic1: eventName
            bytes32(_addressToBytes32(params.poolIn)), // topic2: poolIn
            bytes32(_addressToBytes32(params.poolOut)), // topic3: poolOut
            abi.encode(SwapEvent(
                params.sideIn,
                params.sideOut,
                params.amountIn,
                amountOut,
                params.payer,
                params.recipient
            ))
        );
    }

    function swap(SwapParams memory params) external payable returns (uint amountOut){
        SwapParams memory _params = params;
        address TOKEN_R = IPool(params.poolIn).TOKEN_R();
        if (params.poolIn != params.poolOut) {
            amountOut = _swapMultiPool(params, TOKEN_R);
            return amountOut;
        }

        if (params.sideIn == SIDE_NATIVE) {
            require(TOKEN_R == WETH, 'Reserve token is not Wrapped');
            require(msg.value != 0, 'Value need > 0');
            IWeth(WETH).deposit{value : msg.value}();
            uint amount = IWeth(WETH).balanceOf(address(this));
            IERC20(WETH).approve(params.poolIn, amount);
            params.payer = address(0);
            params.sideIn = SIDE_R;
        }

        if (params.sideOut == SIDE_NATIVE) {
            require(TOKEN_R == WETH, 'Reserve token is not Wrapped');
            params.sideOut = SIDE_R;
            params.recipient = address(this);
        }

        bytes memory payload = abi.encode(
            uint(0),
            params.sideIn,
            params.sideOut,
            params.amountIn
        );

        (, amountOut) = IPool(params.poolIn).swap(
            params.sideIn,
            params.sideOut,
            address(this),
            payload,
            params.payer,
            params.recipient
        );

        if (_params.sideOut == SIDE_NATIVE) {
            amountOut = IERC20(TOKEN_R).balanceOf(address(this));
            IWeth(WETH).withdraw(amountOut);
            payable(_params.recipient).transfer(amountOut);
        }

        emit Derivable(
            'Swap', // topic1: eventName
            bytes32(_addressToBytes32(_params.poolIn)), // topic2: poolIn
            bytes32(_addressToBytes32(_params.poolOut)), // topic3: poolOut
            abi.encode(SwapEvent(
                _params.sideIn,
                _params.sideOut,
                _params.amountIn,
                amountOut,
                _params.payer,
                _params.recipient
            ))
        );
    }

    function unpackId(uint id) pure public returns (uint, address) {
        uint k = id >> 160;
        address p = address(uint160(uint256(id - k)));
        return (k, p);
    }

    function swapToState(
        Market calldata market,
        State calldata state,
        uint rA,
        uint rB,
        bytes calldata payload
    ) external view override returns (State memory state1) {
        (
        uint swapType,
        uint sideIn,
        uint sideOut,
        uint amount
        ) = abi.decode(payload, (uint, uint, uint, uint));
        require(swapType == MAX_IN, 'Helper: UNSUPPORTED_SWAP_TYPE');
        state1 = State(state.R, state.a, state.b);
        if (sideIn == SIDE_R) {
            state1.R += amount;
            if (sideOut == SIDE_A) {
                state1.a = _v(market.xkA, rA + amount, state1.R);
            } else if (sideOut == SIDE_B) {
                state1.b = _v(market.xkB, rB + amount, state1.R);
            }
        } else {
            uint s = _supply(sideIn);

            if (sideIn == SIDE_A) {
                uint rOut = FullMath.mulDiv(rA, amount, s);
                if (sideOut == SIDE_R) {
                    state1.R -= rOut;
                }
                state1.a = _v(market.xkA, rA - rOut, state1.R);
            } else if (sideIn == SIDE_B) {
                uint rOut = FullMath.mulDiv(rB, amount, s);
                if (sideOut == SIDE_R) {
                    state1.R -= rOut;
                }
                state1.b = _v(market.xkB, rB - rOut, state1.R);
            } else /*if (sideIn == SIDE_C)*/ {
                if (sideOut == SIDE_R) {
                    uint rC = state.R - rA - rB;
                    uint rOut = FullMath.mulDiv(rC, amount, s);
                    state1.R -= rOut;
                }
                // state1.c
            }
        }
    }
}

