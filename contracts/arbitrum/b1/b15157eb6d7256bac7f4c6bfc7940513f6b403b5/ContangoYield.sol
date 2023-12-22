//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

import {IContangoLadle} from "./IContangoLadle.sol";
import {IContangoWitchListener} from "./IContangoWitchListener.sol";
import {IPoolView} from "./IPoolView.sol";
import {Yield} from "./Yield.sol";
import {YieldUtils} from "./YieldUtils.sol";

import {Balanceless} from "./Balanceless.sol";
import {ContangoPositionNFT} from "./ContangoPositionNFT.sol";
import {Batchable} from "./Batchable.sol";
import {PermitForwarder} from "./PermitForwarder.sol";
import {IWETH9, WethHandler} from "./WethHandler.sol";
import {IContango, IContangoView, IFeeModel} from "./IContango.sol";
import {Instrument, Position, PositionId, Symbol, YieldInstrument} from "./src_DataTypes.sol";
import {CodecLib} from "./CodecLib.sol";
import {FunctionNotFound} from "./ErrorLib.sol";

import {ConfigStorageLib, StorageLib, YieldStorageLib} from "./StorageLib.sol";
import "./IUniswapV3SwapCallback.sol";
import {ClosingOnly} from "./ErrorLib.sol";

/// @title ContangoYield
/// @notice Contract that acts as the main entry point to the protocol with yoeld-protocol as the underlying
/// @author Bruno Bonanno
/// @dev This is the main entry point to the system when using yield-protocol as the underlying,
/// any UI/contract should be just interacting with this contract children's + the NFT for ownership management
contract ContangoYield is
    IContango,
    IContangoWitchListener,
    IUniswapV3SwapCallback,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    Balanceless,
    Batchable,
    PermitForwarder,
    WethHandler
{
    using CodecLib for uint256;
    using YieldUtils for Symbol;

    bytes32 public constant WITCH = keccak256("WITCH");

    // solhint-disable-next-line no-empty-blocks
    constructor(IWETH9 _weth) WethHandler(_weth) {}

    function initialize(
        ContangoPositionNFT _positionNFT,
        address _treasury,
        IContangoLadle _ladle,
        IPoolView _poolView
    ) public initializer {
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        ConfigStorageLib.setTreasury(_treasury);
        ConfigStorageLib.setPositionNFT(_positionNFT);

        YieldStorageLib.setLadle(_ladle);
        YieldStorageLib.setCauldron(_ladle.cauldron());
        YieldStorageLib.setPoolView(_poolView);
    }

    // ============================================== Trading functions ==============================================

    /// @inheritdoc IContango
    function createPosition(
        Symbol symbol,
        address trader,
        uint256 quantity,
        uint256 limitCost,
        uint256 collateral,
        address payer,
        bool force
    ) external payable override nonReentrant whenNotPaused whenNotClosingOnly(int256(quantity)) returns (PositionId) {
        return Yield.createPosition(symbol, trader, quantity, limitCost, collateral, payer, force);
    }

    /// @inheritdoc IContango
    function modifyCollateral(
        PositionId positionId,
        int256 collateral,
        uint256 slippageTolerance,
        address payerOrReceiver,
        bool force
    ) external payable override nonReentrant whenNotPaused {
        Yield.modifyCollateral(positionId, collateral, slippageTolerance, payerOrReceiver, force);
    }

    /// @inheritdoc IContango
    function modifyPosition(
        PositionId positionId,
        int256 quantity,
        uint256 limitCost,
        int256 collateral,
        address payerOrReceiver,
        bool force
    ) external payable override nonReentrant whenNotPaused whenNotClosingOnly(quantity) {
        Yield.modifyPosition(positionId, quantity, limitCost, collateral, payerOrReceiver, force);
    }

    /// @inheritdoc IContango
    function deliver(
        PositionId positionId,
        address payer,
        address to
    ) external payable override nonReentrant whenNotPaused {
        Yield.deliver(positionId, payer, to);
    }

    // solhint-disable-next-line no-empty-blocks
    function auctionStarted(bytes12 vaultId) external override {}

    function collateralBought(
        bytes12 vaultId,
        uint256 ink,
        uint256 art
    ) external override nonReentrant onlyRole(WITCH) {
        Yield.collateralBought(vaultId, ink, art);
    }

    // solhint-disable-next-line no-empty-blocks
    function auctionEnded(bytes12 vaultId, address owner) external override {}

    // ============================================== Callback functions ==============================================

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        Yield.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }

    // ============================================== Admin functions ==============================================

    function createYieldInstrument(
        Symbol _symbol,
        bytes6 _baseId,
        bytes6 _quoteId,
        uint24 _uniswapFee,
        IFeeModel _feeModel
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (Instrument memory, YieldInstrument memory) {
        return YieldStorageLib.createInstrument(_symbol, _baseId, _quoteId, _uniswapFee, _feeModel);
    }

    function yieldInstrument(Symbol symbol) external view returns (Instrument memory, YieldInstrument memory) {
        return symbol.loadInstrument();
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setClosingOnly(bool _closingOnly) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ConfigStorageLib.setClosingOnly(_closingOnly);
    }

    function setTrustedToken(address token, bool trusted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ConfigStorageLib.setTrustedToken(token, trusted);
    }

    function collectBalance(
        address token,
        address payable to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _collectBalance(token, to, amount);
    }

    modifier whenNotClosingOnly(int256 quantity) {
        if (quantity > 0 && ConfigStorageLib.getClosingOnly()) {
            revert ClosingOnly();
        }
        _;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============================================== View functions ==============================================

    // TODO these could go to a common View

    /// @inheritdoc IContangoView
    function position(PositionId positionId) public view virtual override returns (Position memory _position) {
        _position.symbol = StorageLib.getPositionInstrument()[positionId];
        (_position.openQuantity, _position.openCost) = StorageLib.getPositionNotionals()[positionId].decodeU128();
        (int256 collateral, int256 fees) = StorageLib.getPositionBalances()[positionId].decodeI128();
        (_position.collateral, _position.protocolFees) = (collateral, uint256(fees));

        _position.maturity = StorageLib.getInstrument(positionId).maturity;
        _position.feeModel = StorageLib.getInstrumentFeeModel(positionId);
    }

    /// @inheritdoc IContangoView
    function feeModel(Symbol symbol) public view override returns (IFeeModel) {
        return StorageLib.getInstrumentFeeModel()[symbol];
    }

    /// @notice reverts on fallback for informational purposes
    fallback() external payable {
        revert FunctionNotFound(msg.sig);
    }
}

