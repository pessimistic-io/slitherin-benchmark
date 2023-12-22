// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./IBalancerVault.sol";

contract BalancerUtils {
    address internal constant BALANCER_ETH = address(0);
    address internal immutable balancerVault;
    address private immutable _self;

    constructor(address _balancerVault) {
        balancerVault = _balancerVault;
        _self = address(this);
    }

    /**
     * @dev swaps {from} for {to} in balancer pool with id {poolId}
     * @dev this function does not accept ETH swaps
     * @param from the token to send
     * @param to the token to receive
     * @param amount the amount of {from} to send
     * @param poolId the id of the balancer pool
     */
    function _swapBalancerTokens(
        address from,
        address to,
        uint256 amount,
        bytes32 poolId
    ) internal {
        require(
            from != BALANCER_ETH && to != BALANCER_ETH,
            "ETH swap not directly permitted"
        );

        // from self, to self, using internal balance for neither
        IBalancerVault.FundManagement memory fundManagement = IBalancerVault
            .FundManagement(_self, false, payable(_self), false);
        // amount in is given, hence SwapKind.GIVEN_IN. No user data is needed, hence "0x00"
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(
            poolId,
            IBalancerVault.SwapKind.GIVEN_IN,
            from,
            to,
            amount,
            ""
        );

        // approve and perform swap
        IERC20(from).approve(balancerVault, amount);
        IBalancerVault(balancerVault).swap(
            singleSwap,
            fundManagement,
            // min out not handled in this function, so it is set to zero
            0,
            // no deadline for this swap, hence deadline is infinite
            type(uint256).max
        );
    }
}

