//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

import {Balanceless} from "./Balanceless.sol";
import {ContangoPositionNFT} from "./ContangoPositionNFT.sol";
import {Batchable} from "./Batchable.sol";
import {PermitForwarder} from "./PermitForwarder.sol";
import {IWETH9, WethHandler} from "./WethHandler.sol";
import {IContango} from "./IContango.sol";
import {IContangoView} from "./IContangoView.sol";
import {IFeeModel} from "./IFeeModel.sol";
import {Position, PositionId, Symbol} from "./interfaces_DataTypes.sol";
import {CodecLib} from "./CodecLib.sol";
import {FunctionNotFound} from "./ErrorLib.sol";
import {ConfigStorageLib, StorageLib} from "./StorageLib.sol";
import {ClosingOnly} from "./ErrorLib.sol";

/// @title ContangoBase
/// @notice Base contract that implements all common interfaces and function for all underlying implementations
abstract contract ContangoBase is
    IContango,
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

    // solhint-disable-next-line no-empty-blocks
    constructor(IWETH9 _weth) WethHandler(_weth) {}

    // solhint-disable-next-line func-name-mixedcase
    function __ContangoBase_init(ContangoPositionNFT _positionNFT, address _treasury) public onlyInitializing {
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        ConfigStorageLib.setTreasury(_treasury);
        ConfigStorageLib.setPositionNFT(_positionNFT);
    }

    // ============================================== Admin functions ==============================================

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

    function setFeeModel(Symbol symbol, IFeeModel _feeModel) external onlyRole(DEFAULT_ADMIN_ROLE) {
        StorageLib.setFeeModel(symbol, _feeModel);
    }

    function collectBalance(address token, address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /// @inheritdoc IContangoView
    function position(PositionId positionId) public view virtual override returns (Position memory _position) {
        _position.symbol = StorageLib.getPositionInstrument()[positionId];
        (_position.openQuantity, _position.openCost) = StorageLib.getPositionNotionals()[positionId].decodeU128();
        (int256 collateral, int256 fees) = StorageLib.getPositionBalances()[positionId].decodeI128();
        (_position.collateral, _position.protocolFees) = (collateral, uint256(fees));

        _position.maturity = StorageLib.getInstruments()[_position.symbol].maturity;
        _position.feeModel = feeModel(_position.symbol);
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

