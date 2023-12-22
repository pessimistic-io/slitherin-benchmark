// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";

/// @title GRTTokenSwap
/// @notice A token swap contract that allows exchanging tokens minted by Arbitrum's deprecated GRT contract for the canonical GRT token
/// Note that the inverse swap is not supported
/// @dev This contract needs to be topped off with enough canonical GRT to cover the swaps
contract GRTTokenSwap is Ownable {
    // -- State --

    /// The GRT token contract using the custom GRT gateway
    IERC20 public immutable canonicalGRT;
    /// The GRT token contract using Arbitrum's standard ERC20 gateway
    IERC20 public immutable deprecatedGRT;

    // -- Events --
    event TokensSwapped(address indexed user, uint256 amount);
    event TokensTaken(address indexed owner, address indexed token, uint256 amount);

    // -- Errors --
    /// @dev Cannot swap 0 tokens amounts
    error AmountMustBeGreaterThanZero();
    /// @dev Canonical and deprecated pair addresses are invalid. Either the same or one is 0x00
    error InvalidTokenAddressPair();
    /// @dev The contract does not have enough canonical GRT tokens to cover the swap
    error ContractOutOfFunds();

    // -- Functions --
    /// @notice The constructor for the GRTTokenSwap contract
    constructor(IERC20 _canonicalGRT, IERC20 _deprecatedGRT) {
        if (
            address(_canonicalGRT) == address(0) ||
            address(_deprecatedGRT) == address(0) ||
            address(_canonicalGRT) == address(_deprecatedGRT)
        ) revert InvalidTokenAddressPair();

        canonicalGRT = _canonicalGRT;
        deprecatedGRT = _deprecatedGRT;
    }

    /// @notice Swap the entire balance of the sender's deprecated GRT for canonical GRT
    /// @dev Ensure approve(type(uint256).max) or approve(senderBalance) is called on the deprecated GRT contract before calling this function
    function swapAll() external {
        uint256 balance = deprecatedGRT.balanceOf(msg.sender);
        swap(balance);
    }

    /// @notice Swap deprecated GRT for canonical GRT
    /// @dev Ensure approve(_amount) is called on the deprecated GRT contract before calling this function
    /// @param _amount Amount of tokens to swap
    function swap(uint256 _amount) public {
        if (_amount == 0) revert AmountMustBeGreaterThanZero();

        uint256 contractBalance = canonicalGRT.balanceOf(address(this));
        if (_amount > contractBalance) revert ContractOutOfFunds();

        bool success = deprecatedGRT.transferFrom(msg.sender, address(this), _amount);
        require(success, "Transfer from deprecated GRT failed");
        canonicalGRT.transfer(msg.sender, _amount);

        emit TokensSwapped(msg.sender, _amount);
    }

    /// @notice Transfer all tokens to the contract owner
    /// @dev This is a convenience function to clean up after the contract it's deemed to be no longer necessary
    /// @dev Reverts if either token balance is zero
    function sweep() external onlyOwner {
        (uint256 canonicalBalance, uint256 deprecatedBalance) = getTokenBalances();
        takeCanonical(canonicalBalance);
        takeDeprecated(deprecatedBalance);
    }

    /// @notice Take deprecated tokens from the contract and send it to the owner
    /// @param _amount The amount of tokens to take
    function takeDeprecated(uint256 _amount) public onlyOwner {
        _take(deprecatedGRT, _amount);
    }

    /// @notice Take canonical tokens from the contract and send it to the owner
    /// @param _amount The amount of tokens to take
    function takeCanonical(uint256 _amount) public onlyOwner {
        _take(canonicalGRT, _amount);
    }

    /// @notice Get the token balances
    /// @return canonicalBalance Contract's canonicalGRT balance
    /// @return deprecatedBalance Contract's deprecatedGRT balance
    function getTokenBalances() public view returns (uint256 canonicalBalance, uint256 deprecatedBalance) {
        return (canonicalGRT.balanceOf(address(this)), deprecatedGRT.balanceOf(address(this)));
    }

    /// @notice Take tokens from the contract and send it to the owner
    /// @param _token The token to take
    /// @param _amount The amount of tokens to take
    function _take(IERC20 _token, uint256 _amount) private {
        address owner = owner();
        if (_amount > 0) {
            _token.transfer(owner, _amount);
        }

        emit TokensTaken(owner, address(_token), _amount);
    }
}

