// SPDX-License-Identifier: BSL
pragma solidity ^0.7.6;
pragma abicoder v2;

// libraries
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./OneInchHelper.sol";

import "./ISwapRouter.sol";

interface IFactory {
    function isValidStrategy(address strategy) external view returns (bool);

    function governance() external view returns (address);
}

interface IStrategy {
    function pool() external view returns (address);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);
}

interface IAlgebraSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 limitSqrtPrice;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract SwapProxy is ReentrancyGuard {
    IFactory public factory; // DefiEdge contract address
    address public oneInchRouter; // 1inch router address
    ISwapRouter public uniswapSwapRouter; // uniswapV3 swap router
    IAlgebraSwapRouter public algebraSwapRouter; // algebraV2 swap router

    mapping(address => bool) public isAllowedOneInchCaller; // check if oneinch caller is valid or not

    /**
     * @dev Checks if caller is governance
     */
    modifier onlyGovernance() {
        require(msg.sender == factory.governance(), "NO");
        _;
    }

    /**
     * @dev Checks if it's valid strategy or not
     */
    modifier onlyValidStrategy() {
        // check if strategy is in denylist
        require(factory.isValidStrategy(msg.sender), "IS");
        _;
    }

    constructor(address _factory) {
        factory = IFactory(_factory);
    }

    function aggregatorSwap(bytes calldata swapData) external onlyValidStrategy nonReentrant {

        address pool = IStrategy(msg.sender).pool();
        IERC20 token0 = IStrategy(pool).token0();
        IERC20 token1 = IStrategy(pool).token1();

        (IERC20 srcToken, IERC20 dstToken, uint256 amount) = OneInchHelper.decodeData(address(factory), token0, token1, swapData);

        require((srcToken == token0 && dstToken == token1) || (srcToken == token1 && dstToken == token0), "IA");

        // transfer input token to this address
        SafeERC20.safeTransferFrom(srcToken, msg.sender, address(this), amount);

        // approve input token to oneInchRouter
        SafeERC20.safeIncreaseAllowance(srcToken, oneInchRouter, amount);

        // execute swap
        (bool success, bytes memory returnData) = address(oneInchRouter).call{value: 0}(swapData);

        // Verify return status and data
        if (!success) {
            uint256 length = returnData.length;
            if (length < 68) {
                // If the returnData length is less than 68, then the transaction failed silently.
                revert("swap");
            } else {
                // Look for revert reason and bubble it up if present
                uint256 t;
                assembly {
                    returnData := add(returnData, 4)
                    t := mload(returnData) // Save the content of the length slot
                    mstore(returnData, sub(length, 4)) // Set proper length
                }
                string memory reason = abi.decode(returnData, (string));
                assembly {
                    mstore(returnData, t) // Restore the content of the length slot
                }
                revert(reason);
            }
        }

        uint256 token0Bal = token0.balanceOf(address(this));
        uint256 token1Bal = token1.balanceOf(address(this));

        if (token0Bal > 0) {
            SafeERC20.safeTransfer(token0, msg.sender, token0Bal);
        }

        if (token1Bal > 0) {
            SafeERC20.safeTransfer(token1, msg.sender, token1Bal);
        }
    }

    function uniswapV3Swap(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external onlyValidStrategy nonReentrant {

        address pool = IStrategy(msg.sender).pool();
        address token0 = address(IStrategy(pool).token0());
        address token1 = address(IStrategy(pool).token1());


        require(
            (tokenIn == token0 && tokenOut == token1) ||
                (tokenIn == token1 && tokenOut == token0),
            "IA"
        );

        // transfer input token to this address
        SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);

        // approve input token to uniswap router
        SafeERC20.safeIncreaseAllowance(IERC20(tokenIn), address(uniswapSwapRouter), amountIn);

        uniswapSwapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: msg.sender,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );

        uint256 tokenInBal = IERC20(tokenIn).balanceOf(address(this));
        uint256 tokenOutBal = IERC20(tokenOut).balanceOf(address(this));

        if (tokenInBal > 0) {
            SafeERC20.safeTransfer(IERC20(tokenIn), msg.sender, tokenInBal);
        }

        if (tokenOutBal > 0) {
            SafeERC20.safeTransfer(IERC20(tokenOut), msg.sender, tokenOutBal);
        }    }


    function algebraV3Swap(
        address tokenIn,
        address tokenOut,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external onlyValidStrategy nonReentrant {

        address pool = IStrategy(msg.sender).pool();
        address token0 = address(IStrategy(pool).token0());
        address token1 = address(IStrategy(pool).token1());

        require(
            (tokenIn == token0 && tokenOut == token1) ||
                (tokenIn == token1 && tokenOut == token0),
            "IA"
        );

        // transfer input token to this address
        SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);

        // approve input token to uniswap router
        SafeERC20.safeIncreaseAllowance(IERC20(tokenIn), address(algebraSwapRouter), amountIn);

        algebraSwapRouter.exactInputSingle(
            IAlgebraSwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                recipient: msg.sender,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                limitSqrtPrice: sqrtPriceLimitX96
            })
        );

        uint256 tokenInBal = IERC20(tokenIn).balanceOf(address(this));
        uint256 tokenOutBal = IERC20(tokenOut).balanceOf(address(this));

        if (tokenInBal > 0) {
            SafeERC20.safeTransfer(IERC20(tokenIn), msg.sender, tokenInBal);
        }

        if (tokenOutBal > 0) {
            SafeERC20.safeTransfer(IERC20(tokenOut), msg.sender, tokenOutBal);
        }
    }

    /**
     * @notice Change the 1inch router contract address
     */
    function changeOneinchRouter(address _oneInchRouter) external onlyGovernance {
        oneInchRouter = _oneInchRouter;
    }

    /**
     * @notice Change the UniswapV3 router contract address
     */
    function changeUniswapV3Swaprouter(address _uniswapSwapRouter) external onlyGovernance {
        uniswapSwapRouter = ISwapRouter(_uniswapSwapRouter);
    }

    /**
     * @notice Change the Algebra router contract address
     */
    function changeAlgebraSwaprouter(address _algebraSwapRouter) external onlyGovernance {
        algebraSwapRouter = IAlgebraSwapRouter(_algebraSwapRouter);
    }

    /**
     * @notice Add or remove OneInch caller contract address
     * @param _caller Contract address of OneInch caller
     * @param _status whether to add or remove caller address
     */
    function addOrRemoveOneInchCaller(address _caller, bool _status) external onlyGovernance {
        isAllowedOneInchCaller[_caller] = _status;
    }
}

