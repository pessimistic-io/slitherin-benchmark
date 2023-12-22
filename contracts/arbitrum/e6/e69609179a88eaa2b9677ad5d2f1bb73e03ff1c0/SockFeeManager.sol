// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";

import "./ISockFeeManager.sol";

/**
 * @title SockFeeManager
 * @dev A contract for managing the sock fee cashout
 */
contract SockFeeManager is Ownable, ISockFeeManager {
    // Instance of the Uniswap V3 router.
    ISwapRouter private immutable _swapRouter;

    // Address of the cashout address
    address private immutable _cashOutDestination;

    // Address of the cashout token address
    IERC20 private _cashOutToken;

    // Mapping of tokens that are allowed to be used for sock fees
    mapping(IERC20 => bool) private _allowedFeeTokens;

    /// @param aSockCashOutDestination Address of the cashout address
    /// @param aSwapRouter Address of the Uniswap V3 swap router.
    /// @param aCashOutToken Address of the cashout token address
    constructor(
        address aSockCashOutDestination,
        ISwapRouter aSwapRouter,
        IERC20 aCashOutToken
    ) Ownable() {
        _cashOutDestination = aSockCashOutDestination;
        _swapRouter = aSwapRouter;
        _cashOutToken = aCashOutToken;
    }

    /// @notice Sets the cashout token
    /// @param aCashOutToken The address of the cashout token
    function changeCashOutToken(IERC20 aCashOutToken) external onlyOwner {
        _cashOutToken = aCashOutToken;
    }

    /// @notice Checks if a specific token is allowed to be used for sock fees
    /// @param aToken The contract address of the token in question
    /// @return bool True if the token is allowed to be used for sock fees
    function isAllowedToken(IERC20 aToken) external view returns (bool) {
        return _allowedFeeTokens[aToken];
    }

    /// @notice Adds a list of tokens to the allowed list of tokens
    /// @param someTokens The list of tokens to be added
    function addAllowedTokens(IERC20[] calldata someTokens) external onlyOwner {
        for (uint256 i = 0; i < someTokens.length; i++) {
            _allowedFeeTokens[someTokens[i]] = true;
        }
    }

    /// @notice Removes a list of tokens from the allowed list of tokens
    /// @param someTokens The list of tokens to be removed
    function removeAllowedTokens(
        IERC20[] calldata someTokens
    ) external onlyOwner {
        for (uint256 i = 0; i < someTokens.length; i++) {
            delete _allowedFeeTokens[someTokens[i]];
        }
    }

    /// @notice Deducts the sock fee from the provided tokens
    /// @param cashOutParams The list of tokens to be cashed out with necessary swap data.
    function cashOut(
        CashOutParams[] calldata cashOutParams
    ) external onlyOwner {
        for (uint256 i = 0; i < cashOutParams.length; i++) {
            require(
                _allowedFeeTokens[IERC20(cashOutParams[i].tokenIn)],
                "SockFeeManager: Token not allowed"
            );
            _attemptCashOut(cashOutParams[i]);
        }
    }

    /// @dev Returns the address of the cashout token
    /// @return IERC20 The address of the cashout token
    function cashOutToken() public view returns (IERC20) {
        return _cashOutToken;
    }

    /// @dev Returns the address of the cashout destination
    /// @return address The address of the cashout destination
    function cashOutDestination() public view returns (address) {
        return _cashOutDestination;
    }

    /// @dev Returns the Uniswap V3 router instance.
    /// @return An instance of the Uniswap V3 router.
    function swapRouter() public view returns (ISwapRouter) {
        return _swapRouter;
    }

    /// @notice Deducts the sock fee from the provided tokens
    /// @param cashOutParams The token to be cashed out
    function _attemptCashOut(CashOutParams calldata cashOutParams) internal {
        uint256 balance = cashOutParams.tokenIn.balanceOf(address(this));
        if (balance > 0) {
            TransferHelper.safeApprove(
                address(cashOutParams.tokenIn),
                address(swapRouter()),
                balance
            );
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: address(cashOutParams.tokenIn),
                    tokenOut: address(cashOutToken()),
                    fee: cashOutParams.fee,
                    recipient: cashOutDestination(),
                    amountIn: balance,
                    amountOutMinimum: cashOutParams.amountOutMinimum,
                    deadline: block.timestamp,
                    sqrtPriceLimitX96: 0
                });

            // Executes the swap on Uniswap V3.
            swapRouter().exactInputSingle(params);
        }
    }
}
