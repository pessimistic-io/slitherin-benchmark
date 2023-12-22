// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./types_DexterityTrading.sol";
import "./Main.sol";
import "./payload-assemblers_DexterityTrading.sol";
import "./Core.sol";

/**
 * @title Dexterity Trading Payload Facet
 * @author Ofir Smolinsky @OfirYC
 * @notice The facet responsible for building the eHXRO payloads for trading on Dexterity
 */

contract DexterityTradingPayloadFacet {
    // ================
    //     METHODS
    // ================
    /**
     * Build a deposit payload
     * @param account - The account to build this payload on
     * @param context - DepositFunds accounts for solana "access list"
     * @param amt - Amount to deposit (denominated in LOCAL DECIMALS)
     */
    function buildDepositPayload(
        address account,
        DepositFundsAccounts calldata context,
        uint256 amt
    ) external view returns (InboundPayload memory depositPayload) {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        uint256 userNonce = coreStorage.nonces[account];

        address localToken = coreStorage
            .tokens[context.token_program]
            .localAddress;

        if (localToken == address(0)) revert UnsupportedToken();

        uint256 tokenDecimals = IERC20(localToken).decimals();

        bytes memory msgHash = bytes.concat(
            abi.encode(context),
            abi.encode(
                DepositFundsParams({
                    quantity: Fractional({m: amt, exp: tokenDecimals})
                })
            ),
            abi.encode(userNonce)
        );

        depositPayload = InboundPayload(context.token_program, amt, msgHash);
    }

    /**
     * Build a New Order payload
     * @param account - The account to build this payload ontop of
     * @param context - New Order Accounts Context
     * @param newOrderParams - New Order Params
     * @return newOrderPayload - The encoded HXRO payload
     */
    function buildNewOrderMessage(
        address account,
        NewOrderAccounts calldata context,
        NewOrderParams calldata newOrderParams
    ) external view returns (InboundPayload memory newOrderPayload) {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        uint256 userNonce = coreStorage.nonces[account];

        bytes memory msgHash = bytes.concat(
            abi.encode(context),
            abi.encode(newOrderParams),
            abi.encode(userNonce)
        );

        newOrderPayload = InboundPayload(bytes32(0), 0, msgHash);
    }

    /**
     * Build a Cancel Order payload
     * @param account - The account to build this payload ontop of
     * @param context - Cancel Order Accounts Context
     * @param cancelOrderParams - Cancel Order Params
     */
    function buildCancelOrderPayload(
        address account,
        CancelOrderAccounts calldata context,
        CancelOrderParams calldata cancelOrderParams
    ) external view returns (InboundPayload memory cancelOrderPayload) {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        uint256 userNonce = coreStorage.nonces[account];

        bytes memory msgHash = bytes.concat(
            abi.encode(context),
            abi.encode(cancelOrderParams),
            abi.encode(userNonce)
        );

        cancelOrderPayload = InboundPayload(bytes32(0), 0, msgHash);
    }
}

