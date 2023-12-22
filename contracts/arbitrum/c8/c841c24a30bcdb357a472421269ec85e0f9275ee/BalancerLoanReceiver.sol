pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

/// @notice Skinny interface for the Balancer Vault contract that provides the flash loaned tokens
interface IBalancer {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

/// @title BalancerLoanReceiver
/// @author Hilliam
/// @notice Minimal implementation to receive a Balancer flash loan
abstract contract BalancerLoanReceiver {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Balancer Vault Contract
    // address constant balancerAddress =
    //     0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Flag for protecting the `receiveFlashLoan` callback
    /// @dev `flashWallOn` is false only when a flash loan is about to be executed and turned on otherwise.
    /// @dev See an example of unprotected callbacks: https://github.com/SunWeb3Sec/DeFiVulnLabs/blob/main/src/test/Unprotected-callback.sol
    bool private flashWallOn = true;
    address immutable balancerAddress;
    IBalancer immutable balancer;

    constructor(address _balancerAddress) {
        balancerAddress = _balancerAddress;
        balancer = IBalancer(_balancerAddress);
    }

    /*//////////////////////////////////////////////////////////////
                               FLASH LOAN
    //////////////////////////////////////////////////////////////*/

    /// @notice Flash loan `amount` of a single `token`
    /// @param token Token address to flash loan
    /// @param amount Amount of `token` to flash loan
    /// @dev Simply packages up parameters to fit inside `flashLoanMultipleTokens` call
    function _flashLoan(
        address token,
        uint256 amount,
        bytes memory data
    ) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = token;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        _flashLoanMultipleTokens(tokens, amounts, data);
    }

    /// @notice Flash loan multiple `tokens`
    /// @param tokens Array of token addresses to flash loan
    /// @param amounts Array of corresponding token amounts to flash loan
    /// @dev Tokens should be arranged in address order e.g [0x1, 0x3, 0xA, ...].
    /// @dev See https://dev.balancer.fi/references/error-codes#input for more information.
    function _flashLoanMultipleTokens(
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        // Flag that we have turned off our `flashWall` to allow for a flash loan to occur
        flashWallOn = false;
        balancer.flashLoan(address(this), tokens, amounts, data);
    }

    /// @notice Callback function that is ran
    /// @param tokens Array of tokens that have just been provided by flash loan
    /// @param amounts Array of corresponding amounts that have just been provided
    /// @dev The callback should be ran in the context that `msg.sender` == `balancerAddress`.
    /// @dev `feeAmounts` is just an array of zeroes - Balancer offers free flash loans.
    /// @dev `userData` is assumed to be unused for simplicity.
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata /* feeAmounts */,
        bytes calldata data
    ) public {
        // Ensure that the caller of this callback is Balancer
        require(msg.sender == balancerAddress, "Not Balancer");

        // Ensure that the flash wall is off
        require(!flashWallOn, "Flash wall is on");

        // Run any needed logic to run upon receipt of flash-loaned tokens
        _flashLoanCallback(tokens, amounts, data);

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(balancerAddress, amounts[i]);
        }

        // Turn back on flash wall to prevent others from calling this callback
        flashWallOn = true;
    }

    /// @notice Internal logic for `receiveFlashLoan`
    /// @param tokens Array of tokens that have just been provided by flash loan
    /// @param amounts Array of corresponding amounts that have just been provided
    function _flashLoanCallback(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata data
    ) internal virtual;
}

