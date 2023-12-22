// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Proxy.sol";
import "./IWETH9.sol";
import "./Permit2.sol";
import "./SafeERC20.sol";

/// @title Curve proxy contract
/// @author Matin Kaboli
/// @notice Add/Remove liquidity, and exchange tokens in a pool
contract CurvePool is Proxy {
    using SafeERC20 for IERC20;

    address[] public tokens;
    address public immutable pool;
    address public immutable token;
    uint8 public immutable ethIndex;

    /// @notice Receives ERC20 tokens and Curve pool address and saves them
    /// @param _pool Address of Curve pool
    /// @param _tokens Addresses of ERC20 tokens inside the _pool
    /// @param _token Address of pool token
    /// @param _ethIndex Index of ETH in the pool (100 if ETH does not exist in the pool)
    constructor(
        Permit2 _permit2,
        IWETH9 _weth,
        address _pool,
        address[] memory _tokens,
        address _token,
        uint8 _ethIndex
    ) Proxy(_permit2, _weth) {
        pool = _pool;
        token = _token;
        tokens = _tokens;
        ethIndex = _ethIndex;

        for (uint8 i = 0; i < _tokens.length;) {
            if (i != _ethIndex) {
                IERC20(tokens[i]).safeApprove(_pool, type(uint256).max);
            }

            unchecked {
                ++i;
            }
        }

        IERC20(_token).safeApprove(_pool, type(uint256).max);
    }

    /// @notice Returns the balance of the token (or ETH) of this contract
    /// @param _i Index of the token in the pool
    /// @return The amount of ERC20 or ETH
    function getBalance(uint256 _i) internal view returns (uint256) {
        if (ethIndex == _i) {
            return address(this).balance;
        }

        return IERC20(tokens[_i]).balanceOf(address(this));
    }

    /// @notice Sends ERC20 token or ETH from this contract
    /// @param _i Index of the sending token from the pool
    /// @param _amount Amount of the sending token
    function send(uint256 _i, uint256 _amount) internal {
        if (ethIndex == _i) {
            (bool sent,) = payable(msg.sender).call{value: _amount}("");

            require(sent, "Failed to send Ether");
        } else {
            IERC20(tokens[_i]).safeTransfer(msg.sender, _amount);
        }
    }

    /// @notice Calculates msg.value (takes the fee) and retrieves ERC20 tokens (transferFrom)
    /// @param _i Index of the token in the pool
    /// @param _amount Amount of the token (or ETH)
    function retrieveToken(uint256 _i, uint256 _amount) internal {
        if (_i != ethIndex) {
            IERC20(tokens[_i]).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }
}

