// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

//           _____                    _____                   _______                   _____            _____                    _____                    _____                    _____
//          /\    \                  /\    \                 /::\    \                 /\    \          /\    \                  /\    \                  /\    \                  /\    \
//         /::\    \                /::\____\               /::::\    \               /::\____\        /::\    \                /::\____\                /::\    \                /::\    \
//        /::::\    \              /::::|   |              /::::::\    \             /:::/    /       /::::\    \              /:::/    /               /::::\    \              /::::\    \
//       /::::::\    \            /:::::|   |             /::::::::\    \           /:::/    /       /::::::\    \            /:::/   _/___            /::::::\    \            /::::::\    \
//      /:::/\:::\    \          /::::::|   |            /:::/~~\:::\    \         /:::/    /       /:::/\:::\    \          /:::/   /\    \          /:::/\:::\    \          /:::/\:::\    \
//     /:::/__\:::\    \        /:::/|::|   |           /:::/    \:::\    \       /:::/    /       /:::/__\:::\    \        /:::/   /::\____\        /:::/__\:::\    \        /:::/__\:::\    \
//     \:::\   \:::\    \      /:::/ |::|   |          /:::/    / \:::\    \     /:::/    /        \:::\   \:::\    \      /:::/   /:::/    /       /::::\   \:::\    \      /::::\   \:::\    \
//   ___\:::\   \:::\    \    /:::/  |::|___|______   /:::/____/   \:::\____\   /:::/    /       ___\:::\   \:::\    \    /:::/   /:::/   _/___    /::::::\   \:::\    \    /::::::\   \:::\    \
//  /\   \:::\   \:::\    \  /:::/   |::::::::\    \ |:::|    |     |:::|    | /:::/    /       /\   \:::\   \:::\    \  /:::/___/:::/   /\    \  /:::/\:::\   \:::\    \  /:::/\:::\   \:::\____\
// /::\   \:::\   \:::\____\/:::/    |:::::::::\____\|:::|____|     |:::|    |/:::/____/       /::\   \:::\   \:::\____\|:::|   /:::/   /::\____\/:::/  \:::\   \:::\____\/:::/  \:::\   \:::|    |
// \:::\   \:::\   \::/    /\::/    / ~~~~~/:::/    / \:::\    \   /:::/    / \:::\    \       \:::\   \:::\   \::/    /|:::|__/:::/   /:::/    /\::/    \:::\  /:::/    /\::/    \:::\  /:::|____|
//  \:::\   \:::\   \/____/  \/____/      /:::/    /   \:::\    \ /:::/    /   \:::\    \       \:::\   \:::\   \/____/  \:::\/:::/   /:::/    /  \/____/ \:::\/:::/    /  \/_____/\:::\/:::/    /
//   \:::\   \:::\    \                  /:::/    /     \:::\    /:::/    /     \:::\    \       \:::\   \:::\    \       \::::::/   /:::/    /            \::::::/    /            \::::::/    /
//    \:::\   \:::\____\                /:::/    /       \:::\__/:::/    /       \:::\    \       \:::\   \:::\____\       \::::/___/:::/    /              \::::/    /              \::::/    /
//     \:::\  /:::/    /               /:::/    /         \::::::::/    /         \:::\    \       \:::\  /:::/    /        \:::\__/:::/    /               /:::/    /                \::/____/
//      \:::\/:::/    /               /:::/    /           \::::::/    /           \:::\    \       \:::\/:::/    /          \::::::::/    /               /:::/    /                  ~~
//       \::::::/    /               /:::/    /             \::::/    /             \:::\    \       \::::::/    /            \::::::/    /               /:::/    /
//        \::::/    /               /:::/    /               \::/____/               \:::\____\       \::::/    /              \::::/    /               /:::/    /
//         \::/    /                \::/    /                 ~~                      \::/    /        \::/    /                \::/____/                \::/    /
//          \/____/                  \/____/                                           \/____/          \/____/                  ~~                       \/____/

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./ANFTReceiver.sol";
import "./SettingsBitFlag.sol";
import "./Math.sol";
import "./ITreasureMarketplace.sol";
import "./BuyOrder.sol";
import "./ITreasureSmolSweeper.sol";
import "./ABaseSmolSweeper.sol";

// Ownable,
abstract contract ABaseTreasureSmolSweeper is
    ReentrancyGuard,
    ABaseSmolSweeper,
    ITreasureSmolSweeper
{
    using SafeERC20 for IERC20;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    IERC20 public defaultPaymentToken;
    ITreasureMarketplace public marketplace;

    constructor(address _treasureMarketplace, address _defaultPaymentToken) {
        marketplace = ITreasureMarketplace(_treasureMarketplace);
        defaultPaymentToken = IERC20(_defaultPaymentToken);

        _approveERC20TokenToContract(
            IERC20(_defaultPaymentToken),
            _treasureMarketplace,
            type(uint256).max
        );
    }

    function setMarketplaceContract(ITreasureMarketplace _treasureMarketplace)
        external
        onlyOwner
    {
        marketplace = _treasureMarketplace;
    }

    function setDefaultPaymentToken(IERC20 _defaultPaymentToken)
        external
        onlyOwner
    {
        defaultPaymentToken = _defaultPaymentToken;
    }

    // approve token to TreasureMarketplace contract address
    function approveDefaultPaymentTokensToTreasureMarketplace()
        external
        onlyOwner
    {
        _approveERC20TokenToContract(
            defaultPaymentToken,
            address(marketplace),
            type(uint256).max
        );
    }

    function sumTotalPrice(BuyOrder[] memory _buyOrders)
        internal
        pure
        returns (uint256 totalPrice)
    {
        for (uint256 i = 0; i < _buyOrders.length; i++) {
            totalPrice +=
                _buyOrders[i].quantity *
                _buyOrders[i].maxPricePerItem;
        }
    }

    function tryBuyItem(
        BuyOrder memory _buyOrder,
        uint16 _inputSettingsBitFlag,
        uint256 _maxSpendAllowanceLeft
    )
        internal
        returns (
            uint256 totalPrice,
            bool success,
            uint16 failReason
        )
    {
        uint256 quantityToBuy = _buyOrder.quantity;
        // check if the listing exists
        ITreasureMarketplace.Listing memory listing = marketplace.listings(
            _buyOrder.assetAddress,
            _buyOrder.tokenId,
            _buyOrder.seller
        );

        // // check if the price is correct
        // if (listing.pricePerItem > _buyOrder.maxPricePerItem) {
        //     // skip this item
        //     return (0, false, SettingsBitFlag.MAX_PRICE_PER_ITEM_EXCEEDED);
        // }

        // not enough listed items
        if (listing.quantity < quantityToBuy) {
            if (
                SettingsBitFlag.checkSetting(
                    _inputSettingsBitFlag,
                    SettingsBitFlag.INSUFFICIENT_QUANTITY_ERC1155
                )
            ) {
                // else buy all listed items even if it's less than requested
                quantityToBuy = listing.quantity;
            } else {
                // skip this item
                return (
                    0,
                    false,
                    SettingsBitFlag.INSUFFICIENT_QUANTITY_ERC1155
                );
            }
        }

        // check if total price is less than max spend allowance left
        if ((listing.pricePerItem * quantityToBuy) > _maxSpendAllowanceLeft) {
            // skip this item
            return (0, false, SettingsBitFlag.MAX_SPEND_ALLOWANCE_EXCEEDED);
        }

        uint256 totalSpent = 0;
        try
            marketplace.buyItem(
                _buyOrder.assetAddress,
                _buyOrder.tokenId,
                _buyOrder.seller,
                uint64(quantityToBuy),
                uint128(_buyOrder.maxPricePerItem)
            )
        {
            if (
                SettingsBitFlag.checkSetting(
                    _inputSettingsBitFlag,
                    SettingsBitFlag.EMIT_SUCCESS_EVENT_LOGS
                )
            ) {
                emit SuccessBuyItem(
                    _buyOrder.assetAddress,
                    _buyOrder.tokenId,
                    _buyOrder.seller,
                    msg.sender,
                    quantityToBuy,
                    listing.pricePerItem
                );
            }

            if (
                IERC165(_buyOrder.assetAddress).supportsInterface(
                    INTERFACE_ID_ERC721
                )
            ) {
                IERC721(_buyOrder.assetAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    _buyOrder.tokenId
                );
            } else if (
                IERC165(_buyOrder.assetAddress).supportsInterface(
                    INTERFACE_ID_ERC1155
                )
            ) {
                IERC1155(_buyOrder.assetAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    _buyOrder.tokenId,
                    quantityToBuy,
                    bytes("")
                );
            } else revert InvalidNFTAddress();

            totalSpent = listing.pricePerItem * quantityToBuy;
        } catch (bytes memory errorReason) {
            if (
                SettingsBitFlag.checkSetting(
                    _inputSettingsBitFlag,
                    SettingsBitFlag.EMIT_FAILURE_EVENT_LOGS
                )
            ) {
                emit CaughtFailureBuyItem(
                    _buyOrder.assetAddress,
                    _buyOrder.tokenId,
                    _buyOrder.seller,
                    msg.sender,
                    quantityToBuy,
                    listing.pricePerItem,
                    errorReason
                );
            }

            if (
                SettingsBitFlag.checkSetting(
                    _inputSettingsBitFlag,
                    SettingsBitFlag.MARKETPLACE_BUY_ITEM_REVERTED
                )
            ) revert FirstBuyReverted(errorReason);
            // skip this item
            return (0, false, SettingsBitFlag.MARKETPLACE_BUY_ITEM_REVERTED);
        }

        return (totalSpent, true, SettingsBitFlag.NONE);
    }

    function buyUsingPaymentToken(
        BuyOrder[] memory _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint256 _maxSpendIncFees
    ) external nonReentrant {
        // transfer payment tokens to this contract
        defaultPaymentToken.safeTransferFrom(
            msg.sender,
            address(this),
            _maxSpendIncFees
        );

        (
            uint256 totalSpentAmount,
            uint256 successCount
        ) = _buyUsingPaymentToken(
                _buyOrders,
                _inputSettingsBitFlag,
                _calculateAmountWithoutFees(_maxSpendIncFees)
            );

        // transfer back failed payment tokens to the buyer
        if (successCount == 0) revert AllReverted();

        uint256 feeAmount = _calculateFee(totalSpentAmount);
        defaultPaymentToken.safeTransfer(
            msg.sender,
            _maxSpendIncFees - (totalSpentAmount + feeAmount)
        );
    }

    function _buyUsingPaymentToken(
        BuyOrder[] memory _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint256 _maxSpendIncFees
    ) internal returns (uint256 totalSpentAmount, uint256 successCount) {
        // buy all assets
        for (uint256 i = 0; i < _buyOrders.length; i++) {
            (
                uint256 spentAmount,
                bool spentSuccess,
                uint16 spentError
            ) = tryBuyItem(
                    _buyOrders[i],
                    _inputSettingsBitFlag,
                    _maxSpendIncFees - totalSpentAmount
                );

            if (spentSuccess) {
                totalSpentAmount += spentAmount;
                successCount++;
            } else {
                if (
                    spentError ==
                    SettingsBitFlag.MAX_SPEND_ALLOWANCE_EXCEEDED &&
                    SettingsBitFlag.checkSetting(
                        _inputSettingsBitFlag,
                        SettingsBitFlag.MAX_SPEND_ALLOWANCE_EXCEEDED
                    )
                ) break;
            }
        }
    }

    function sweepUsingPaymentToken(
        BuyOrder[] memory _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint256 _maxSuccesses,
        uint256 _maxFailures,
        uint256 _maxSpendIncFees,
        uint256 _minSpend
    ) external nonReentrant {
        // transfer payment tokens to this contract
        defaultPaymentToken.safeTransferFrom(
            msg.sender,
            address(this),
            _maxSpendIncFees
        );

        (
            uint256 totalSpentAmount,
            uint256 successCount
        ) = _sweepUsingPaymentToken(
                _buyOrders,
                _inputSettingsBitFlag,
                _maxSuccesses,
                _maxFailures,
                _calculateAmountWithoutFees(_maxSpendIncFees),
                _minSpend
            );

        // transfer back failed payment tokens to the buyer
        if (successCount == 0) revert AllReverted();

        uint256 feeAmount = _calculateFee(totalSpentAmount);
        defaultPaymentToken.safeTransfer(
            msg.sender,
            _maxSpendIncFees - (totalSpentAmount + feeAmount)
        );
    }

    function _sweepUsingPaymentToken(
        BuyOrder[] memory _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint256 _maxSuccesses,
        uint256 _maxFailures,
        uint256 _maxSpendIncFees,
        uint256 _minSpend
    ) internal returns (uint256 totalSpentAmount, uint256 successCount) {
        // buy all assets
        uint256 failCount = 0;
        for (uint256 i = 0; i < _buyOrders.length; i++) {
            if (successCount >= _maxSuccesses || failCount >= _maxFailures)
                break;

            if (totalSpentAmount >= _minSpend) break;

            (
                uint256 spentAmount,
                bool spentSuccess,
                uint16 spentError
            ) = tryBuyItem(
                    _buyOrders[i],
                    _inputSettingsBitFlag,
                    _maxSpendIncFees - totalSpentAmount
                );

            if (spentSuccess) {
                totalSpentAmount += spentAmount;
                successCount++;
            } else {
                if (
                    spentError ==
                    SettingsBitFlag.MAX_SPEND_ALLOWANCE_EXCEEDED &&
                    SettingsBitFlag.checkSetting(
                        _inputSettingsBitFlag,
                        SettingsBitFlag.MAX_SPEND_ALLOWANCE_EXCEEDED
                    )
                ) break;
                failCount++;
            }
        }
    }
}

