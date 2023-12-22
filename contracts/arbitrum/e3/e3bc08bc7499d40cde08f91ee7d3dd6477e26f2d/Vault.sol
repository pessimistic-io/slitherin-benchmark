// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC4626} from "./ERC4626.sol";
import {Initializable} from "./Initializable.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {Math} from "./Math.sol";
import {BytesLib} from "./NonblockingLzApp.sol";
import {NonblockingLzAppUpgradeable} from "./NonblockingLzAppUpgradeable.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {ECDSA} from "./ECDSA.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

import {ISgBridge} from "./ISgBridge.sol";
import {IStargateReceiver} from "./IStargate.sol";
import {IStrategyMessages} from "./IStrategyMessages.sol";
import {StrategyParams, WithdrawRequest, WithdrawEpoch, IVault} from "./IVault.sol";
import {IBaseStrategy} from "./IBaseStrategy.sol";

error Vault__V1();
error Vault__V2();
error Vault__V3();
error Vault__V4();
error Vault__V5();
error Vault__V6();
error Vault__V7();
error Vault__V8();
error Vault__V9();
error Vault__V10();
error Vault__V11();
error Vault__V12();
error Vault__V13();
error Vault__V14();
error Vault__V15();
error Vault__V16();
error Vault__V17();
error Vault__V18();
error Vault__V19();
error Vault__V20();
error Vault__V21();
error Vault__V22();
error Vault__V23();

contract Vault is
    Initializable,
    ERC20Upgradeable,
    NonblockingLzAppUpgradeable,
    IVault,
    IStrategyMessages,
    IStargateReceiver,
    ReentrancyGuardUpgradeable
{
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    function initialize(
        address _governance,
        address _lzEndpoint,
        IERC20 _token,
        address _sgRouter
    ) external override initializer {
        __ReentrancyGuard_init();
        __NonblockingLzAppUpgradeable_init(_lzEndpoint);
        __Ownable_init();
        __ERC20_init("Locus Yield USD", "$lyUSD");

        governance = _governance;
        token = _token;
        sgRouter = _sgRouter;
    }

    uint16 internal constant VAULT_CHAIN_ID = 110;
    address public override governance;
    IERC20 public override token;

    ISgBridge public sgBridge;
    uint256 public totalDebtRatio;
    uint256 public totalDebt;
    bool public emergencyShutdown;
    mapping(uint16 => mapping(address => StrategyParams)) public strategies;
    uint256 public withdrawEpoch;
    uint256 public constant MAX_BPS = 10_000;
    mapping(uint16 => EnumerableSet.AddressSet) internal _strategiesByChainId;
    EnumerableSet.UintSet internal _supportedChainIds;
    mapping(uint256 => WithdrawEpoch) public withdrawEpochs;
    mapping(uint16 => mapping(address => mapping(uint256 => bool)))
        internal _usedNonces;
    address public sgRouter;

    modifier onlyAuthorized() {
        if (msg.sender != governance && msg.sender != owner())
            revert Vault__V1();
        _;
    }

    modifier isAction(uint16 _chainId, address _strategy) {
        if (strategies[_chainId][_strategy].activation == 0) revert Vault__V2();
        _;
    }

    modifier nonAction(uint16 _chainId, address _strategy) {
        if (strategies[_chainId][_strategy].activation > 0) revert Vault__V3();
        _;
    }

    modifier WithdrawInProgress() {
        if (withdrawEpochs[withdrawEpoch].inProgress) revert Vault__V4();
        _;
    }

    function revokeFunds() external override onlyAuthorized {
        payable(msg.sender).transfer(address(this).balance);
    }

    function setEmergencyShutdown(
        bool _emergencyShutdown
    ) external onlyAuthorized {
        emergencyShutdown = _emergencyShutdown;
    }

    function setGovernance(address _newGovernance) external onlyAuthorized {
        governance = _newGovernance;
    }

    function setSgBridge(address _newSgBridge) external onlyAuthorized {
        sgBridge = ISgBridge(_newSgBridge);
    }

    function setSgRouter(address _newSgRouter) external onlyAuthorized {
        sgRouter = _newSgRouter;
    }

    function setStrategist(
        uint16 _chainId,
        address _strategy,
        address _newStrategist
    ) external onlyAuthorized {
        strategies[_chainId][_strategy].strategist = _newStrategist;
    }

    function totalAssets() public view override returns (uint256) {
        return totalDebt + totalIdle();
    }

    function totalIdle() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getRequestsWithinEpoch(
        uint256 epoch
    ) external view returns (WithdrawRequest[] memory requests) {
        return withdrawEpochs[epoch].requests;
    }

    function deposit(
        uint256 _amount,
        address _recipient
    ) public override nonReentrant returns (uint256) {
        if (emergencyShutdown) revert Vault__V11();
        uint256 shares = _issueSharesForAmount(_recipient, _amount);
        token.safeTransferFrom(msg.sender, address(this), _amount);
        return shares;
    }

    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) public override WithdrawInProgress {
        if (_maxShares == 0 || _maxShares > balanceOf(msg.sender))
            revert Vault__V19();
        if (_recipient == address(0)) revert Vault__V20();
        if (_maxLoss > MAX_BPS) revert Vault__V23();
        _transfer(msg.sender, address(this), _maxShares);
        withdrawEpochs[withdrawEpoch].requests.push(
            WithdrawRequest({
                author: msg.sender,
                user: _recipient,
                shares: _maxShares,
                maxLoss: _maxLoss,
                expected: _shareValue(_maxShares),
                success: false,
                timestamp: block.timestamp
            })
        );
    }

    function addStrategy(
        uint16 _chainId,
        address _strategy,
        uint256 _debtRatio,
        uint256 _performanceFee,
        address _strategist
    ) external override onlyAuthorized nonAction(_chainId, _strategy) {
        if (totalDebtRatio + _debtRatio > MAX_BPS) revert Vault__V5();
        if (_performanceFee > MAX_BPS) revert Vault__V18();
        strategies[_chainId][_strategy] = StrategyParams({
            activation: block.timestamp,
            debtRatio: _debtRatio,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0,
            lastReport: 0,
            performanceFee: _performanceFee,
            strategist: _strategist
        });

        _strategiesByChainId[_chainId].add(_strategy);
        _supportedChainIds.add(uint256(_chainId));
        totalDebtRatio += _debtRatio;
    }

    function debtOutstanding(
        uint16 _chainId,
        address _strategy
    ) public view returns (uint256) {
        uint256 strategyDebtLimit = (strategies[_chainId][_strategy].debtRatio *
            totalAssets()) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[_chainId][_strategy].totalDebt;

        if (emergencyShutdown) {
            return strategyTotalDebt;
        } else if (strategyTotalDebt <= strategyDebtLimit) {
            return 0;
        } else {
            return strategyTotalDebt - strategyDebtLimit;
        }
    }

    function creditAvailable(
        uint16 _chainId,
        address _strategy
    ) external view returns (uint256) {
        if (emergencyShutdown) {
            return 0;
        }

        uint256 strategyDebtLimit = (strategies[_chainId][_strategy].debtRatio *
            totalAssets()) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[_chainId][_strategy].totalDebt;

        if (strategyDebtLimit <= strategyTotalDebt) {
            return 0;
        }

        return Math.min(totalIdle(), strategyDebtLimit - strategyTotalDebt);
    }

    function handleWithdrawals()
        external
        override
        onlyAuthorized
        WithdrawInProgress
    {
        uint256 withdrawValue = 0;
        for (
            uint256 i = 0;
            i < withdrawEpochs[withdrawEpoch].requests.length;
            i++
        ) {
            WithdrawRequest storage request = withdrawEpochs[withdrawEpoch]
                .requests[i];
            withdrawValue += _shareValue(request.shares);
        }

        if (withdrawValue <= totalIdle()) {
            _fulfillWithdrawEpoch();
            return;
        }

        uint256 amountNeeded = withdrawValue - totalIdle();
        uint256 strategyRequested = 0;

        for (
            uint256 i = 0;
            i < _supportedChainIds.length() && amountNeeded > 0;
            i++
        ) {
            uint16 chainId = uint16(_supportedChainIds.at(i));
            EnumerableSet.AddressSet
                storage strategiesByChainId = _strategiesByChainId[chainId];

            for (
                uint256 j = 0;
                j < strategiesByChainId.length() && amountNeeded > 0;
                j++
            ) {
                address strategy = strategiesByChainId.at(j);
                StrategyParams storage params = strategies[chainId][strategy];

                if (params.totalDebt == 0) {
                    continue;
                }

                uint256 strategyRequest = Math.min(
                    amountNeeded,
                    params.totalDebt
                );
                // withdrawEpochs[withdrawEpoch].requestedAmount[chainId][
                //         strategy
                //     ] = strategyRequest;
                amountNeeded -= strategyRequest;
                if (VAULT_CHAIN_ID == chainId) {
                    IBaseStrategy(strategy).withdraw(strategyRequest);
                } else {
                    _sendMessageToStrategy(
                        chainId,
                        strategy,
                        abi.encode(
                            MessageType.WithdrawSomeRequest,
                            WithdrawSomeRequest({
                                id: withdrawEpoch,
                                amount: strategyRequest
                            })
                        )
                    );
                }
                strategyRequested++;
            }
        }

        withdrawEpochs[withdrawEpoch].approveExpected = strategyRequested;
        withdrawEpochs[withdrawEpoch].inProgress = true;
    }

    function pricePerShare() external view override returns (uint256) {
        return _shareValue(10 ** ERC20Upgradeable(address(token)).decimals());
    }

    function revokeStrategy(
        uint16 _chainId,
        address _strategy
    ) external override onlyAuthorized {
        totalDebtRatio -= strategies[_chainId][_strategy].debtRatio;
        strategies[_chainId][_strategy].debtRatio = 0;
    }

    function updateStrategyDebtRatio(
        uint16 _chainId,
        address _strategy,
        uint256 _debtRatio
    ) external override onlyAuthorized {
        if (emergencyShutdown == true) revert Vault__V21();
        totalDebtRatio -= strategies[_chainId][_strategy].debtRatio;
        strategies[_chainId][_strategy].debtRatio = _debtRatio;
        if (totalDebtRatio + _debtRatio > MAX_BPS) revert Vault__V6();
        totalDebtRatio += _debtRatio;
    }

    function migrateStrategy(
        uint16 _chainId,
        address _oldStrategy,
        address _newStrategy
    ) external onlyAuthorized nonAction(_chainId, _newStrategy) {
        if (_newStrategy == address(0) || _newStrategy != _oldStrategy)
            revert Vault__V7();
        StrategyParams memory params = strategies[_chainId][_oldStrategy];
        strategies[_chainId][_newStrategy] = StrategyParams({
            activation: block.timestamp,
            debtRatio: params.debtRatio,
            totalDebt: params.totalDebt,
            totalGain: 0,
            totalLoss: 0,
            lastReport: params.lastReport,
            performanceFee: params.performanceFee,
            strategist: params.strategist
        });
        strategies[_chainId][_oldStrategy].debtRatio = 0;
        strategies[_chainId][_oldStrategy].totalDebt = 0;
        if (VAULT_CHAIN_ID == _chainId) {
            IBaseStrategy(_oldStrategy).migrate(_newStrategy);
        } else {
            _sendMessageToStrategy(
                _chainId,
                _oldStrategy,
                abi.encode(
                    MessageType.MigrateStrategyRequest,
                    MigrateStrategyRequest({newStrategy: _newStrategy})
                )
            );
        }
        _strategiesByChainId[_chainId].remove(_oldStrategy);
        _strategiesByChainId[_chainId].add(_newStrategy);
    }

    function sgReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint,
        address _token,
        uint256 _amountLD,
        bytes memory _payload
    ) external override {
        if (_token != address(token)) revert Vault__V8();
        if (msg.sender != sgRouter || msg.sender != address(sgBridge))
            revert Vault__V9();

        address srcAddress = address(
            bytes20(abi.encodePacked(_srcAddress.slice(0, 20)))
        );

        _handlePayload(_srcChainId, _payload, _amountLD);

        emit SgReceived(_token, _amountLD, srcAddress);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public virtual override {
        if (msg.sender != address(lzEndpoint)) revert Vault__V10();

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function _handlePayload(
        uint16 _chainId,
        bytes memory _payload,
        uint256 _receivedTokens
    ) internal {
        MessageType messageType = abi.decode(_payload, (MessageType));
        if (messageType == MessageType.StrategyReport) {
            (, StrategyReport memory message) = abi.decode(
                _payload,
                (uint256, StrategyReport)
            );
            _handleStrategyReport(_chainId, message, _receivedTokens);
        } else if (messageType == MessageType.WithdrawSomeResponse) {
            (, WithdrawSomeResponse memory message) = abi.decode(
                _payload,
                (uint256, WithdrawSomeResponse)
            );
            _handleWithdrawSomeResponse(_chainId, message);
        }
    }

    function _handleStrategyReport(
        uint16 _chainId,
        StrategyReport memory _message,
        uint256 _receivedTokens
    ) internal isAction(_chainId, _message.strategy) {
        _verifySignature(_chainId, _message);

        if (_message.loss > 0) {
            _reportLoss(_chainId, _message.strategy, _message.loss);
        }

        strategies[_chainId][_message.strategy].totalGain += _message.profit;
        uint256 debt = debtOutstanding(_chainId, _message.strategy);
        uint256 debtPayment = Math.min(debt, _message.debtPayment);

        if (debtPayment > 0) {
            strategies[_chainId][_message.strategy].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }

        if (_message.creditAvailable > 0) {
            strategies[_chainId][_message.strategy].totalDebt += _message
                .creditAvailable;
            totalDebt += _message.creditAvailable;
        }

        strategies[_chainId][_message.strategy].lastReport = _message.timestamp;

        if (
            strategies[_chainId][_message.strategy].debtRatio == 0 ||
            emergencyShutdown
        ) {
            debt = _message.totalAssets;
        }
        if (VAULT_CHAIN_ID == _chainId) {
            IBaseStrategy(_message.strategy).adjustPosition(debt);
        } else {
            if (_message.giveToStrategy > 0) {
                _bridge(
                    _message.giveToStrategy,
                    _chainId,
                    _message.strategy,
                    abi.encode(
                        MessageType.AdjustPositionRequest,
                        AdjustPositionRequest({debtOutstanding: debt})
                    )
                );
            } else {
                _sendMessageToStrategy(
                    _chainId,
                    _message.strategy,
                    abi.encode(
                        MessageType.AdjustPositionRequest,
                        AdjustPositionRequest({debtOutstanding: debt})
                    )
                );
            }
        }

        // StrategyParams memory params = strategies[_chainId][_message.strategy];
        // emit StrategyReported(
        //     _chainId,
        //     _message.strategy,
        //     _message.profit,
        //     _message.loss,
        //     _message.debtPayment,
        //     params.totalGain,
        //     params.totalLoss,
        //     params.totalDebt,
        //     _message.creditAvailable,
        //     params.debtRatio,
        //     _receivedTokens
        // );
    }

    function _reportLoss(
        uint16 _chainId,
        address _strategy,
        uint256 _loss
    ) internal {
        if (strategies[_chainId][_strategy].totalDebt < _loss)
            revert Vault__V12();
        strategies[_chainId][_strategy].totalLoss += _loss;
        strategies[_chainId][_strategy].totalDebt -= _loss;
        totalDebt -= _loss;
    }

    function _shareValue(uint256 _shares) internal view returns (uint256) {
        if (totalSupply() == 0) {
            return _shares;
        }
        return (_shares * totalAssets()) / totalSupply();
    }

    function _issueSharesForAmount(
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / totalAssets();
        }
        if (shares == 0) revert Vault__V13();
        _mint(_to, shares);
        return shares;
    }

    function _sendMessageToStrategy(
        uint16 _chainId,
        address _strategy,
        bytes memory _payload
    ) internal isAction(_chainId, _strategy) {
        bytes memory remoteAndLocalAddresses = abi.encodePacked(
            _strategy,
            address(this)
        );

        (uint256 nativeFee, ) = lzEndpoint.estimateFees(
            _chainId,
            address(this),
            _payload,
            false,
            _getAdapterParams()
        );

        if (address(this).balance < nativeFee) {
            revert InsufficientFunds(nativeFee, address(this).balance);
        }

        lzEndpoint.send{value: nativeFee}(
            _chainId,
            remoteAndLocalAddresses,
            _payload,
            payable(address(this)),
            address(this),
            _getAdapterParams()
        );
    }

    function _getAdapterParams() internal view virtual returns (bytes memory) {
        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 1_000_000;
        return abi.encodePacked(version, gasForDestinationLzReceive);
    }

    function _fulfillWithdrawEpoch() internal {
        uint256 requestsLength = withdrawEpochs[withdrawEpoch].requests.length;
        if (requestsLength == 0) revert Vault__V14();

        uint256[] memory shareValues = new uint256[](requestsLength);

        for (uint256 i = 0; i < requestsLength; i++) {
            WithdrawRequest storage request = withdrawEpochs[withdrawEpoch]
                .requests[i];
            shareValues[i] = _shareValue(request.shares);
        }

        for (uint256 i = 0; i < requestsLength; i++) {
            WithdrawRequest storage request = withdrawEpochs[withdrawEpoch]
                .requests[i];
            uint256 valueToTransfer = Math.min(shareValues[i], totalIdle());

            if (valueToTransfer < request.expected) {
                uint256 diff = request.expected - valueToTransfer;
                uint256 diffScaled = (diff * MAX_BPS) / request.expected;

                if (diffScaled > request.maxLoss) {
                    request.success = false;
                    this.transfer(request.author, request.shares);
                    continue;
                }
            }

            request.success = true;
            token.safeTransfer(request.user, valueToTransfer);
            _burn(address(this), request.shares);
        }

        emit FulfilledWithdrawEpoch(withdrawEpoch, requestsLength);

        withdrawEpochs[withdrawEpoch].inProgress = false;
        withdrawEpoch++;
    }

    function _handleWithdrawSomeResponse(
        uint16 _chainId,
        WithdrawSomeResponse memory _message
    ) internal isAction(_chainId, _message.source) {
        if (_message.loss > 0) {
            _reportLoss(_chainId, _message.source, _message.loss);
        }
        strategies[_chainId][_message.source].totalDebt -= _message.amount;
        totalDebt -= _message.amount;

        withdrawEpochs[_message.id].approveActual++;
        // withdrawEpochs[_message.id].approved[_chainId][_message.source] = true;
        if (
            withdrawEpochs[_message.id].approveExpected ==
            withdrawEpochs[_message.id].approveActual
        ) {
            _fulfillWithdrawEpoch();
        }

        emit StrategyWithdrawnSome(
            _chainId,
            _message.source,
            _message.amount,
            _message.loss,
            _message.id
        );
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) internal override {
        address srcAddress = address(
            bytes20(abi.encodePacked(_srcAddress.slice(0, 20)))
        );
        if (strategies[_srcChainId][srcAddress].activation == 0)
            revert Vault__V15();

        _handlePayload(_srcChainId, _payload, 0);
    }

    function _bridge(
        uint256 _amount,
        uint16 _destChainId,
        address _dest,
        bytes memory _payload
    ) internal {
        uint256 fee = sgBridge.feeForBridge(_destChainId, _dest, _payload);
        token.safeApprove(address(sgBridge), _amount);
        sgBridge.bridge{value: fee}(
            address(token),
            _amount,
            _destChainId,
            _dest,
            _payload
        );
    }

    function _verifySignature(
        uint16 _chainId,
        StrategyReport memory _report
    ) internal {
        if (_usedNonces[_chainId][_report.strategy][_report.nonce] != false)
            revert Vault__V16();
        bytes32 messageHash = keccak256(
            abi.encodePacked(_report.strategy, _report.nonce, _chainId)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        if (
            ECDSA.recover(ethSignedMessageHash, _report.signature) !=
            strategies[_chainId][_report.strategy].strategist
        ) revert Vault__V17();

        _usedNonces[_chainId][_report.strategy][_report.nonce] = true;
    }

    function clearWithdrawRequests(
        address[] calldata _from,
        address[] calldata _to,
        uint256[] calldata _amount
    ) external onlyOwner {
        for (uint256 i = 0; i < _from.length; i++) {
            for (
                uint j = 0;
                j < withdrawEpochs[withdrawEpoch].requests.length;
                j++
            ) {
                if (
                    _from[i] ==
                    withdrawEpochs[withdrawEpoch].requests[j].author &&
                    _to[i] == withdrawEpochs[withdrawEpoch].requests[j].user &&
                    _amount[i] ==
                    withdrawEpochs[withdrawEpoch].requests[j].shares
                ) {
                    withdrawEpochs[withdrawEpoch].requests[j] = withdrawEpochs[
                        withdrawEpoch
                    ].requests[
                            withdrawEpochs[withdrawEpoch].requests.length - 1
                        ];
                    withdrawEpochs[withdrawEpoch].requests.pop();
                }
            }
        }
    }

    function mixChainIds(uint256[] calldata values) external onlyAuthorized {
        for (uint256 i = 0; i < values.length; i++) {
            _supportedChainIds.remove(values[i]);
            _supportedChainIds.add(values[i]);
        }
    }

    function mixStrategiesByChainIds(
        uint16 chainId,
        address[] calldata addresses
    ) external onlyAuthorized {
        for (uint256 i = 0; i < addresses.length; i++) {
            _strategiesByChainId[chainId].remove(addresses[i]);
            _strategiesByChainId[chainId].add(addresses[i]);
        }
    }

    function getChainIdsSet() external view returns (uint256[] memory) {
        return _supportedChainIds.values();
    }

    function getStrategiesSetByChainId(
        uint16 chainId
    ) external view returns (address[] memory) {
        return _strategiesByChainId[chainId].values();
    }

    receive() external payable {}
}

