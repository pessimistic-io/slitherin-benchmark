/// SPDX-License-Identifier: GPL-3.0

/// Copyright (C) 2023 Portals.fi

/// @author Portals.fi
/// @notice This contract adds or removes liquidity to or from Balancer V2 like pools using any ERC20 token or the network token.
/// @note This contract is intended to be consumed via a multicall contract and as such omits various checks
/// including slippage and does not return the quantity of tokens acquired. These checks should be handled
/// by the caller

pragma solidity 0.8.19;

import { ERC20 } from "./ERC20.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { Owned } from "./Owned.sol";
import { Pausable } from "./Pausable.sol";
import { IBalancerVault } from "./IBalancerVault.sol";

contract BalancerV2Portal is Owned, Pausable {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    constructor(address admin) Owned(admin) { }

    /// @notice Add liquidity to Balancer V2 like pools with network tokens/ERC20 tokens
    /// @param inputToken The ERC20 token address to spend (address(0) if network token)
    /// @param inputAmount The quantity of inputToken to Portal in
    /// @param vault The Balancer V2 like vault to be used for adding liquidity
    /// @param poolId The ID of the pool to add liquidity to
    /// @param assets The assets in the pool
    /// @param index The index of the asset to add
    /// @param recipient The recipient of the liquidity tokens
    function portalIn(
        address inputToken,
        uint256 inputAmount,
        address vault,
        bytes32 poolId,
        address[] calldata assets,
        uint256 index,
        address recipient
    ) external payable whenNotPaused {
        uint256 amount = _transferFromCaller(inputToken, inputAmount);

        uint256[] memory maxAmountsIn = new uint256[](assets.length);
        maxAmountsIn[index] = amount;

        bytes memory userData = abi.encode(1, maxAmountsIn, 0);

        _approve(inputToken, vault);

        IBalancerVault(vault).joinPool(
            poolId,
            address(this),
            recipient,
            IBalancerVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );
    }

    /// @notice Remove liquidity from Balancer V2 like pools into network tokens/ERC20 tokens
    /// @param inputToken The Balancer V2 like pool address (i.e. the LP token address)
    /// @param inputAmount The quantity of inputToken to Portal out
    /// @param vault The Balancer V2 like vault to be used for removing liquidity
    /// @param poolId The ID of the pool to remove liquidity from
    /// @param assets The assets in the pool
    /// @param index The index of the asset to remove
    /// @param recipient The recipient of the withdrawn tokens
    function portalOut(
        address inputToken,
        uint256 inputAmount,
        address vault,
        bytes32 poolId,
        address[] calldata assets,
        uint256 index,
        address payable recipient
    ) external payable whenNotPaused {
        uint256 amount = _transferFromCaller(inputToken, inputAmount);

        uint256[] memory minAmountsOut = new uint256[](assets.length);

        bytes memory userData = abi.encode(0, amount, index);

        _approve(inputToken, address(vault));

        IBalancerVault(vault).exitPool(
            poolId,
            address(this),
            recipient,
            IBalancerVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: userData,
                toInternalBalance: false
            })
        );
    }

    /// @notice Transfers tokens or the network token from the caller to this contract
    /// @param token The address of the token to transfer (address(0) if network token)
    /// @param quantity The quantity of tokens to transfer from the caller
    /// @return The quantity of tokens or network tokens transferred from the caller to this contract
    function _transferFromCaller(address token, uint256 quantity)
        internal
        virtual
        returns (uint256)
    {
        if (token == address(0)) {
            require(msg.value != 0, "Invalid msg.value");
            return msg.value;
        }

        require(
            quantity != 0 && msg.value == 0,
            "Invalid quantity or msg.value"
        );
        ERC20(token).safeTransferFrom(
            msg.sender, address(this), quantity
        );

        return quantity;
    }

    /// @notice Approve a token for spending with infinite allowance
    /// @param token The ERC20 token to approve
    /// @param spender The spender of the token
    function _approve(address token, address spender) internal {
        ERC20 _token = ERC20(token);
        if (_token.allowance(address(this), spender) == 0) {
            _token.safeApprove(spender, type(uint256).max);
        }
    }

    /// @dev Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Recovers stuck tokens
    /// @param tokenAddress The address of the token to recover (address(0) if ETH)
    /// @param tokenAmount The quantity of tokens to recover
    /// @param to The address to send the recovered tokens to
    function recoverToken(
        address tokenAddress,
        uint256 tokenAmount,
        address to
    ) external onlyOwner {
        if (tokenAddress == address(0)) {
            to.safeTransferETH(tokenAmount);
        } else {
            ERC20(tokenAddress).safeTransfer(to, tokenAmount);
        }
    }

    receive() external payable { }
}

