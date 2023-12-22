// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

enum OrderType {
    MARKET,
    LIMIT,
    STOP,
    STOP_LIMIT,
    TRAILING_STOP
}

enum OrderStatus {
    NONE,
    PENDING,
    FILLED,
    CANCELED
}

enum PositionStatus {
    NONE,
    PENDING,
    FILLED,
    CANCELED
}

enum TriggerStatus {
    OPEN,
    TRIGGERED,
    CANCELLED
}

struct ConfirmInfo {
    bool confirmDelayStatus;
    uint256 pendingDelayCollateral;
    uint256 pendingDelaySize;
    uint256 delayStartTime;
}

struct OrderInfo {
    OrderStatus status;
    uint256 lmtPrice;
    uint256 pendingSize;
    uint256 pendingCollateral;
    uint256 positionType;
    uint256 stepAmount;
    uint256 stepType;
    uint256 stpPrice;
}

struct Position {
    address owner;
    address refer;
    int256 realisedPnl;
    uint256 averagePrice;
    uint256 collateral;
    uint256 entryFundingRate;
    uint256 lastIncreasedTime;
    uint256 lastPrice;
    uint256 reserveAmount;
    uint256 size;
}

struct TriggerOrder {
    bytes32 key;
    uint256[] slPrices;
    uint256[] slAmountPercents;
    uint256[] slTriggeredAmounts;
    uint256[] tpPrices;
    uint256[] tpAmountPercents;
    uint256[] tpTriggeredAmounts;
    TriggerStatus status;
}


contract Constants {
    address public constant ZERO_ADDRESS = address(0);
    uint8 public constant ORDER_FILLED = 1;
    uint8 public constant ORDER_NOT_FILLED = 0;
    uint8 public constant STAKING_PID_FOR_CHARGE_FEE = 1;
    uint256 public constant BASIS_POINTS_DIVISOR = 100000;
    uint256 public constant DEFAULT_FUNDING_RATE_FACTOR = 100;
    uint256 public constant DEFAULT_MAX_OPEN_INTEREST = 10000000000 * PRICE_PRECISION;
    uint256 public constant DEFAULT_ALP_PRICE = 100000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;
    uint256 public constant LIQUIDATE_NONE_EXCEED = 0;
    uint256 public constant LIQUIDATE_FEE_EXCEED = 1;
    uint256 public constant LIQUIDATE_THRESHOLD_EXCEED = 2;
    uint256 public constant MAX_DEPOSIT_FEE = 10000; // 10%
    uint256 public constant MAX_DELTA_TIME = 24 hours;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    uint256 public constant MAX_FEE_BASIS_POINTS = 5000; // 5%
    uint256 public constant MAX_FEE_REWARD_BASIS_POINTS = BASIS_POINTS_DIVISOR; // 100%
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 10000; // 1%
    uint256 public constant MAX_FUNDING_RATE_INTERVAL = 48 hours;
    uint256 public constant MAX_LIQUIDATION_FEE_USD = 100 * PRICE_PRECISION; // 100 USD
    uint256 public constant MAX_STAKING_FEE = 10000; // 10%
    uint256 public constant MAX_TOKENFARM_COOLDOWN_DURATION = 4 weeks;
    uint256 public constant MAX_TRIGGER_GAS_FEE = 1e8 gwei;
    uint256 public constant MAX_VESTING_DURATION = 700 days;
    uint256 public constant MIN_FUNDING_RATE_INTERVAL = 1 hours;
    uint256 public constant MIN_LEVERAGE = 10000; // 1x
    uint256 public constant MIN_FEE_REWARD_BASIS_POINTS = 50000; // 50%
    uint256 public constant POSITION_MARKET = 0;
    uint256 public constant POSITION_LIMIT = 1;
    uint256 public constant POSITION_STOP_MARKET = 2;
    uint256 public constant POSITION_STOP_LIMIT = 3;
    uint256 public constant POSITION_TRAILING_STOP = 4;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant TRAILING_STOP_TYPE_AMOUNT = 0;
    uint256 public constant TRAILING_STOP_TYPE_PERCENT = 1;
    uint256 public constant ALP_DECIMALS = 18;

    function _getPositionKey(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken, _isLong, _posId));
    }

    function checkSlippage(
        bool isLong,
        uint256 expectedMarketPrice,
        uint256 slippageBasisPoints,
        uint256 actualMarketPrice
    ) internal pure {
        if (isLong) {
            require(
                actualMarketPrice <=
                    (expectedMarketPrice * (BASIS_POINTS_DIVISOR + slippageBasisPoints)) / BASIS_POINTS_DIVISOR,
                "slippage exceeded"
            );
        } else {
            require(
                (expectedMarketPrice * (BASIS_POINTS_DIVISOR - slippageBasisPoints)) / BASIS_POINTS_DIVISOR <=
                    actualMarketPrice,
                "slippage exceeded"
            );
        }
    }
}


/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


interface ITriggerOrderManager {
    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external returns (bool, uint256);

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external view returns (bool);
}


interface ISettingsManager {
    function decreaseOpenInterest(address _token, address _sender, bool _isLong, uint256 _amount) external;

    function increaseOpenInterest(address _token, address _sender, bool _isLong, uint256 _amount) external;

    function updateCumulativeFundingRate(address _token, bool _isLong) external;

    function openInterestPerAsset(address _token) external view returns (uint256);

    function openInterestPerSide(bool _isLong) external view returns (uint256);

    function openInterestPerUser(address _sender) external view returns (uint256);

    function bountyPercent() external view returns (uint256);

    function checkDelegation(address _master, address _delegate) external view returns (bool);

    function closeDeltaTime() external view returns (uint256);

    function collectMarginFees(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view returns (uint256);

    function cooldownDuration() external view returns (uint256);

    function cumulativeFundingRates(address _token, bool _isLong) external view returns (uint256);

    function delayDeltaTime() external view returns (uint256);

    function depositFee() external view returns (uint256);

    function feeManager() external view returns (address);

    function feeRewardBasisPoints() external view returns (uint256);

    function fundingInterval() external view returns (uint256);

    function fundingRateFactor(address _token, bool _isLong) external view returns (uint256);

    function getFundingFee(
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view returns (uint256);

    function getPositionFee(address _indexToken, bool _isLong, uint256 _sizeDelta) external view returns (uint256);

    function getDelegates(address _master) external view returns (address[] memory);

    function isDeposit(address _token) external view returns (bool);

    function isManager(address _account) external view returns (bool);

    function isStaking(address _token) external view returns (bool);

    function lastFundingTimes(address _token, bool _isLong) external view returns (uint256);

    function liquidationFeeUsd() external view returns (uint256);

    function liquidateThreshold(address) external view returns (uint256);

    function marginFeeBasisPoints(address _token, bool _isLong) external view returns (uint256);

    function marketOrderEnabled() external view returns (bool);
    function pauseForexForCloseTime() external view returns (bool);

    function positionManager() external view returns (address);

    function priceMovementPercent() external view returns (uint256);

    function referFee() external view returns (uint256);

    function referEnabled() external view returns (bool);

    function stakingFee() external view returns (uint256);

    function triggerGasFee() external view returns (uint256);

    function validatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _collateral
    ) external view;
}


interface IPositionVault {
    function addOrRemoveCollateral(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool isPlus,
        uint256 _amount
    ) external;

    function addPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external;

    function addTrailingStop(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params
    ) external;

    function cancelPendingOrder(address _account, address _indexToken, bool _isLong, uint256 _posId) external;

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _posId
    ) external;

    function newPositionOrder(
        address _account,
        address _indexToken,
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address _refer
    ) external;

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (Position memory, OrderInfo memory, ConfirmInfo memory);

    function poolAmounts(address _token, bool _isLong) external view returns (uint256);

    function reservedAmounts(address _token, bool _isLong) external view returns (uint256);
}


interface IPriceManager {
    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong
    ) external view returns (bool, uint256);

    function getLastPrice(address _token) external view returns (uint256);

    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _sizeDelta
    ) external view returns (uint256);
    function isForex(address _token) external view returns (bool);
    function maxLeverage(address _token) external view returns (uint256);

    function usdToToken(address _token, uint256 _usdAmount) external view returns (uint256);

    function tokenDecimals(address _token) external view returns (uint256);

    function tokenToUsd(address _token, uint256 _tokenAmount) external view returns (uint256);
}


/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


contract TriggerOrderManager is ITriggerOrderManager, ReentrancyGuard, Constants {
    IPositionVault public immutable positionVault;
    ISettingsManager public immutable settingsManager;
    IPriceManager public priceManager;

    mapping(bytes32 => TriggerOrder) public triggerOrders;

    event ExecuteTriggerOrders(
        bytes32 key,
        uint256[] tpPrices,
        uint256[] slPrices,
        uint256[] tpAmountPercents,
        uint256[] slAmountPercents,
        uint256[] tpTriggeredAmounts,
        uint256[] slTriggeredAmounts,
        TriggerStatus status
    );
    event UpdateTriggerOrders(
        bytes32 key,
        uint256[] tpPrices,
        uint256[] slPrices,
        uint256[] tpAmountPercents,
        uint256[] slAmountPercents,
        uint256[] tpTriggeredAmounts,
        uint256[] slTriggeredAmounts,
        TriggerStatus status
    );
    event UpdateTriggerStatus(bytes32 key, TriggerStatus status);

    modifier onlyVault() {
        require(msg.sender == address(positionVault), "Only vault has access");
        _;
    }

    constructor(address _positionVault, address _priceManager, address _settingsManager) {
        require(Address.isContract(_positionVault), "positionVault address is invalid");
        require(Address.isContract(_priceManager), "priceManager address is invalid");
        require(Address.isContract(_settingsManager), "settingsManager address is invalid");
        positionVault = IPositionVault(_positionVault);
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManager(_settingsManager);
    }

    function cancelTriggerOrders(address _token, bool _isLong, uint256 _posId) external {
        bytes32 key = _getPositionKey(msg.sender, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        require(order.status == TriggerStatus.OPEN, "TriggerOrder was cancelled");
        order.status = TriggerStatus.CANCELLED;
        emit UpdateTriggerStatus(key, order.status);
    }

    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external override onlyVault returns (bool, uint256) {
        bytes32 key = _getPositionKey(_account, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        (Position memory position, , ) = positionVault.getPosition(_account, _token, _isLong, _posId);
        require(order.status == TriggerStatus.OPEN, "TriggerOrder not Open");
        uint256 price = priceManager.getLastPrice(_token);
        for (bool tp = true; ; tp = false) {
            uint256[] storage prices = tp ? order.tpPrices : order.slPrices;
            uint256[] storage triggeredAmounts = tp ? order.tpTriggeredAmounts : order.slTriggeredAmounts;
            uint256[] storage amountPercents = tp ? order.tpAmountPercents : order.slAmountPercents;
            uint256 closeAmountPercent;
            for (uint256 i = 0; i != prices.length && closeAmountPercent < BASIS_POINTS_DIVISOR; ++i) {
                bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
                if (triggeredAmounts[i] == 0 && (pricesAreUpperBounds ? prices[i] <= price : price <= prices[i])) {
                    closeAmountPercent += amountPercents[i];
                    triggeredAmounts[i] = (position.size * amountPercents[i]) / BASIS_POINTS_DIVISOR;
                }
            }
            if (closeAmountPercent != 0) {
                emit ExecuteTriggerOrders(
                    key,
                    order.tpPrices,
                    order.slPrices,
                    order.tpAmountPercents,
                    order.slAmountPercents,
                    order.tpTriggeredAmounts,
                    order.slTriggeredAmounts,
                    order.status
                );
                if (closeAmountPercent >= BASIS_POINTS_DIVISOR) {
                    order.status = TriggerStatus.TRIGGERED;
                    return (true, BASIS_POINTS_DIVISOR);
                }
                return (true, closeAmountPercent);
            }
            if (!tp) {
                break;
            }
        }
        return (false, 0);
    }

    function updateTriggerOrders(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpAmountPercents,
        uint256[] memory _slAmountPercents,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) external payable nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        (Position memory position, , ) = positionVault.getPosition(msg.sender, _indexToken, _isLong, _posId);
        require(position.size > 0, "position size should be greater than zero");
        payable(settingsManager.positionManager()).transfer(msg.value);
        bool validateTriggerData = validateTriggerOrdersData(
            _indexToken,
            _isLong,
            _tpPrices,
            _slPrices,
            _tpTriggeredAmounts,
            _slTriggeredAmounts
        );
        require(validateTriggerData, "triggerOrder data are incorrect");
        if (triggerOrders[key].tpPrices.length + triggerOrders[key].slPrices.length < _tpPrices.length + _slPrices.length) {
            require(msg.value == settingsManager.triggerGasFee(), "invalid triggerGasFee");
        }
        triggerOrders[key] = TriggerOrder({
            key: key,
            tpTriggeredAmounts: _tpTriggeredAmounts,
            slTriggeredAmounts: _slTriggeredAmounts,
            tpPrices: _tpPrices,
            tpAmountPercents: _tpAmountPercents,
            slPrices: _slPrices,
            slAmountPercents: _slAmountPercents,
            status: TriggerStatus.OPEN
        });
        emit UpdateTriggerOrders(
            key,
            _tpPrices,
            _slPrices,
            _tpAmountPercents,
            _slAmountPercents,
            _tpTriggeredAmounts,
            _slTriggeredAmounts,
            TriggerStatus.OPEN
        );
    }

    function getTriggerOrderInfo(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (TriggerOrder memory) {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        return triggerOrders[key];
    }

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId
    ) external view override returns (bool) {
        bytes32 key = _getPositionKey(_account, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        if (order.status != TriggerStatus.OPEN) {
            return false;
        }
        uint256 price = priceManager.getLastPrice(_token);
        for (bool tp = true; ; tp = false) {
            uint256[] storage prices = tp ? order.tpPrices : order.slPrices;
            uint256[] storage triggeredAmounts = tp ? order.tpTriggeredAmounts : order.slTriggeredAmounts;
            uint256[] storage amountPercents = tp ? order.tpAmountPercents : order.slAmountPercents;
            uint256 closeAmountPercent;
            for (uint256 i = 0; i != prices.length && closeAmountPercent < BASIS_POINTS_DIVISOR; ++i) {
                bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
                if (triggeredAmounts[i] == 0 && (pricesAreUpperBounds ? prices[i] <= price : price <= prices[i])) {
                    closeAmountPercent += amountPercents[i];
                }
            }
            if (closeAmountPercent != 0) {
                return true;
            }
            if (!tp) {
                break;
            }
        }
        return false;
    }

    function validateTriggerOrdersData(
        address _indexToken,
        bool _isLong,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) internal view returns (bool) {
        uint256 price = priceManager.getLastPrice(_indexToken);
        for (bool tp = true; ; tp = false) {
            uint256[] memory prices = tp ? _tpPrices : _slPrices;
            uint256[] memory triggeredAmounts = tp ? _tpTriggeredAmounts : _slTriggeredAmounts;
            bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
            for (uint256 i = 0; i < prices.length; ++i) {
                if (triggeredAmounts[i] == 0 && (price < prices[i]) != pricesAreUpperBounds) {
                    return false;
                }
            }
            if (!tp) {
                break;
            }
        }
        return true;
    }
}