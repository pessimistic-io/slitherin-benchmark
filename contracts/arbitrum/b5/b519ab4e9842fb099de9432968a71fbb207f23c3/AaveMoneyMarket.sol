//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./Math.sol";
import "./FlashLoanReceiverBase.sol";
import "./IAaveRewardsController.sol";

import "./BaseMoneyMarket.sol";
import "./IFlashBorrowProvider.sol";
import "./TransferLib.sol";
import "./Arrays.sol";
import "./AaveUtils.sol";

contract AaveMoneyMarket is BaseMoneyMarket, FlashLoanReceiverBase, IFlashBorrowProvider {
    using SafeERC20 for *;
    using TransferLib for *;
    using AaveUtils for IPool;

    bool public constant override NEEDS_ACCOUNT = true;
    uint256 public constant VARIABLE = 2;

    MoneyMarket public immutable override moneyMarketId;
    IAaveRewardsController public immutable rewardsController;

    constructor(
        MoneyMarket _moneyMarketId,
        IContango _contango,
        IPoolAddressesProvider _provider,
        IAaveRewardsController _rewardsController
    ) BaseMoneyMarket(_contango) FlashLoanReceiverBase(_provider) {
        moneyMarketId = _moneyMarketId;
        rewardsController = _rewardsController;
    }

    // ====== IMoneyMarket =======

    function _initialise(PositionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        uint256 eModeCategory = POOL.eModeCategory(collateralAsset, debtAsset);
        if (eModeCategory > 0) POOL.setUserEMode(uint8(eModeCategory));
        collateralAsset.forceApprove(address(POOL), type(uint256).max);
        debtAsset.forceApprove(address(POOL), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal view override returns (uint256 balance) {
        return POOL.collateralBalance(asset, address(this));
    }

    function _lend(PositionId, IERC20 asset, uint256 amount, address payer)
        internal
        override
        returns (uint256 actualAmount)
    {
        actualAmount = asset.transferOut(payer, address(this), amount);
        POOL.supply({asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0});
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to)
        internal
        override
        returns (uint256 actualAmount)
    {
        POOL.borrow({
            asset: address(asset),
            amount: amount,
            interestRateMode: VARIABLE,
            onBehalfOf: address(this),
            referralCode: 0
        });

        actualAmount = asset.transferOut(address(this), to, amount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer)
        internal
        override
        returns (uint256 actualAmount)
    {
        actualAmount = Math.min(amount, POOL.debtBalance(asset, address(this)));
        if (actualAmount > 0) {
            asset.transferOut(payer, address(this), actualAmount);
            actualAmount = POOL.repay({
                asset: address(asset),
                amount: actualAmount,
                interestRateMode: VARIABLE,
                onBehalfOf: address(this)
            });
        }
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to)
        internal
        override
        returns (uint256 actualAmount)
    {
        actualAmount = POOL.withdraw({asset: address(asset), amount: amount, to: to});
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal override {
        rewardsController.claimAllRewards(
            toArray(
                POOL.getReserveData(address(collateralAsset)).aTokenAddress,
                POOL.getReserveData(address(debtAsset)).variableDebtTokenAddress
            ),
            to
        );
    }

    // ===== IFlashBorrowProvider =====

    struct MetaParams {
        bytes params;
        function(IERC20, uint256, bytes memory) external returns (bytes memory) callback;
    }

    bytes internal tmpResult;

    function flashBorrow(
        IERC20 asset,
        uint256 amount,
        bytes calldata params,
        function(IERC20, uint256, bytes memory) external returns (bytes memory) callback
    ) public override onlyContango returns (bytes memory result) {
        POOL.flashLoan({
            receiverAddress: address(this),
            assets: toArray(address(asset)),
            amounts: toArray(amount),
            interestRateModes: toArray(VARIABLE),
            onBehalfOf: address(this),
            params: abi.encode(MetaParams({params: params, callback: callback})),
            referralCode: 0
        });

        result = tmpResult;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(POOL) && initiator == address(this), "Invalid sender/initiator");

        MetaParams memory metaParams = abi.decode(params, (MetaParams));

        IERC20(assets[0]).safeTransfer(metaParams.callback.address, amounts[0]);

        tmpResult = metaParams.callback(IERC20(assets[0]), amounts[0], metaParams.params);

        return true;
    }

    function supportsInterface(bytes4 interfaceId) public pure override(BaseMoneyMarket, IERC165) returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId || interfaceId == type(IFlashBorrowProvider).interfaceId;
    }
}

