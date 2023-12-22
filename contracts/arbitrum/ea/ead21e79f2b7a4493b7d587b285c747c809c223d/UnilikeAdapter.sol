// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./IUnilikeFactory.sol";
import "./IUnilikePair.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Adapter.sol";

contract UnilikeAdapter is Adapter {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes32 public constant ID = keccak256("UnilikeAdapter");
    uint256 internal constant FEE_DENOMINATOR = 1e3;
    uint256 public immutable feeCompliment;
    address public immutable factory;

    constructor(
        string memory _name,
        address _factory,
        uint256 _fee,
        uint256 _swapGasEstimate,
        address payable _weth
    ) public {
        require(
            FEE_DENOMINATOR > _fee,
            "UnilikeAdapter: Fee greater than the denominator"
        );
        factory = _factory;
        name = _name;
        feeCompliment = FEE_DENOMINATOR.sub(_fee);
        setSwapGasEstimate(_swapGasEstimate);
        WGAS = _weth;
        setAllowances();
    }

    function setAllowances() public override onlyOwner {
        IERC20(WGAS).safeApprove(WGAS, UINT_MAX);
    }

    function _approveIfNeeded(address tokenIn, uint256 amount)
        internal
        override
    {}

    function _getAmountOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) internal view returns (uint256 amountOut) {
        // Based on https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/UniswapV2Router02.sol
        uint256 amountInWithFee = _amountIn.mul(feeCompliment);
        uint256 numerator = amountInWithFee.mul(_reserveOut);
        uint256 denominator = _reserveIn.mul(FEE_DENOMINATOR).add(
            amountInWithFee
        );
        amountOut = numerator / denominator;
    }

    function _query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view override returns (uint256) {
        if (_tokenIn == _tokenOut || _amountIn == 0) {
            return 0;
        }
        address pair = IUnilikeFactory(factory).getPair(_tokenIn, _tokenOut);
        if (pair == address(0)) {
            return 0;
        }
        (uint256 r0, uint256 r1, ) = IUnilikePair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = _tokenIn < _tokenOut
            ? (r0, r1)
            : (r1, r0);
        if (reserveIn > 0 && reserveOut > 0) {
            return _getAmountOut(_amountIn, reserveIn, reserveOut);
        }
    }

    function _swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address _tokenIn,
        address _tokenOut,
        address to
    ) internal override {
        address pair = IUnilikeFactory(factory).getPair(_tokenIn, _tokenOut);
        (uint256 amount0Out, uint256 amount1Out) = (_tokenIn < _tokenOut)
            ? (uint256(0), _amountOut)
            : (_amountOut, uint256(0));
        IERC20(_tokenIn).safeTransfer(pair, _amountIn);
        IUnilikePair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }
}

