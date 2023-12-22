/**
 * LP adapter for minting GLP using it's basket assets
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./LpAdapter.sol";
import "./IGlp.sol";
import "./ERC20-Util.sol";

// ===================
//      STRUCTS
// ===================
/**
 * Represents the extra data of the client
 * @param lpToken - The address of the end LP token to receive, which represents the basket of assets
 * @param lpTokenShuttle - The address which we use to transfer these LP tokens.
 * @param vault - The vault address
 */
struct GlpClientData {
    address lpToken;
    address lpTokenShuttle;
    address vault;
}

contract GlpAdapterFacet is ERC20Utils {
    // Libs
    using SafeERC20 for IERC20;

    // ===================
    //      FUNCTIONS
    // ===================
    /**
     * Add Liquidity To A GLP LPClient
     * @param client - LP Adapter compliant LPClient struct
     * @param mintToken - The token to use to mint GLP
     * @param tokenAmount - amount for token #1
     */
    function addLiquidityGLP(
        LPClient calldata client,
        address mintToken,
        address /** unusedAddress */,
        uint256 tokenAmount
    ) external payable {
        GlpClientData memory clientData = abi.decode(
            client.extraData,
            (GlpClientData)
        );

        uint256 mintedAmt;

        if (mintToken == address(0))
            mintedAmt = IRewardRouterV2(client.clientAddress)
                .mintAndStakeGlpETH{value: msg.value}(0, 0);
        else {
            _transferFromVault(msg.sender, IERC20(mintToken), tokenAmount);

            _tryApproveExternal(
                IERC20(mintToken),
                clientData.vault,
                tokenAmount
            );

            _tryApproveExternal(
                IERC20(mintToken),
                0x3963FfC9dff443c2A94f21b129D429891E32ec18,
                tokenAmount
            );

            mintedAmt = IRewardRouterV2(client.clientAddress).mintAndStakeGlp(
                mintToken,
                tokenAmount,
                0,
                0
            );
        }

        IERC20(clientData.lpTokenShuttle).transfer(msg.sender, mintedAmt);
    }

    /**
     * Remove liquidity
     * @param client - LP Adapter compliant LPClient struct
     * @param tokenOut - Token to redeem to
     * @param glpAmount - Amount of glp tokens to withdraw
     */
    function removeLiquidityGLP(
        LPClient calldata client,
        address tokenOut,
        address /** unusedAddress */,
        uint256 glpAmount
    ) external {
        GlpClientData memory clientData = abi.decode(
            client.extraData,
            (GlpClientData)
        );

        _transferFromVault(
            msg.sender,
            IERC20(clientData.lpTokenShuttle),
            glpAmount
        );

        if (tokenOut == address(0))
            IRewardRouterV2(client.clientAddress).unstakeAndRedeemGlpETH(
                glpAmount,
                0,
                payable(msg.sender)
            );
        else
            IRewardRouterV2(client.clientAddress).unstakeAndRedeemGlp(
                tokenOut,
                glpAmount,
                0,
                msg.sender
            );
    }

    /**
     * Harvest rewards from a GLP position
     * @param client - The client
     */
    function harvestGlpRewards(LPClient calldata client) external {
        GlpClientData memory clientData = abi.decode(
            client.extraData,
            (GlpClientData)
        );
        IRewardTracker(clientData.lpToken).claimForAccount(
            msg.sender,
            msg.sender
        );
    }

    // ==================
    //     GETTERS
    // ==================
    /**
     * Get an address' balance of an LP pair token
     * @param client The LP client to check on
     * @param owner owner to check the balance of
     * @return ownerLpBalance
     */
    function balanceOfGLP(
        LPClient calldata client,
        address /** unusedAddress */,
        address /** unusedAddress */,
        address owner
    ) external view returns (uint256 ownerLpBalance) {
        GlpClientData memory clientData = abi.decode(
            client.extraData,
            (GlpClientData)
        );
        return IERC20(clientData.lpToken).balanceOf(owner);
    }
}
// Token: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
// newTo: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
// Owner: 0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758
// Newow: 0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758
// Spend: 0x489ee077994B6658eAfA855C308275EAd8097C4A
// Nwspe: 0x489ee077994B6658eAfA855C308275EAd8097C4A
// Amont: 100000000000000
// Amtaa: 100000000000000
//

