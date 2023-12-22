// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";
import "./IFeeLP.sol";
import "./IWETH.sol";
import "./IVault.sol";
import "./IUniswapV2Router01.sol";
import "./IRouter.sol";
import "./IReferral.sol";

contract Router is IRouter, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    struct IncreasePositionRequest {
        address account;
        address inToken;
        address indexToken;
        uint256 collateralDelta;
        uint256 amountIn;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 insuranceLevel;
        uint256 executionFee;
        uint256 feeLPAmount;
        uint256 blockTime;
    }
    struct DecreasePositionRequest {
        address account;
        address inToken;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 insuranceLevel;
        uint256 minOut;
        uint256 executionFee;
        uint256 feeLPAmount;
        uint256 blockTime;
    }

    address public gov;
    bool public isInitialized = false;
    // wrapped BNB / ETH
    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public LP;
    address public FeeLP;
    address public vault;

    uint256 public minExecutionFee;

    uint256 public minTimeDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;

    bytes32[] public increasePositionRequestKeys;
    bytes32[] public decreasePositionRequestKeys;

    uint256 public override increasePositionRequestKeysStart;
    uint256 public override decreasePositionRequestKeysStart;

    mapping(address => bool) public isPositionKeeper;

    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping(address => uint256) public decreasePositionsIndex;
    mapping(bytes32 => DecreasePositionRequest) public decreasePositionRequests;

    address public referral;

    uint256[50] private _gap;
    // Event
    event Swap(
        address account,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event CreateIncreasePosition(
        address indexed account,
        address inToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 insuranceLevel,
        uint256 executionFee,
        uint256 index,
        uint256 feeLPAmount,
        uint256 blockTime
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address inToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 insuranceLevel,
        uint256 executionFee,
        uint256 timeGap
    );

    event CancelIncreasePosition(
        address indexed account,
        address inToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 insuranceLevel,
        uint256 executionFee,
        uint256 timeGap,
        uint256 feeLPAmount
    );

    event CreateDecreasePosition(
        address indexed account,
        address inToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 insuranceLevel,
        uint256 minOut,
        uint256 executionFee,
        uint256 index,
        uint256 feeLPAmount,
        uint256 blockTime
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address inToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 insuranceLevel,
        uint256 minOut,
        uint256 executionFee,
        uint256 timeGap
    );

    event CancelDecreasePosition(
        address indexed account,
        address inToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 insuranceLevel,
        uint256 minOut,
        uint256 executionFee,
        uint256 timeGap,
        uint256 feeLPAmount
    );

    event SetPositionKeeper(address indexed account, bool isActive);
    event SetMinExecutionFee(uint256 minExecutionFee);
    event SetDelayValues(
        uint256 minTimeDelayKeeper,
        uint256 minTimeDelayPublic,
        uint256 maxTimeDelay
    );
    event SetRequestKeysStartValues(
        uint256 increasePositionRequestKeysStart,
        uint256 decreasePositionRequestKeysStart
    );

    modifier onlyGov() {
        require(msg.sender == gov, "Router: forbidden");
        _;
    }
    modifier onlyPositionKeeper() {
        require(isPositionKeeper[msg.sender], "403");
        _;
    }
    event Initialize(
        address _vault,
        address _LP,
        address _weth,
        uint256 _minExecutionFee
    );

    function initialize(
        address _vault,
        address _LP,
        address _weth,
        address _FeeLP,
        address _referral,
        uint256 _minExecutionFee,
        uint256 _minTimeDelayKeeper,
        uint256 _minTimeDelayPublic,
        uint256 _maxTimeDelay
    ) external {
        require(!isInitialized, "Router: already initialized");
        isInitialized = true;
        gov = msg.sender;

        vault = _vault;
        LP = _LP;
        weth = _weth;
        FeeLP = _FeeLP;
        referral= _referral;
        minExecutionFee = _minExecutionFee;

        minTimeDelayKeeper = _minTimeDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;

        IERC20(LP).safeApprove(vault, type(uint256).max);

        emit Initialize(_vault, _LP, _weth, _minExecutionFee);
    }

    receive() external payable {
        require(msg.sender == weth, "Router: receive invalid sender");
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setPositionKeeper(address _addr, bool active) external onlyGov {
        isPositionKeeper[_addr] = active;
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyGov {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    function setRequestKeysStartValues(
        uint256 _increasePositionRequestKeysStart,
        uint256 _decreasePositionRequestKeysStart
    ) external onlyGov {
        increasePositionRequestKeysStart = _increasePositionRequestKeysStart;
        decreasePositionRequestKeysStart = _decreasePositionRequestKeysStart;

        emit SetRequestKeysStartValues(
            _increasePositionRequestKeysStart,
            _decreasePositionRequestKeysStart
        );
    }

    function createIncreasePosition(
        address _inToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _insuranceLevel,
        uint256 _executionFee,
        bytes32 _referralCode
    ) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value == _executionFee, "val");

        _transferInETH();
        _setTraderReferralCode(_referralCode);

        IncreasePositionRequest memory p = IncreasePositionRequest(
            msg.sender,
            _inToken,
            _indexToken,
            _collateralDelta,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _insuranceLevel,
            _executionFee,
            0,
            block.timestamp
        );

        {
            //transfer in here first
            //if _sizeDelta is 0,no fee,no insurance
            if (p.sizeDelta > 0) {
                require(
                    p.sizeDelta <=
                        _collateralDelta.mul(IVault(vault).maxLeverage()).div(
                            2*IVault(vault).BASIS_POINTS_DIVISOR()
                        ),
                    "Router: leverage invalid"
                );
                //add insurance
                p.amountIn = p.amountIn.add(
                    p
                        .amountIn
                        .mul(IVault(vault).insuranceLevel(_insuranceLevel))
                        .div(IVault(vault).BASIS_POINTS_DIVISOR())
                );
                //add fee
                {
                    uint256 fee = IVault(vault).getPositionFee(_sizeDelta);
                    if (IFeeLP(FeeLP).balanceOf(msg.sender) >= fee) {
                        IFeeLP(FeeLP).lock(
                            msg.sender,
                            address(this),
                            fee,
                            true
                        );
                        p.feeLPAmount = fee;
                    } else {
                        p.amountIn = p.amountIn.add(fee);
                    }
                }
            }
            IERC20(_inToken).safeTransferFrom(
                msg.sender,
                address(this),
                p.amountIn
            );
        }

        return _createIncreasePosition(p);
    }

    function createDecreasePosition(
        address _inToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _insuranceLevel,
        uint256 _minOut,
        uint256 _executionFee
    ) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(
            msg.value == _executionFee,
            "Router: insufficient execution fee"
        );

        uint256 feeLPAmount;
        if (_sizeDelta > 0) {
            require(
                _collateralDelta > 0,
                "Router: sizeDelta not zero, collateralDelta zero"
            );
            uint256 fee = IVault(vault).getPositionFee(_sizeDelta);
            if (IFeeLP(FeeLP).balanceOf(msg.sender) >= fee) {
                IFeeLP(FeeLP).lock(msg.sender, address(this), fee, false);
                feeLPAmount = fee;
            }
        }
        _transferInETH();
        return
            _createDecreasePosition(
                msg.sender,
                _inToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                _acceptablePrice,
                _insuranceLevel,
                _minOut,
                _executionFee,
                feeLPAmount
            );
    }

    function _createDecreasePosition(
        address _account,
        address _inToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _insuranceLevel,
        uint256 _minOut,
        uint256 _executionFee,
        uint256 _feeLPAmount
    ) internal returns (bytes32) {
        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _inToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _insuranceLevel,
            _minOut,
            _executionFee,
            _feeLPAmount,
            block.timestamp
        );
        {
            (uint256 index, bytes32 requestKey) = _storeDecreasePositionRequest(
                request
            );
            emit CreateDecreasePosition(
                request.account,
                request.inToken,
                request.indexToken,
                request.collateralDelta,
                request.sizeDelta,
                request.isLong,
                request.acceptablePrice,
                request.insuranceLevel,
                request.minOut,
                request.executionFee,
                index,
                request.feeLPAmount,
                block.timestamp
            );
            return requestKey;
        }
    }

    function _createIncreasePosition(
        IncreasePositionRequest memory p
    ) internal returns (bytes32 requestKey) {
        {
            uint256 index;
            (index, requestKey) = _storeIncreasePositionRequest(p);

            emit CreateIncreasePosition(
                p.account,
                p.inToken,
                p.indexToken,
                p.collateralDelta,
                p.sizeDelta,
                p.isLong,
                p.acceptablePrice,
                p.insuranceLevel,
                p.executionFee,
                index,
                p.feeLPAmount,
                block.timestamp
            );
        }
    }

    function _storeIncreasePositionRequest(
        IncreasePositionRequest memory _request
    ) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = increasePositionsIndex[account].add(1);
        increasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    function _storeDecreasePositionRequest(
        DecreasePositionRequest memory _request
    ) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = decreasePositionsIndex[account].add(1);
        decreasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        decreasePositionRequests[key] = _request;
        decreasePositionRequestKeys.push(key);

        return (index, key);
    }

    function executeIncreasePositions(
        uint256 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionKeeper {
        uint256 index = increasePositionRequestKeysStart;
        uint256 length = increasePositionRequestKeys.length;

        if (index >= length) {
            return;
        }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = increasePositionRequestKeys[index];
            // bool suc = this.executeIncreasePosition(key, _executionFeeReceiver);
            // require(suc, "executeIncreasePosition");
            try
                this.executeIncreasePosition(key, _executionFeeReceiver)
            returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                try
                    this.cancelIncreasePosition(key, _executionFeeReceiver)
                returns (bool _wasCancelled) {
                    if (!_wasCancelled) {
                        break;
                    }
                } catch {}
            }

            delete increasePositionRequestKeys[index];
            index++;
        }

        increasePositionRequestKeysStart = index;
    }

    function executeDecreasePositions(
        uint256 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionKeeper {
        uint256 index = decreasePositionRequestKeysStart;
        uint256 length = decreasePositionRequestKeys.length;

        if (index >= length) {
            return;
        }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = decreasePositionRequestKeys[index];
            // bool suc = this.executeDecreasePosition(key, _executionFeeReceiver);
            // require(suc, "executeDecreasePosition fail");
            try
                this.executeDecreasePosition(key, _executionFeeReceiver)
            returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                try
                    this.cancelDecreasePosition(key, _executionFeeReceiver)
                returns (bool _wasCancelled) {
                    if (!_wasCancelled) {
                        break;
                    }
                } catch {}
            }

            delete decreasePositionRequestKeys[index];
            index++;
        }

        decreasePositionRequestKeysStart = index;
    }

    function executeIncreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        if (request.account == address(0)) {
            return true;
        }

        bool shouldExecute = _validateExecution(
            request.blockTime,
            request.account
        );
        if (!shouldExecute) {
            return false;
        }

        if (
            request.sizeDelta > 0 &&
            request.feeLPAmount >=
            IVault(vault).getPositionFee(request.sizeDelta)
        ) {
            IFeeLP(FeeLP).burnLocked(
                request.account,
                address(this),
                request.feeLPAmount,
                true
            );
        }

        if (request.amountIn > 0) {
            IERC20(request.inToken).safeTransfer(vault, request.amountIn);
        }
        delete increasePositionRequests[_key];
        IVault(vault).increasePosition(
            request.account,
            request.indexToken,
            request.sizeDelta,
            request.collateralDelta,
            request.isLong,
            request.insuranceLevel,
            request.feeLPAmount
        );

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit ExecuteIncreasePosition(
            request.account,
            request.inToken,
            request.indexToken,
            request.collateralDelta,
            request.amountIn,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.insuranceLevel,
            request.executionFee,
            block.timestamp.sub(request.blockTime)
        );
        return true;
    }

    function executeDecreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        if (request.account == address(0)) {
            return true;
        }

        bool shouldExecute = _validateExecution(
            request.blockTime,
            request.account
        );
        if (!shouldExecute) {
            return false;
        }

        if (
            request.sizeDelta > 0 &&
            request.feeLPAmount >=
            IVault(vault).getPositionFee(request.sizeDelta)
        ) {
            IFeeLP(FeeLP).burnLocked(
                request.account,
                address(this),
                request.feeLPAmount,
                false
            );
        }

        delete decreasePositionRequests[_key];
        (, uint256 outLp) = IVault(vault).decreasePosition(
            request.account,
            request.indexToken,
            request.sizeDelta,
            request.collateralDelta,
            request.isLong,
            request.account, //request.receiver,
            request.insuranceLevel,
            request.feeLPAmount
        );
        require(outLp >= request.minOut, "Router: min out");

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit ExecuteDecreasePosition(
            request.account,
            request.inToken,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.insuranceLevel,
            request.minOut,
            request.executionFee,
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }

    function cancelIncreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        if (request.account == address(0)) {
            return true;
        }

        bool shouldCancel = _validateCancellation(
            request.blockTime,
            request.account
        );
        if (!shouldCancel) {
            return false;
        }

        delete increasePositionRequests[_key];

        if (request.feeLPAmount > 0) {
            //request.sizeDelta > 0 &&
            IFeeLP(FeeLP).unlock(
                request.account,
                address(this),
                request.feeLPAmount,
                true
            );
        }
        IERC20(request.inToken).safeTransfer(request.account, request.amountIn);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit CancelIncreasePosition(
            request.account,
            request.inToken,
            request.indexToken,
            request.collateralDelta,
            request.amountIn,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.insuranceLevel,
            request.executionFee,
            block.timestamp.sub(request.blockTime),
            request.feeLPAmount
        );

        return true;
    }

    function cancelDecreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        if (request.account == address(0)) {
            return true;
        }

        bool shouldCancel = _validateCancellation(
            request.blockTime,
            request.account
        );
        if (!shouldCancel) {
            return false;
        }
        if (request.feeLPAmount > 0) {
            //request.sizeDelta > 0 &&
            IFeeLP(FeeLP).unlock(
                request.account,
                address(this),
                request.feeLPAmount,
                false
            );
        }
        delete decreasePositionRequests[_key];

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit CancelDecreasePosition(
            request.account,
            request.inToken,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.insuranceLevel,
            request.minOut,
            request.executionFee,
            block.timestamp.sub(request.blockTime),
            request.feeLPAmount
        );

        return true;
    }

    function _setTraderReferralCode(bytes32 _referralCode) private {
        if (_referralCode != bytes32(0) && referral != address(0)) {
            IReferral(referral).setTraderReferralCode(
                msg.sender,
                _referralCode
            );
        }
    }

    function _sender() private view returns (address) {
        return msg.sender;
    }

    function _transferInETH() private {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(
        uint256 _amountOut,
        address payable _receiver
    ) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _transferOutETHWithGasLimitIgnoreFail(
        uint256 _amountOut,
        address payable _receiver
    ) internal {
        IWETH(weth).withdraw(_amountOut);
        _receiver.send(_amountOut);
    }

    function setTokenVault(
        address _weth,
        address _LP,
        address _vault
    ) external onlyGov {
        weth = _weth;
        LP = _LP;
        vault = _vault;

        IERC20(LP).approve(vault, type(uint256).max);
    }

    function setDelayValues(
        uint256 _minTimeDelayKeeper,
        uint256 _minTimeDelayPublic,
        uint256 _maxTimeDelay
    ) external onlyGov {
        minTimeDelayKeeper = _minTimeDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(
            _minTimeDelayKeeper,
            _minTimeDelayPublic,
            _maxTimeDelay
        );
    }

    function setReferral(address _referral) external onlyGov {
        referral = _referral;
    }

    function _validateExecution(
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        require(
            _positionBlockTime.add(maxTimeDelay) >= block.timestamp,
            "Router: expired"
        );

        bool isKeeperCall = msg.sender == address(this) ||
            isPositionKeeper[msg.sender];

        if (isKeeperCall) {
            return
                _positionBlockTime.add(minTimeDelayKeeper) <= block.timestamp;
        } else {
            require(
                msg.sender == _account,
                "Router: _validateExecution invalid"
            );
        }

        require(
            _positionBlockTime.add(minTimeDelayPublic) <= block.timestamp,
            "Router: delay"
        );

        return true;
    }

    function _validateCancellation(
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        bool isKeeperCall = msg.sender == address(this) ||
            isPositionKeeper[msg.sender];

        if (isKeeperCall) {
            return
                _positionBlockTime.add(minTimeDelayKeeper) <= block.timestamp;
        }

        require(
            msg.sender == _account,
            "Router: _validateCancellation invalid"
        );

        require(
            _positionBlockTime.add(minTimeDelayPublic) <= block.timestamp,
            "delay"
        );

        return true;
    }

    function getRequestQueueLengths()
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return (
            increasePositionRequestKeysStart,
            increasePositionRequestKeys.length,
            decreasePositionRequestKeysStart,
            decreasePositionRequestKeys.length
        );
    }

    function getRequestKey(
        address _account,
        uint256 _index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index));
    }
}

