//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IOracle} from "./IOracle.sol";
import {IPoolOracle} from "./IPoolOracle.sol";
import "./access_AccessControl.sol";
import "./ERC721Holder.sol";
import "./SafeTransferLib.sol";
import "./SafeCast.sol";
import "./token_ERC20.sol";
import "./WETH.sol";
import "./FixedPointMathLib.sol";
import "./IContangoYield.sol";
import "./YieldUtils.sol";
import "./SignedMath.sol";
import "./IOrderManager.sol";
import "./IContangoOracle.sol";
import "./Errors.sol";
import "./Balanceless.sol";
import "./ContangoPositionNFT.sol";

contract OrderManagerContangoYield is IOrderManager, ERC721Holder, AccessControl, Balanceless {
    using SafeTransferLib for *;
    using SafeCast for *;
    using SignedMath for int256;
    using YieldUtils for *;
    using FixedPointMathLib for *;

    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes6 public constant ETH_ID = "00";

    IContangoYield public immutable contango;
    ContangoPositionNFT public immutable positionNFT;
    ICauldron public immutable cauldron;
    WETH public immutable weth;
    IOracle public immutable oracle;
    IPoolOracle public immutable poolOracle;
    IContangoOracle public immutable contangoOracle;

    mapping(bytes32 => bool) public orders;
    uint256 public gasMultiplier;
    uint256 public gasStart = 21_000;

    constructor(
        uint256 _gasMultiplier,
        IContangoYield _contango,
        ContangoPositionNFT _positionNFT,
        ICauldron _cauldron,
        WETH _weth,
        IOracle _oracle,
        IPoolOracle _poolOracle,
        IContangoOracle _contangoOracle
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        gasMultiplier = _gasMultiplier;
        contango = _contango;
        positionNFT = _positionNFT;
        cauldron = _cauldron;
        weth = _weth;
        oracle = _oracle;
        poolOracle = _poolOracle;
        contangoOracle = _contangoOracle;
    }

    // ====================================== Setters ======================================

    function setGasMultiplier(uint256 _gasMultiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gasMultiplier = _gasMultiplier;
    }

    // ====================================== Linked Orders ======================================

    function placeLinkedOrder(PositionId positionId, OrderType orderType, uint256 triggerCost, uint256 limitCost)
        external
        override
    {
        address owner = _verifyPosition(positionId);

        bytes32 orderHash = hashLinkedOrder(positionId, owner, orderType, triggerCost, limitCost);
        orders[orderHash] = true;

        emit LinkedOrderPlaced(orderHash, owner, positionId, orderType, triggerCost, limitCost);
    }

    function executeLinkedOrder(
        PositionId positionId,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) external override gasMeasured onlyRole(KEEPER) returns (uint256 keeperReward) {
        address owner = positionNFT.positionOwner(positionId);

        bytes32 orderHash = hashLinkedOrder(positionId, owner, orderType, triggerCost, limitCost);

        if (!orders[orderHash]) revert OrderNotFound();
        // remove the order
        orders[orderHash] = false;

        positionNFT.safeTransferFrom(owner, address(this), PositionId.unwrap(positionId));

        keeperReward =
            _modifyPosition(positionId, owner, orderType, triggerCost, limitCost, lendingLiquidity, uniswapFee);

        emit LinkedOrderExecuted(
            orderHash, owner, positionId, orderType, triggerCost, limitCost, keeperReward, lendingLiquidity, uniswapFee
        );
    }

    function cancelLinkedOrder(PositionId positionId, OrderType orderType, uint256 triggerCost, uint256 limitCost)
        external
        override
    {
        bytes32 orderHash = hashLinkedOrder(positionId, msg.sender, orderType, triggerCost, limitCost);
        orders[orderHash] = false;

        emit LinkedOrderCancelled(orderHash, msg.sender, positionId, orderType, triggerCost, limitCost);
    }

    // ====================================== Lever Orders ======================================

    function placeLeverOrder(
        PositionId positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    ) external override {
        address owner = _verifyPosition(positionId);

        bytes32 orderHash =
            hashLeverOrder(positionId, owner, triggerLeverage, targetLeverage, oraclePriceTolerance, recurrent);
        orders[orderHash] = true;

        emit LeverOrderPlaced(
            orderHash, owner, positionId, triggerLeverage, targetLeverage, oraclePriceTolerance, recurrent
        );
    }

    function executeLeverOrder(
        PositionId positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        uint256 lendingLiquidity,
        bool recurrent
    ) external override gasMeasured onlyRole(KEEPER) returns (uint256 keeperReward) {
        address owner = positionNFT.positionOwner(positionId);

        bytes32 orderHash =
            hashLeverOrder(positionId, owner, triggerLeverage, targetLeverage, oraclePriceTolerance, recurrent);

        if (!orders[orderHash]) revert OrderNotFound();
        orders[orderHash] = recurrent;

        positionNFT.safeTransferFrom(owner, address(this), PositionId.unwrap(positionId));

        uint256 currentLeverage;
        (keeperReward, currentLeverage) = _modifyCollateral(
            ModifyCollateralParams(
                positionId, owner, triggerLeverage, targetLeverage, oraclePriceTolerance, lendingLiquidity
            )
        );

        emit LeverOrderExecuted(
            orderHash,
            owner,
            positionId,
            keeperReward,
            triggerLeverage,
            targetLeverage,
            currentLeverage,
            oraclePriceTolerance,
            lendingLiquidity,
            recurrent
        );
    }

    function cancelLeverOrder(
        PositionId positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    ) external override {
        bytes32 orderHash =
            hashLeverOrder(positionId, msg.sender, triggerLeverage, targetLeverage, oraclePriceTolerance, recurrent);
        orders[orderHash] = false;

        emit LeverOrderCancelled(
            orderHash, msg.sender, positionId, triggerLeverage, targetLeverage, oraclePriceTolerance, recurrent
        );
    }

    // ====================================== Other ======================================

    function collectBalance(ERC20 token, address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _collectBalance(token, to, amount);
    }

    // ====================================== Internal ======================================

    function _modifyPosition(
        PositionId positionId,
        address owner,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) internal returns (uint256 keeperReward) {
        Position memory position = contango.position(positionId);

        YieldInstrument memory instrument = contango.yieldInstrumentV2(position.symbol);

        uint256 balanceBefore = instrument.quote.balanceOf(address(this));

        if (orderType == OrderType.StopLoss) {
            uint256 closingCost = contangoOracle.closingCost(positionId, uniswapFee, 60);
            if (triggerCost < closingCost) {
                revert TriggerCostNotReached(closingCost, triggerCost);
            }
        }

        contango.modifyPosition({
            positionId: positionId,
            quantity: -int256(position.openQuantity),
            limitCost: limitCost,
            collateral: 0,
            payerOrReceiver: address(this),
            lendingLiquidity: lendingLiquidity,
            uniswapFee: uniswapFee
        });

        uint256 balanceAfter = instrument.quote.balanceOf(address(this));

        keeperReward = _keeperReward(instrument.quote, instrument.quoteId);
        _transferOut(instrument.quote, msg.sender, keeperReward);
        _transferOut(instrument.quote, owner, balanceAfter - balanceBefore - keeperReward);
    }

    struct ModifyCollateralParams {
        PositionId positionId;
        address owner;
        uint256 triggerLeverage;
        uint256 targetLeverage;
        uint256 oraclePriceTolerance;
        uint256 lendingLiquidity;
    }

    function _modifyCollateral(ModifyCollateralParams memory params)
        internal
        returns (uint256 keeperReward, uint256 currentLeverage)
    {
        int256 collateral;
        uint256 collateralFV;
        ERC20 quote;
        bool isReLever;
        bytes6 quoteId;
        (currentLeverage, collateral, collateralFV, quote, isReLever, quoteId) = _collateral(params);

        uint256 multiplier = collateral < 0 ? 1e18 + params.oraclePriceTolerance : 1e18 - params.oraclePriceTolerance;
        uint256 slippageTolerance = collateralFV * multiplier / 1e18;

        if (!isReLever) {
            quote.safeTransferFrom(params.owner, address(contango), collateral.abs());
        }

        contango.modifyCollateral({
            positionId: params.positionId,
            collateral: collateral,
            slippageTolerance: slippageTolerance,
            payerOrReceiver: isReLever ? address(this) : address(contango),
            lendingLiquidity: params.lendingLiquidity
        });

        positionNFT.safeTransferFrom(address(this), params.owner, PositionId.unwrap(params.positionId));

        keeperReward = _keeperReward(quote, quoteId);
        if (isReLever) {
            _transferOut(quote, params.owner, collateral.abs() - keeperReward);
        } else {
            quote.safeTransferFrom(params.owner, address(this), keeperReward);
        }

        _transferOut(quote, msg.sender, keeperReward);
    }

    function _keeperReward(ERC20 quote, bytes6 quoteId) internal returns (uint256 keeperReward) {
        uint256 rate;
        if (address(quote) != address(weth)) {
            DataTypes.Series memory series = cauldron.series(quoteId);
            (rate,) = oracle.get(ETH_ID, series.baseId, 1 ether);
        }

        // 21000 min tx gas (starting gasStart value) + gas used so far + 16 gas per byte of data + 60k for the 2 ERC20 transfers
        uint256 gasSpent = gasStart - gasleft() + 16 * msg.data.length + 60_000;
        // Keeper receives a multiplier of the gas spent @ (current baseFee + 3 wei for tip)
        keeperReward = gasSpent * gasMultiplier * block.basefee + 3;

        if (rate > 0) {
            keeperReward = keeperReward * rate / 1 ether;
        }
    }

    function _transferOut(ERC20 token, address to, uint256 amount) internal {
        if (address(token) == address(weth)) {
            weth.withdraw(amount);
            to.safeTransferETH(amount);
        } else {
            token.safeTransfer(to, amount);
        }
    }

    function _collateral(ModifyCollateralParams memory params)
        internal
        returns (
            uint256 currentLeverage,
            int256 collateral,
            uint256 collateralFV,
            ERC20 quote,
            bool isReLever,
            bytes6 quoteId
        )
    {
        Position memory position = contango.position(params.positionId);

        YieldInstrument memory instrument = contango.yieldInstrumentV2(position.symbol);
        quote = instrument.quote;
        quoteId = instrument.quoteId;

        DataTypes.Balances memory balances = cauldron.balances(params.positionId.toVaultId());

        isReLever = params.targetLeverage > params.triggerLeverage;

        uint256 underlyingCollateral;
        (currentLeverage, underlyingCollateral) = _positionLeverage(instrument, balances);

        {
            // take profit scenario, aka re-lever
            if (isReLever && currentLeverage > params.triggerLeverage) {
                revert LeverageNotReached(currentLeverage, params.triggerLeverage);
            }
            // stop loss scenario, aka de-lever
            if (!isReLever && currentLeverage < params.triggerLeverage) {
                revert LeverageNotReached(currentLeverage, params.triggerLeverage);
            }
        }

        (collateral, collateralFV) =
            _deriveCollateralFromLeverage(instrument, balances, underlyingCollateral, params.targetLeverage);
    }

    function _deriveCollateralFromLeverage(
        YieldInstrument memory instrument,
        DataTypes.Balances memory balances,
        uint256 underlyingCollateral,
        uint256 leverage
    ) internal returns (int256 collateral, uint128 collateralFV) {
        uint256 debtFV =
            (((-int256(underlyingCollateral) * 1e18) / int256(leverage)) + int256(underlyingCollateral)).toUint256();

        if (debtFV > balances.art) {
            // Debt needs to increase to reach the desired leverage
            collateralFV = debtFV.toUint128() - balances.art;
            (uint256 collateralPV,) = poolOracle.getSellFYTokenPreview(instrument.quotePool, collateralFV);
            collateral = -int256(collateralPV);
        } else {
            // Debt needs to be burnt to reach the desired leverage
            collateralFV = balances.art - debtFV.toUint128();
            (uint256 collateralPV,) = poolOracle.getBuyFYTokenPreview(instrument.quotePool, collateralFV);
            collateral = int256(collateralPV);
        }
    }

    function _positionLeverage(YieldInstrument memory instrument, DataTypes.Balances memory balances)
        private
        returns (uint256 leverage, uint256 underlyingCollateral)
    {
        DataTypes.Series memory series = cauldron.series(instrument.quoteId);
        DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(series.baseId, instrument.baseId);

        (underlyingCollateral,) = spotOracle.oracle.get(instrument.baseId, series.baseId, balances.ink);

        uint256 multiplier = 10 ** (instrument.quote.decimals());
        uint256 margin = (underlyingCollateral - balances.art) * multiplier / underlyingCollateral;
        leverage = 1e18 * multiplier / margin;
    }

    function _verifyPosition(PositionId positionId) internal view returns (address owner) {
        owner = positionNFT.positionOwner(positionId);
        if (owner != msg.sender) revert NotPositionOwner();
        if (
            positionNFT.getApproved(PositionId.unwrap(positionId)) != address(this)
                && !positionNFT.isApprovedForAll(owner, address(this))
        ) revert PositionNotApproved();
    }

    function hashLinkedOrder(
        PositionId positionId,
        address owner,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(positionId, owner, orderType, triggerCost, limitCost));
    }

    function hashLeverOrder(
        PositionId positionId,
        address owner,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(positionId, owner, triggerLeverage, targetLeverage, oraclePriceTolerance, recurrent)
        );
    }

    /// @dev `weth.withdraw` will send ether using this function.
    receive() external payable {
        if (msg.sender != address(weth)) {
            revert OnlyFromWETH(msg.sender);
        }
    }

    modifier gasMeasured() {
        gasStart += gasleft();
        _;
        gasStart = 21_000;
    }
}

