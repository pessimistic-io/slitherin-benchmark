// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableInternal.sol";
import "./PausableInternal.sol";
import "./IERC20.sol";
import "./ERC1155BaseInternal.sol";
import "./ERC1155EnumerableInternal.sol";
import "./IWETH.sol";
import "./SafeERC20.sol";

import "./IPremiaPool.sol";

import "./IVault.sol";

import "./IQueueEvents.sol";
import "./QueueStorage.sol";

/**
 * @title Knox Queue Internal Contract
 */

contract QueueInternal is
    ERC1155BaseInternal,
    ERC1155EnumerableInternal,
    IQueueEvents,
    OwnableInternal,
    PausableInternal
{
    using QueueStorage for QueueStorage.Layout;
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    uint256 internal constant ONE_SHARE = 10**18;

    IERC20 public immutable ERC20;
    IVault public immutable Vault;
    IWETH public immutable WETH;

    constructor(
        bool isCall,
        address pool,
        address vault,
        address weth
    ) {
        IPremiaPool.PoolSettings memory settings =
            IPremiaPool(pool).getPoolSettings();
        address asset = isCall ? settings.underlying : settings.base;

        ERC20 = IERC20(asset);
        Vault = IVault(vault);
        WETH = IWETH(weth);
    }

    /************************************************
     *  ACCESS CONTROL
     ***********************************************/

    /**
     * @dev Throws if called by any account other than the vault.
     */
    modifier onlyVault() {
        QueueStorage.Layout storage l = QueueStorage.layout();
        require(msg.sender == address(Vault), "!vault");
        _;
    }

    /************************************************
     *  DEPOSIT
     ***********************************************/

    /**
     * @notice validates the deposit, redeems claim tokens for vault shares and mints claim
     * tokens 1:1 for collateral deposited
     * @param l queue storage layout
     * @param amount total collateral deposited
     */
    function _deposit(QueueStorage.Layout storage l, uint256 amount) internal {
        require(amount > 0, "value exceeds minimum");

        // the maximum total value locked is the sum of collateral assets held in
        // the queue and the vault. if a deposit exceeds the max TVL, the transaction
        // should revert.
        uint256 totalWithDepositedAmount =
            Vault.totalAssets() + ERC20.balanceOf(address(this));
        require(totalWithDepositedAmount <= l.maxTVL, "maxTVL exceeded");

        // prior to making a new deposit, the vault will redeem all available claim tokens
        // in exchange for the pro-rata vault shares
        _redeemMax(msg.sender, msg.sender);

        uint256 currentTokenId = QueueStorage._getCurrentTokenId();

        // the queue mints claim tokens 1:1 with collateral deposited
        _mint(msg.sender, currentTokenId, amount, "");

        emit Deposit(l.epoch, msg.sender, amount);
    }

    /************************************************
     *  REDEEM
     ***********************************************/

    /**
     * @notice exchanges claim token for vault shares
     * @param tokenId claim token id
     * @param receiver vault share recipient
     * @param owner claim token holder
     */
    function _redeem(
        uint256 tokenId,
        address receiver,
        address owner
    ) internal {
        uint256 currentTokenId = QueueStorage._getCurrentTokenId();

        // claim tokens cannot be redeemed within the same epoch that they were minted
        require(
            tokenId != currentTokenId,
            "current claim token cannot be redeemed"
        );

        uint256 balance = _balanceOf(owner, tokenId);
        uint256 unredeemedShares = _previewUnredeemed(tokenId, owner);

        // burns claim tokens held by owner
        _burn(owner, tokenId, balance);
        // transfers unredeemed share amount to the receiver
        require(Vault.transfer(receiver, unredeemedShares), "transfer failed");

        uint64 epoch = QueueStorage._getEpoch();
        emit Redeem(epoch, receiver, owner, unredeemedShares);
    }

    /**
     * @notice exchanges all claim tokens for vault shares
     * @param receiver vault share recipient
     * @param owner claim token holder
     */
    function _redeemMax(address receiver, address owner) internal {
        uint256[] memory tokenIds = _tokensByAccount(owner);
        uint256 currentTokenId = QueueStorage._getCurrentTokenId();

        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId != currentTokenId) {
                _redeem(tokenId, receiver, owner);
            }
        }
    }

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @notice calculates unredeemed vault shares available
     * @param tokenId claim token id
     * @param owner claim token holder
     * @return total unredeemed vault shares
     */
    function _previewUnredeemed(uint256 tokenId, address owner)
        internal
        view
        returns (uint256)
    {
        QueueStorage.Layout storage l = QueueStorage.layout();
        uint256 balance = _balanceOf(owner, tokenId);
        return (balance * l.pricePerShare[tokenId]) / ONE_SHARE;
    }

    /************************************************
     *  DEPOSIT HELPERS
     ***********************************************/

    /**
     * @notice wraps ETH sent to the contract and credits the amount, if the collateral asset
     * is not WETH, the transaction will revert
     * @param amount total collateral deposited
     * @return credited amount
     */
    function _wrapNativeToken(uint256 amount) internal returns (uint256) {
        uint256 credit;

        if (msg.value > 0) {
            require(address(ERC20) == address(WETH), "collateral != wETH");

            if (msg.value > amount) {
                // if the ETH amount is greater than the amount needed, it will be sent
                // back to the msg.sender
                unchecked {
                    (bool success, ) =
                        payable(msg.sender).call{value: msg.value - amount}("");

                    require(success, "ETH refund failed");

                    credit = amount;
                }
            } else {
                credit = msg.value;
            }

            WETH.deposit{value: credit}();
        }

        return credit;
    }

    /**
     * @notice pull token from user, send to exchangeHelper trigger a trade from
     * ExchangeHelper, and credits the amount
     * @param Exchange ExchangeHelper contract interface
     * @param s swap arguments
     * @param tokenOut token to swap for. should always equal to the collateral asset
     * @return credited amount
     */
    function _swapForPoolTokens(
        IExchangeHelper Exchange,
        IExchangeHelper.SwapArgs calldata s,
        address tokenOut
    ) internal returns (uint256) {
        if (msg.value > 0) {
            require(s.tokenIn == address(WETH), "tokenIn != wETH");
            WETH.deposit{value: msg.value}();
            WETH.safeTransfer(address(Exchange), msg.value);
        }

        if (s.amountInMax > 0) {
            IERC20(s.tokenIn).safeTransferFrom(
                msg.sender,
                address(Exchange),
                s.amountInMax
            );
        }

        uint256 amountCredited =
            Exchange.swapWithToken(
                s.tokenIn,
                tokenOut,
                s.amountInMax + msg.value,
                s.callee,
                s.allowanceTarget,
                s.data,
                s.refundAddress
            );

        require(
            amountCredited >= s.amountOutMin,
            "not enough output from trade"
        );

        return amountCredited;
    }

    /************************************************
     *  ERC1155 OVERRIDES
     ***********************************************/

    /**
     * @notice ERC1155 hook, called before all transfers including mint and burn
     * @dev function should be overridden and new implementation must call super
     * @dev called for both single and batch transfers
     * @param operator executor of transfer
     * @param from sender of tokens
     * @param to receiver of tokens
     * @param ids token IDs
     * @param amounts quantities of tokens to transfer
     * @param data data payload
     */

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
        override(ERC1155BaseInternal, ERC1155EnumerableInternal)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

