//SPDX-License-Identifier: ISC

pragma solidity 0.8.17;

import "./UniswapAdapter.sol";
import "./SushiAdapter.sol";
import "./XCaliburAdapter.sol";
import "./StargateArbitrum.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {CamelotAdapter} from "./CamelotAdapter.sol";
import {IWETH9} from "./IWETH9.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IArbitrumSwaps} from "./IArbitrumSwaps.sol";

contract ArbitrumSwaps is
    UniswapAdapter,
    SushiAdapter,
    XCaliburAdapter,
    StargateArbitrum,
    CamelotAdapter,
    IArbitrumSwaps
{
    using SafeERC20 for IERC20;

    error MoreThanZero();
    error WithdrawFailed();
    error InvaldStep();

    event FeePaid(address _token, uint256 _fee);

    IWETH9 internal immutable weth;
    address public feeCollector;

    uint8 private locked = 1;

    modifier lock() {
        require(locked == 1, "REENTRANCY");
        locked = 2;
        _;
        locked = 1;
    }

    struct SrcTransferParams {
        address token;
        address receiver;
        uint256 amount;
    }

    //Constants

    uint8 internal constant BATCH_DEPOSIT = 1;
    uint8 internal constant WETH_DEPOSIT = 2;
    uint8 internal constant UNI_SINGLE = 3;
    uint8 internal constant UNI_MULTI = 4;
    uint8 internal constant SUSHI_LEGACY = 5;
    uint8 internal constant XCAL = 6;
    uint8 internal constant CAMELOT = 7;
    uint8 internal constant WETH_WITHDRAW = 13;
    uint8 internal constant SRC_TRANSFER = 14;
    uint8 internal constant STARGATE = 15;

    constructor(
        address _weth,
        ISwapRouter _swapRouter,
        address _feeCollector,
        address _factory,
        bytes32 _pairCodeHash,
        address _xcalFactory,
        address _camelotRouter,
        IStargateRouter _stargateRouter
    )
        UniswapAdapter(_swapRouter)
        SushiAdapter(_factory, _pairCodeHash)
        XCaliburAdapter(_xcalFactory, _weth)
        CamelotAdapter(_camelotRouter)
        StargateArbitrum(_stargateRouter)
    {
        weth = IWETH9(_weth);
        feeCollector = _feeCollector;
    }
    ///@param steps the steps taken to accomplish the necessary desired actions for the transaction. Available steps are listed above.
    ///@param data the necessary data that goes with each transaction.

    function arbitrumSwaps(uint8[] calldata steps, bytes[] calldata data) external payable override lock {
        if (steps.length != data.length) revert MismatchedLengths();
        for (uint256 i; i < steps.length; i++) {
            uint8 step = steps[i];
            if (step == BATCH_DEPOSIT) {
                (address[] memory tokens, uint256[] memory amounts) = abi.decode(data[i], (address[], uint256[]));

                for (uint256 j; j < tokens.length; j++) {
                    if (amounts[j] <= 0) revert MoreThanZero();
                    IERC20(tokens[j]).safeTransferFrom(msg.sender, address(this), amounts[j]);
                }
            } else if (step == WETH_DEPOSIT) {
                uint256 _amount = abi.decode(data[i], (uint256));
                if (_amount == 0) revert MoreThanZero();
                weth.deposit{value: _amount}();
            } else if (step == UNI_SINGLE) {
                UniswapV3Single[] memory params = abi.decode(data[i], (UniswapV3Single[]));
                for (uint256 j; j < params.length; j++) {
                    UniswapV3Single memory swapData = params[j];
                    swapExactInputSingle(swapData);
                }
            } else if (step == UNI_MULTI) {
                UniswapV3Multi[] memory params = abi.decode(data[i], (UniswapV3Multi[]));
                for (uint256 j; j < params.length; j++) {
                    swapExactInputMultihop(params[j]);
                }
            } else if (step == SUSHI_LEGACY) {
                SushiParams[] memory params = abi.decode(data[i], (SushiParams[]));
                for (uint256 j; j < params.length; j++) {
                    _swapExactTokensForTokens(params[j]);
                }
            } else if (step == XCAL) {
                XcaliburParams[] memory params = abi.decode(data[i], (XcaliburParams[]));
                for (uint256 j; j < params.length; j++) {
                    swapExactTokensForTokens(params[j]);
                }
            } else if (step == CAMELOT) {
                (uint256 amountIn, address[] memory path, address referrer, uint256 deadline) =
                    abi.decode(data[i], (uint256, address[], address, uint256));

                camelotSwap(amountIn, path, referrer, deadline);
            } else if (step == WETH_WITHDRAW) {
                (address to, uint256 amount) = abi.decode(data[i], (address, uint256));
                amount = amount != 0 ? amount : IERC20(weth).balanceOf(address(this));
                weth.withdraw(amount);
                uint256 ethFee = calculateFee(amount);
                SafeTransferLib.safeTransferETH(to, (amount - ethFee));
                SafeTransferLib.safeTransferETH(feeCollector, ethFee);
            } else if (step == SRC_TRANSFER) {
                SrcTransferParams[] memory params = abi.decode(data[i], (SrcTransferParams[]));
                for (uint256 k; k < params.length; k++) {
                    _srcTransfer(params[k].token, params[k].amount, params[k].receiver);
                }
            } else if (step == STARGATE) {
                (StargateParams memory params, uint8[] memory stepperions, bytes[] memory datass) =
                    abi.decode(data[i], (StargateParams, uint8[], bytes[]));
                stargateSwap(params, stepperions, datass);
            } else {
                revert InvaldStep();
            }
        }
    }

    function _srcTransfer(address _token, uint256 amount, address to) private {
        amount = amount != 0 ? amount : IERC20(_token).balanceOf(address(this));
        uint256 fee = calculateFee(amount);
        amount -= fee;
        IERC20(_token).safeTransfer(feeCollector, fee);
        IERC20(_token).safeTransfer(to, amount);
        emit FeePaid(_token, fee);
    }

    function calculateFee(uint256 amount) internal pure returns (uint256 fee) {
        fee = amount - ((amount * 9995) / 1e4);
    }

    receive() external payable {}
}

