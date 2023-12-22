// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

/// @title Base V1 Fees contract is used as a 1:1 pair relationship to split out fees,
///        this ensures that the curve does not need to be modified for LP shares
contract PairFees is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev The pair it is bonded to
    address internal pair;
    /// @dev Token0 of pair, saved localy and statically for gas optimization
    address internal token0;
    /// @dev Token1 of pair, saved localy and statically for gas optimization
    address internal token1;

    function initialize(address _token0, address _token1, bool /* isStable */) public initializer {
        pair = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    // Allow the pair to transfer fees to users
    function claimFeesFor(address recipient, uint amount0, uint amount1) external {
        require(msg.sender == pair, "Not pair");
        if (amount0 > 0) {
            IERC20Upgradeable(token0).safeTransfer(recipient, amount0);
        }
        if (amount1 > 0) {
            IERC20Upgradeable(token1).safeTransfer(recipient, amount1);
        }
    }
}

