// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./IStrategy.sol";

import "./IRebalanceFacet.sol";

contract RebalanceFacet is IRebalanceFacet {
    using SafeERC20 for IERC20;

    function rebalance(address callback, bytes calldata data) external {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet commonFacet = ICommonFacet(address(this));
        (, , , , bool isStarted, address strategy) = IDutchAuctionFacet(address(this)).auctionParams();

        require(isStarted && !IStrategy(strategy).canStopAuction(), "Invalid auction state");

        uint256 tvlBefore = commonFacet.tvl();
        (address[] memory vaultTokens, , ) = commonFacet.tokens();
        for (uint256 i = 0; i < vaultTokens.length; i++) {
            ITokensManagementFacet(address(this)).approve(vaultTokens[i], callback, type(uint256).max);
        }

        (bool success, bytes memory response) = callback.call(data);
        require(success, "Callback execution failed");

        address[] memory newMutableTokens = abi.decode(response, (address[]));

        ICommonFacet(address(this)).updateMutableTokens(newMutableTokens);

        uint256 tvlAfter = commonFacet.tvl();
        IStrategy(strategy).updateVaultTokens(newMutableTokens);

        require(IStrategy(strategy).checkStateAfterRebalance(), "Invalid tokens state after rebalance");
        require(IDutchAuctionFacet(address(this)).checkTvlAfterRebalance(tvlBefore, tvlAfter), "Too little received");

        for (uint256 i = 0; i < vaultTokens.length; i++) {
            ITokensManagementFacet(address(this)).approve(vaultTokens[i], callback, 0);
        }

        IDutchAuctionFacet(address(this)).finishAuction();
    }
}

