//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./IUniswapV3SwapCallback.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./UUPSUpgradeable.sol";

import "./Balanceless.sol";
import "./ContangoPositionNFT.sol";
import "./Batchable.sol";
import "./PermitForwarder.sol";
import "./WethHandler.sol";
import "./IContango.sol";
import "./IContangoAdmin.sol";
import "./libraries_DataTypes.sol";
import "./CodecLib.sol";
import "./Errors.sol";
import "./StorageLib.sol";

/// @notice Base contract that implements all common interfaces and function for all underlying implementations
abstract contract ContangoBase is
    IContango,
    IContangoAdmin,
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

    bytes32 public constant EMERGENCY_BREAK = keccak256("EMERGENCY_BREAK");
    bytes32 public constant OPERATOR = keccak256("OPERATOR");

    // solhint-disable-next-line no-empty-blocks
    constructor(WETH _weth) WethHandler(_weth) {}

    // solhint-disable-next-line func-name-mixedcase
    function __ContangoBase_init(ContangoPositionNFT _positionNFT, address _treasury) public onlyInitializing {
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        ConfigStorageLib.setTreasury(_treasury);
        emit TreasurySet(_treasury);

        ConfigStorageLib.setPositionNFT(_positionNFT);
        emit PositionNFTSet(_positionNFT);
    }

    // ============================================== Admin functions ==============================================

    function pause() external onlyRole(EMERGENCY_BREAK) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_BREAK) {
        _unpause();
    }

    function setClosingOnly(bool _closingOnly) external override onlyRole(OPERATOR) {
        ConfigStorageLib.setClosingOnly(_closingOnly);
        emit ClosingOnlySet(_closingOnly);
    }

    function closingOnly() external view override returns (bool) {
        return ConfigStorageLib.getClosingOnly();
    }

    function setClosingOnly(Symbol symbol, bool _closingOnly) external override onlyRole(OPERATOR) {
        StorageLib.setClosingOnly(symbol, _closingOnly);
        emit ClosingOnlySet(symbol, _closingOnly);
    }

    function setTrustedToken(address token, bool trusted) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        ConfigStorageLib.setTrustedToken(token, trusted);
        emit TokenTrusted(token, trusted);
    }

    function setFeeModel(Symbol symbol, IFeeModel _feeModel) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeModel(symbol, _feeModel);
    }

    function _setFeeModel(Symbol symbol, IFeeModel _feeModel) internal {
        StorageLib.setFeeModel(symbol, _feeModel);
        emit FeeModelUpdated(symbol, _feeModel);
    }

    function collectBalance(ERC20 token, address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _collectBalance(token, to, amount);
    }

    modifier whenNotClosingOnly(int256 quantity) {
        if (quantity > 0 && ConfigStorageLib.getClosingOnly()) {
            revert ClosingOnly();
        }
        _;
    }

    function _authorizeUpgrade(address) internal view override {
        _checkRole(DEFAULT_ADMIN_ROLE);
    }

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
}

