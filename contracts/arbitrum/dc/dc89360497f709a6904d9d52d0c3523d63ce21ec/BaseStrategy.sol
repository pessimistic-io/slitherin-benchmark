// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20, IERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {NonblockingLzAppUpgradeable} from "./NonblockingLzAppUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {BytesLib} from "./NonblockingLzApp.sol";
import {Math} from "./Math.sol";
import {ECDSA} from "./ECDSA.sol";

import {ISgBridge} from "./ISgBridge.sol";
import {IStargateRouter, IStargateReceiver} from "./IStargate.sol";
import {IStrategyMessages} from "./IStrategyMessages.sol";

abstract contract BaseStrategy is
    Initializable,
    NonblockingLzAppUpgradeable,
    IStrategyMessages,
    IStargateReceiver
{
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    error InsufficientFunds(uint256 amount, uint256 balance);
    error IncorrectMessageType(uint256 messageType);

    event SgReceived(address indexed token, uint256 amount, address sender);
    event StrategyReported(
        uint256 profit,
        uint256 loss,
        uint256 debtPayment,
        uint256 giveToStrategy,
        uint256 requestFromStrategy,
        uint256 creditAvailable,
        uint256 totalAssets
    );
    event AdjustedPosition(uint256 debtOutstanding);
    event StrategyMigrated(address newStrategy);

    modifier onlyStrategist() {
        _onlyStrategist();
        _;
    }

    modifier onlyStrategistOrSelf() {
        _onlyStrategistOrSelf();
        _;
    }

    function __BaseStrategy_init(
        address _lzEndpoint,
        address _strategist,
        IERC20 _want,
        address _vault,
        uint16 _vaultChainId,
        uint16 _currentChainId,
        address _sgBridge,
        address _sgRouter,
        uint256 _slippage
    ) internal onlyInitializing {
        __NonblockingLzAppUpgradeable_init(_lzEndpoint);

        strategist = _strategist;
        want = _want;
        vaultChainId = _vaultChainId;
        vault = _vault;
        slippage = _slippage;
        wantDecimals = ERC20(address(want)).decimals();
        _signNonce = 0;
        currentChainId = _currentChainId;
        sgBridge = ISgBridge(_sgBridge);
        sgRouter = IStargateRouter(_sgRouter);

        want.approve(_sgBridge, type(uint256).max);
    }

    address public strategist;
    IERC20 public want;
    address public vault;
    uint16 public vaultChainId;
    uint16 public currentChainId;
    uint8 public wantDecimals;
    uint256 public slippage;
    bool public emergencyExit;
    ISgBridge public sgBridge;
    IStargateRouter public sgRouter;

    mapping(uint256 => bool) withdrawnInEpoch;

    uint256 internal _signNonce;

    function name() external view virtual returns (string memory);

    function estimatedTotalAssets() public view virtual returns (uint256);

    function setStrategist(address _strategist) external onlyOwner {
        strategist = _strategist;
    }

    function setEmergencyExit(bool _emergencyExit) external onlyStrategist {
        emergencyExit = _emergencyExit;
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        slippage = _slippage;
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function revokeFunds() external onlyStrategist {
        payable(strategist).transfer(address(this).balance);
    }

    function sweepToken(IERC20 _token) external onlyStrategist {
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }

    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    function strategistSignMessageHash() public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(address(this), _signNonce, currentChainId)
            );
    }

    function harvest(
        uint256 _totalDebt,
        uint256 _debtOutstanding,
        uint256 _creditAvailable,
        uint256 _debtRatio,
        bytes memory _signature
    ) external onlyStrategist {
        _verifySignature(_signature);

        uint256 profit = 0;
        uint256 loss = 0;
        uint256 debtPayment = 0;

        if (emergencyExit) {
            require(_debtRatio == 0, "BaseStrategy::DebtRatioNotZero");

            uint256 amountFreed = _liquidateAllPositions();
            if (amountFreed < _debtOutstanding) {
                loss = _debtOutstanding - amountFreed;
            } else if (amountFreed > _debtOutstanding) {
                profit = amountFreed - _debtOutstanding;
            }
            debtPayment = _debtOutstanding - loss;
        } else {
            (profit, loss, debtPayment) = _prepareReturn(
                _totalDebt,
                _debtOutstanding
            );
        }

        uint256 fundsAvailable = profit + debtPayment;
        uint256 giveToStrategy = 0;
        uint256 requestFromStrategy = 0;

        if (fundsAvailable < _creditAvailable) {
            giveToStrategy = _creditAvailable - fundsAvailable;
            requestFromStrategy = 0;
        } else {
            giveToStrategy = 0;
            requestFromStrategy = fundsAvailable - _creditAvailable;
        }

        StrategyReport memory report = StrategyReport({
            strategy: address(this),
            timestamp: block.timestamp,
            profit: profit,
            loss: loss,
            debtPayment: debtPayment,
            giveToStrategy: giveToStrategy,
            requestFromStrategy: requestFromStrategy,
            creditAvailable: _creditAvailable,
            totalAssets: estimatedTotalAssets() - requestFromStrategy,
            nonce: _signNonce++,
            signature: _signature
        });

        if (requestFromStrategy > 0) {
            _bridge(
                requestFromStrategy,
                vaultChainId,
                vault,
                abi.encode(MessageType.StrategyReport, report)
            );
        } else {
            _sendMessageToVault(abi.encode(MessageType.StrategyReport, report));
        }

        emit StrategyReported(
            report.profit,
            report.loss,
            report.debtPayment,
            report.giveToStrategy,
            report.requestFromStrategy,
            report.creditAvailable,
            report.totalAssets
        );
    }

    function adjustPosition(uint256 _debtOutstanding) public onlyStrategist {
        _adjustPosition(_debtOutstanding);
        emit AdjustedPosition(_debtOutstanding);
    }

    function sgReceive(
        uint16,
        bytes memory _srcAddress,
        uint,
        address _token,
        uint256 _amountLD,
        bytes memory
    ) external override {
        require(
            msg.sender == address(sgRouter) || msg.sender == address(sgBridge),
            "SgBridge::RouterOrBridgeOnly"
        );
        address srcAddress = address(
            bytes20(abi.encodePacked(_srcAddress.slice(0, 20)))
        );

        emit SgReceived(_token, _amountLD, srcAddress);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public virtual override {
        require(
            msg.sender == address(lzEndpoint),
            "BaseStrategy::InvalidEndpointCaller"
        );

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function _verifySignature(bytes memory _signature) internal view {
        bytes32 messageHash = strategistSignMessageHash();
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        require(
            ECDSA.recover(ethSignedMessageHash, _signature) == strategist,
            "BaseStrategy::InvalidSignature"
        );
    }

    function _adjustPosition(uint256 _debtOutstanding) internal virtual;

    function _getAdapterParams() internal view virtual returns (bytes memory) {
        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 1_000_000;
        return abi.encodePacked(version, gasForDestinationLzReceive);
    }

    function _onlyStrategist() internal view {
        require(msg.sender == strategist, "BaseStrategy::OnlyStrategist");
    }

    function _onlyStrategistOrSelf() internal view {
        require(
            msg.sender == strategist || msg.sender == address(this),
            "BaseStrategy::OnlyStrategistOrSelf"
        );
    }

    function _withSlippage(uint256 _amount) internal view returns (uint256) {
        return (_amount * slippage) / 10_000;
    }

    function _withSlippage(
        uint256 _amount,
        uint256 _slippage
    ) internal pure returns (uint256) {
        return (_amount * _slippage) / 10_000;
    }

    function _liquidatePosition(
        uint256 _amountNeeded
    ) internal virtual returns (uint256 _liquidatedAmount, uint256 _loss);

    function _liquidateAllPositions()
        internal
        virtual
        returns (uint256 _amountFreed);

    function _prepareMigration(address _newStrategy) internal virtual;

    function _prepareReturn(
        uint256 _totalDebt,
        uint256 _debtOutstanding
    ) internal returns (uint256 profit, uint256 loss, uint256 debtPayment) {
        uint256 totalAssets = estimatedTotalAssets();

        if (totalAssets >= _totalDebt) {
            profit = totalAssets - _totalDebt;
            loss = 0;
        } else {
            profit = 0;
            loss = _totalDebt - totalAssets;
        }

        _liquidatePosition(_debtOutstanding + profit);

        uint256 liquidWant = want.balanceOf(address(this));
        if (liquidWant <= profit) {
            profit = liquidWant;
            debtPayment = 0;
        } else {
            debtPayment = Math.min(liquidWant - profit, _debtOutstanding);
        }
    }

    function _handlePayload(bytes memory _payload) internal {
        MessageType messageType = abi.decode(_payload, (MessageType));
        if (messageType == MessageType.AdjustPositionRequest) {
            (, AdjustPositionRequest memory request) = abi.decode(
                _payload,
                (uint256, AdjustPositionRequest)
            );
            _adjustPosition(request.debtOutstanding);

            emit AdjustedPosition(request.debtOutstanding);
        } else if (messageType == MessageType.WithdrawSomeRequest) {
            (, WithdrawSomeRequest memory request) = abi.decode(
                _payload,
                (uint256, WithdrawSomeRequest)
            );
            _handleWithdrawSomeRequest(request);
        } else if (messageType == MessageType.MigrateStrategyRequest) {
            (, MigrateStrategyRequest memory request) = abi.decode(
                _payload,
                (uint256, MigrateStrategyRequest)
            );
            _handleMigrationRequest(request.newStrategy);

            emit StrategyMigrated(request.newStrategy);
        }
    }

    function _handleWithdrawSomeRequest(
        WithdrawSomeRequest memory _request
    ) internal {
        require(
            !withdrawnInEpoch[_request.id],
            "BaseStrategy::AlreadyWithdrawn"
        );

        (uint256 liquidatedAmount, uint256 loss) = _liquidatePosition(
            _request.amount
        );

        bytes memory payload = abi.encode(
            MessageType.WithdrawSomeResponse,
            WithdrawSomeResponse({
                source: address(this),
                amount: liquidatedAmount,
                loss: loss,
                id: _request.id
            })
        );

        if (liquidatedAmount > 0) {
            _bridge(liquidatedAmount, vaultChainId, vault, payload);
        } else {
            _sendMessageToVault(payload);
        }

        withdrawnInEpoch[_request.id] = true;
    }

    function _handleMigrationRequest(address _newStrategy) internal {
        _prepareMigration(_newStrategy);
        want.safeTransfer(_newStrategy, want.balanceOf(address(this)));
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) internal override {
        require(
            _srcChainId == vaultChainId,
            "BaseStrategy::VaultChainIdMismatch"
        );
        address srcAddress = address(
            bytes20(abi.encodePacked(_srcAddress.slice(0, 20)))
        );
        require(srcAddress == vault, "BaseStrategy::VaultAddressMismatch");

        _handlePayload(_payload);
    }

    function _bridge(
        uint256 _amount,
        uint16 _destChainId,
        address _dest,
        bytes memory _payload
    ) internal {
        uint256 fee = sgBridge.feeForBridge(_destChainId, _dest, _payload);
        sgBridge.bridge{value: fee}(
            address(want),
            _amount,
            _destChainId,
            _dest,
            _payload
        );
    }

    function _sendMessageToVault(bytes memory _payload) internal {
        bytes memory remoteAndLocalAddresses = abi.encodePacked(
            vault,
            address(this)
        );

        (uint256 nativeFee, ) = lzEndpoint.estimateFees(
            vaultChainId,
            address(this),
            _payload,
            false,
            _getAdapterParams()
        );

        if (address(this).balance < nativeFee) {
            revert InsufficientFunds(nativeFee, address(this).balance);
        }

        lzEndpoint.send{value: nativeFee}(
            vaultChainId,
            remoteAndLocalAddresses,
            _payload,
            payable(address(this)),
            address(this),
            _getAdapterParams()
        );
    }

    receive() external payable {}

    /* === DEBUG FUNCTIONS === */

    function clearWant() external onlyStrategist {
        want.safeTransfer(address(1), want.balanceOf(address(this)));
    }

    function callMe(uint256 epoch) external onlyOwner {
        withdrawnInEpoch[epoch] = false;
    }
}

