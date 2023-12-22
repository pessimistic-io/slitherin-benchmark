// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import "./AccessControlEnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IMuxLiquidityCallback.sol";
import "./LibConfigSet.sol";
import "./RouterStore.sol";
import "./RouterImp.sol";

contract RouterV1 is
    RouterStore,
    Initializable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using RouterImp for RouterStateStore;
    using LibConfigSet for LibConfigSet.ConfigSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize(
        address seniorVault,
        address juniorVault,
        address rewardController
    ) external initializer {
        __AccessControlEnumerable_init();
        _store.initialize(seniorVault, juniorVault, rewardController);
        _grantRole(DEFAULT_ADMIN, msg.sender);
    }

    // =============================================== Configs ===============================================
    function routerStatus() external view returns (RouterStatus) {
        return _store.status;
    }

    function getConfig(bytes32 configKey) external view returns (bytes32) {
        return _store.config.getBytes32(configKey);
    }

    function setConfig(bytes32 configKey, bytes32 value) external {
        require(
            hasRole(CONFIG_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN, msg.sender),
            "JuniorVault::ONLY_AUTHRIZED_ROLE"
        );
        _store.config.setBytes32(configKey, value);
    }

    function getTickets(
        uint256 begin,
        uint256 count
    ) external view returns (Ticket[] memory tickets) {
        tickets = _store.getTickets(begin, count);
    }

    function juniorLeverage(
        uint256 seniorPrice,
        uint256 juniorPrice
    ) external view returns (uint256 leverage) {
        leverage = _store.juniorLeverage(seniorPrice, juniorPrice);
    }

    function isJuniorBalanced(
        uint256 seniorPrice,
        uint256 juniorPrice
    ) external view returns (bool isBalanced, bool isRebalancing) {
        (isBalanced, , ) = _store.isJuniorBalanced(seniorPrice, juniorPrice);
        isRebalancing = _store.status == RouterStatus.Rebalance;
    }

    function depositJunior(uint256 assets) external nonReentrant {
        _store.depositJunior(msg.sender, assets);
    }

    function totalPendingJuniorWithdrawal() external view returns (uint256) {
        return _store.totalPendingJuniorWithdrawal;
    }

    function pendingJuniorWithdrawal(address account) external view returns (uint256) {
        return _store.pendingJuniorWithdrawals[account];
    }

    function totalPendingSeniorWithdrawal() external view returns (uint256) {
        return _store.totalPendingSeniorWithdrawal;
    }

    function pendingSeniorWithdrawal(address account) external view returns (uint256) {
        return _store.pendingSeniorWithdrawals[account];
    }

    function withdrawJunior(uint256 shares) external nonReentrant {
        _store.withdrawJunior(msg.sender, shares);
    }

    function depositSenior(uint256 amount) external nonReentrant {
        _store.depositSenior(msg.sender, amount);
    }

    function withdrawSenior(uint256 amount, bool acceptPenalty) external nonReentrant {
        _store.withdrawSenior(msg.sender, amount, acceptPenalty);
    }

    function handleTicket(uint64 ticketId) external nonReentrant {
        _store.handleTicket(ticketId);
    }

    function updateRewards() external nonReentrant {
        _store.updateRewards();
    }

    function rebalance(uint256 seniorPrice, uint256 juniorPrice) external onlyRole(KEEPER_ROLE) {
        _store.rebalance(seniorPrice, juniorPrice);
    }

    function cancelTicket(uint64 ticketId) external onlyRole(KEEPER_ROLE) {
        _store.cancelTicket(ticketId);
    }

    function liquidate(uint256 seniorPrice, uint256 juniorPrice) external onlyRole(KEEPER_ROLE) {
        _store.liquidate(seniorPrice, juniorPrice);
    }

    function beforeFillLiquidityOrder(
        IMuxLiquidityCallback.LiquidityOrder calldata order,
        uint96 assetPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external nonReentrant returns (bool isValid) {
        address orderBook = _store.config.mustGetAddress(MUX_ORDER_BOOK);
        require(msg.sender == orderBook, "RouterV1::ONLY_ORDERBOOK");
        MuxOrderContext memory context = MuxOrderContext({
            orderId: order.id,
            seniorAssetId: order.assetId,
            seniorPrice: assetPrice,
            juniorPrice: mlpPrice,
            currentSeniorValue: currentAssetValue,
            targetSeniorValue: targetAssetValue
        });
        isValid = _store.beforeOrderFilled(context);
    }

    function afterFillLiquidityOrder(
        IMuxLiquidityCallback.LiquidityOrder calldata order,
        uint256 amountOut,
        uint96 seniorPrice,
        uint96 juniorPrice,
        uint96 currentSeniorValue,
        uint96 targetSeniorValue
    ) external nonReentrant {
        address orderBook = _store.config.mustGetAddress(MUX_ORDER_BOOK);
        require(
            msg.sender == orderBook || hasRole(KEEPER_ROLE, msg.sender),
            "RouterV1::ONLY_ORDERBOOK_OR_KEEPER"
        );
        MuxOrderContext memory context = MuxOrderContext({
            orderId: order.id,
            seniorAssetId: order.assetId,
            seniorPrice: seniorPrice,
            juniorPrice: juniorPrice,
            currentSeniorValue: currentSeniorValue,
            targetSeniorValue: targetSeniorValue
        });
        _store.onOrderFilled(context, amountOut);
    }

    function afterCancelLiquidityOrder(
        IMuxLiquidityCallback.LiquidityOrder calldata order
    ) external nonReentrant {
        address orderBook = _store.config.mustGetAddress(MUX_ORDER_BOOK);
        require(msg.sender == orderBook, "RouterV1::ONLY_ORDERBOOK");
        _store.onOrderCancelled(order.id);
    }
}

