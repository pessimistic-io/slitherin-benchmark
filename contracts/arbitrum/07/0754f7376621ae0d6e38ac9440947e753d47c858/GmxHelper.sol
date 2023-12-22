// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {IVault as IGmxVault} from "./IVault.sol";
import {IPositionRouter} from "./IPositionRouter.sol";
import {IGeniBot} from "./IGeniBot.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

struct GmxConfig {
    address vault;
    address glp;
    address fsGlp;
    address glpManager;
    address positionRouter;
    address usdg;
}

contract GmxHelper is Ownable, ReentrancyGuard {
    // GMX contracts
    address public gmxVault;
    address public gmxPositionRouter;

    uint256 public constant BASE_LEVERAGE = 10000; // 1x

    mapping(address => bool) public isKeeper;
    // Modifier for execution roles
    modifier onlyKeeper() {
        require(isKeeper[msg.sender], "GmxHelper: Is not keeper");
        _;
    }

    struct Increase {
        address _trader;
        address _account;
        address[] _path;
        address _indexToken;
        uint256 _amountIn;
        bool _isLong;
        uint256 _acceptablePrice;
        address _traderTokenIn;
        uint256 _traderAmountIn;
        uint256 _traderSizeDelta;
    }
    struct Decrease {
        address _trader;
        address _account;
        address[] _path;
        address _indexToken;
        bool _isLong;
        uint256 _acceptablePrice;
        address _traderCollateralToken;
        uint256 _traderCollateralDelta;
        uint256 _traderSizeDelta;
    }
    struct Close {
        address _trader;
        address _account;
        address[] _path;
        address _indexToken;
        bool _isLong;
        uint256 _sizeDelta;
        uint256 _collateralDelta;
        uint256 _acceptablePrice;
    }

    struct UpdateBalance {
        address _bot;
        uint256 _collateralDelta;
        uint256 _sizeDelta;
        address _indexToken;
        bool _isLong;
    }

    event UpdateBalanceFail(address bot, uint256 collateralDelta, uint256 sizeDelta, address indexToken, bool isLong);
    event SendIncreaseOrderFail(
        address trader,
        address account,
        address indexToken,
        uint256 amountIn,
        bool isLong,
        uint256 acceptablePrice
    );
    event SendDecreaseOrderFail(
        address trader,
        address account,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice
    );

    constructor(address _gmxVault, address _gmxPositionRouter) {
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;
    }

    function setKeeper(address _account, bool _status) external onlyOwner {
        isKeeper[_account] = _status;
    }

    // Handle multiple update balance for user when close position
    function bulkUpdateBalance(UpdateBalance[] memory updateBalances)
        external
        payable
        nonReentrant
        onlyKeeper
        returns (bool)
    {
        for (uint256 index = 0; index < updateBalances.length; index++) {
            try IGeniBot(updateBalances[index]._bot).updateBalanceToVault() {} catch {
                emit UpdateBalanceFail(
                    updateBalances[index]._bot,
                    updateBalances[index]._collateralDelta,
                    updateBalances[index]._sizeDelta,
                    updateBalances[index]._indexToken,
                    updateBalances[index]._isLong
                );
            }
        }
        return true;
    }

    function bulkOrders(Increase[] memory increases, Decrease[] memory decreases)
        external
        payable
        nonReentrant
        onlyKeeper
        returns (bool)
    {
        uint256 minExecutionFee = IPositionRouter(gmxPositionRouter).minExecutionFee();
        require(
            msg.value >= (increases.length + decreases.length) * minExecutionFee,
            "GmxHelper: insufficient execution fee."
        );

        for (uint256 index = 0; index < increases.length; index++) {
            Increase memory increase = increases[index];
            uint256 newSizeDelta = this.getIncreaseData(
                increase._account,
                increase._traderTokenIn,
                increase._traderAmountIn,
                increase._traderSizeDelta,
                increase._isLong,
                increase._amountIn
            );
            try
                IGeniBot(increase._account).createIncreasePosition{value: minExecutionFee}(
                    increase._trader,
                    increase._path,
                    increase._indexToken,
                    increase._amountIn,
                    0,
                    newSizeDelta,
                    increase._isLong,
                    increase._acceptablePrice,
                    minExecutionFee
                )
            {} catch {
                emit SendIncreaseOrderFail(
                    increase._trader,
                    increase._account,
                    increase._indexToken,
                    increase._amountIn,
                    increase._isLong,
                    increase._acceptablePrice
                );
            }
        }
        //
        for (uint256 index = 0; index < decreases.length; index++) {
            Decrease memory decrease = decreases[index];
            (uint256 newSizeDelta, uint256 newCollateralDetal, ) = this.getDecreaseData(
                decrease._trader,
                decrease._traderCollateralToken,
                decrease._traderCollateralDelta,
                decrease._traderSizeDelta,
                decrease._isLong,
                decrease._account,
                decrease._path[0],
                decrease._indexToken
            );
            try
                IGeniBot(decrease._account).createDecreasePosition{value: minExecutionFee}(
                    decrease._trader,
                    decrease._path,
                    decrease._indexToken,
                    newCollateralDetal,
                    newSizeDelta,
                    decrease._isLong,
                    decrease._acceptablePrice,
                    0,
                    minExecutionFee,
                    address(0)
                )
            {} catch {
                emit SendDecreaseOrderFail(
                    decrease._trader,
                    decrease._account,
                    decrease._indexToken,
                    newCollateralDetal,
                    newSizeDelta,
                    decrease._isLong,
                    decrease._acceptablePrice
                );
            }
        }
        return true;
    }

    function bulkTakeProfiStoploss(Close[] memory closes) external payable nonReentrant onlyKeeper returns (bool) {
        uint256 minExecutionFee = IPositionRouter(gmxPositionRouter).minExecutionFee();
        require(msg.value >= (closes.length) * minExecutionFee, "GmxHelper: insufficient execution fee.");

        for (uint256 index = 0; index < closes.length; index++) {
            Close memory closes = closes[index];

            try
                IGeniBot(closes._account).createDecreasePosition{value: minExecutionFee}(
                    closes._trader,
                    closes._path,
                    closes._indexToken,
                    closes._collateralDelta,
                    closes._sizeDelta,
                    closes._isLong,
                    closes._acceptablePrice,
                    0,
                    minExecutionFee,
                    address(0)
                )
            {} catch {
                emit SendDecreaseOrderFail(
                    closes._trader,
                    closes._account,
                    closes._indexToken,
                    closes._collateralDelta,
                    closes._sizeDelta,
                    closes._isLong,
                    closes._acceptablePrice
                );
            }
        }
        return true;
    }

    function getPrice(address _token, bool _maximise) public view returns (uint256) {
        return _maximise ? IGmxVault(gmxVault).getMaxPrice(_token) : IGmxVault(gmxVault).getMinPrice(_token);
    }

    function getLeverage(
        address tokenIn,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong
    ) public view returns (uint256) {
        IGmxVault _gmxVault = IGmxVault(gmxVault);
        uint256 decimals = _gmxVault.tokenDecimals(tokenIn);

        uint256 price = getPrice(tokenIn, isLong);
        uint256 amountInUsd = (price * amountIn) / (10**decimals);
        uint256 leverage = ((sizeDelta * BASE_LEVERAGE) / amountInUsd);
        return leverage;
    }

    function getIncreaseData(
        address bot,
        address tokenIn,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 fixedMargin
    ) public view returns (uint256) {
        address tokenPlay = IGeniBot(bot).getTokenPlay();
        IGmxVault _gmxVault = IGmxVault(gmxVault);

        uint256 tokenPlayPrice = getPriceBySide(tokenPlay, isLong, true);

        uint256 leverage = this.getLeverage(tokenIn, amountIn, sizeDelta, isLong);

        return (((fixedMargin * tokenPlayPrice * leverage) / BASE_LEVERAGE) / (10**_gmxVault.tokenDecimals(tokenPlay))); // sizeDelta
    }

    function getDecreaseData(
        address pAccount,
        address pCollateralToken,
        uint256 pCollateralDelta,
        uint256 pSizeDelta,
        bool isLong,
        address account,
        address collateralToken,
        address indexToken
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 pSize, uint256 pCollateral, , , , , , ) = IGmxVault(gmxVault).getPosition(
            pAccount,
            pCollateralToken,
            indexToken,
            isLong
        );
        pSize = pSizeDelta + pSize;
        pCollateral = pCollateralDelta + pCollateral;
        (uint256 size, uint256 collateral, , , , , , ) = IGmxVault(gmxVault).getPosition(
            account,
            collateralToken,
            indexToken,
            isLong
        );
        if (pSize == 0 || pCollateral == 0) {
            // Close
            return (size, 0, BASE_LEVERAGE);
        }

        uint256 ratio = pSizeDelta == 0
            ? (pCollateralDelta * BASE_LEVERAGE) / pCollateral
            : (pSizeDelta * BASE_LEVERAGE) / pSize;

        if (pSize == pSizeDelta || ratio > (100 * BASE_LEVERAGE)) {
            // Close
            return (
                size, // 0
                0, // 1
                ratio
            );
        }

        return (
            (ratio * size) / BASE_LEVERAGE, // 0
            (ratio * collateral) / BASE_LEVERAGE, // 1
            ratio
        );
    }

    function getPriceBySide(
        address token,
        bool isLong,
        bool isIncrease
    ) public view returns (uint256 price) {
        if (isIncrease) {
            return isLong ? getPrice(token, true) : getPrice(token, false);
        } else {
            return isLong ? getPrice(token, false) : getPrice(token, true);
        }
    }

    function _validatePositionLimit(
        address _bot,
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _pendingSize,
        bool _isLong,
        uint256 positionLimit
    ) private view {
        (uint256 size, , , , , , , ) = IGmxVault(gmxVault).getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        require(size + _pendingSize <= positionLimit, "Position limit size");
    }
}

