// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./IERC20.sol";
import "./AccessControlEnumerable.sol";
import "./Context.sol";
import "./EnumerableSet.sol";
import "./Pausable.sol";
import "./IERC20BurnableMinter.sol";
import "./IStakePool.sol";
import "./IMarket.sol";
import "./Initializer.sol";
import "./DelegateGuard.sol";
import "./Math.sol";

contract Market is
    Context,
    AccessControlEnumerable,
    Pausable,
    DelegateGuard,
    Initializer,
    IMarket
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant ADD_STABLECOIN_ROLE =
        keccak256("ADD_STABLECOIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STARTUP_ROLE = keccak256("STARTUP_ROLE");

    // Chaos token address
    IERC20BurnableMinter public override Chaos;
    // prChaos token address
    IERC20BurnableMinter public override prChaos;
    // StakePool contract address
    IStakePool public override pool;

    // target funding ratio (target/10000)
    //
    // price supporting funding(PSF) = (t - p) * (c - f) / 2
    //
    // floor supporting funding(FSF) = f * t
    //
    //                              PSF
    // current funding ratio = -------------
    //                           PSF + FSF
    //
    uint32 public override target;
    // target adjusted funding ratio (targetAdjusted/10000),
    // if the current funding ratio reaches targetAjusted, f and p will be increased to bring the funding ratio back to target
    uint32 public override targetAdjusted;
    // minimum value of target
    uint32 public override minTarget;
    // maximum value of the targetAdjusted
    uint32 public override maxTargetAdjusted;
    // step value of each raise
    uint32 public override raiseStep;
    // step value of each lower
    uint32 public override lowerStep;
    // interval of each lower
    uint32 public override lowerInterval;
    // the time when ratio was last modified
    uint256 public override latestUpdateTimestamp;

    // developer address
    address public override dev;
    // vault address
    address public override vault;
    // dev fee for buying Chaos
    uint32 public override buyFee;
    // vault fee for selling Chaos
    uint32 public override sellFee;
    // burn fee for selling Chaos
    uint32 public override burnFee;

    // the slope of the price function (1/(k * 1e18))
    uint256 public override k;
    // current Chaos price
    uint256 public override c;
    // floor Chaos price
    uint256 public override f;
    // floor supply,
    // if t <= p, the price of Chaos will always be f
    uint256 public override p;
    // total worth
    uint256 public override w;
    //
    //     ^
    //   c |_____________/
    //     |            /|
    //     |           / |
    //   f |__________/  |
    //     |          |  |
    //     |          |  |
    //      ------------------>
    //                p  t

    // stablecoins that can be used to buy Chaos
    EnumerableSet.AddressSet internal stablecoinsCanBuy;
    // stablecoins that can be exchanged with Chaos
    EnumerableSet.AddressSet internal stablecoinsCanSell;
    // stablecoins decimals
    mapping(address => uint8) public override stablecoinsDecimals;

    event Buy(
        address indexed from,
        address indexed token,
        uint256 input,
        uint256 output,
        uint256 fee
    );

    event Realize(
        address indexed from,
        address indexed token,
        uint256 input,
        uint256 output
    );

    event Sell(
        address indexed from,
        address indexed token,
        uint256 input,
        uint256 output,
        uint256 fee
    );

    event Burn(address indexed user, uint256 amount);

    event Raise(address trigger, uint256 target, uint256 targetAdjusted);

    event Lower(uint256 target, uint256 targetAdjusted);

    event Adjust(uint256 c, uint256 f, uint256 p);

    event AdjustOptionsChanged(
        uint32 minTarget,
        uint32 maxTargetAdjusted,
        uint32 raiseStep,
        uint32 lowerStep,
        uint32 lowerInterval
    );

    event FeeOptionsChanged(
        address dev,
        address vault,
        uint32 buyFee,
        uint32 sellFee,
        uint32 burnFee
    );

    event StablecoinsChanged(address token, bool buyOrSell, bool addOrDelete);

    modifier isStarted() {
        require(f > 0 && initialized, "Market: is not started");
        _;
    }

    modifier canBuy(address token) {
        require(stablecoinsCanBuy.contains(token), "Market: invalid buy token");
        _;
    }

    modifier canSell(address token) {
        require(
            stablecoinsCanSell.contains(token),
            "Market: invalid sell token"
        );
        _;
    }

    /**
     * @dev Constructor.
     * NOTE This function can only called through delegatecall.
     * @param _Chaos - Chaos token address.
     * @param _prChaos - prChaos token address.
     * @param _pool - StakePool contract addresss.
     * @param _k - Slope.
     * @param _target - Target funding ratio.
     * @param _targetAdjusted - Target adjusted funding ratio.
     * @param _manager - Manager address.
     * @param _stablecoins - Stablecoin addresses.
     */
    function constructor1(
        IERC20BurnableMinter _Chaos,
        IERC20BurnableMinter _prChaos,
        IStakePool _pool,
        uint256 _k,
        uint32 _target,
        uint32 _targetAdjusted,
        address _manager,
        address[] memory _stablecoins
    ) external override isDelegateCall isUninitialized {
        minTarget = 1;
        maxTargetAdjusted = 10000;
        require(_Chaos.decimals() == 18, "Market: invalid Chaos token");
        require(_prChaos.decimals() == 18, "Market: invalid prChaos token");
        require(
            _k > 0 &&
                _target >= minTarget &&
                _targetAdjusted > _target &&
                _targetAdjusted <= maxTargetAdjusted,
            "Market: invalid constructor args"
        );
        Chaos = _Chaos;
        prChaos = _prChaos;
        pool = _pool;
        k = _k;
        target = _target;
        targetAdjusted = _targetAdjusted;
        _setupRole(MANAGER_ROLE, _manager);
        _setupRole(DEFAULT_ADMIN_ROLE, _manager);
        for (uint256 i = 0; i < _stablecoins.length; i++) {
            address token = _stablecoins[i];
            uint8 decimals = IERC20Metadata(token).decimals();
            require(decimals > 0, "Market: invalid token");
            stablecoinsCanBuy.add(token);
            stablecoinsCanSell.add(token);
            stablecoinsDecimals[token] = decimals;
            emit StablecoinsChanged(token, true, true);
            emit StablecoinsChanged(token, false, true);
        }
    }

    /**
     * @dev Startup market.
     *      The caller has STARTUP_ROLE.
     * @param _token - Initial stablecoin address
     * @param _w - Initial stablecoin worth
     * @param _t - Initial chaos total supply
     */
    function startup(
        address _token,
        uint256 _w,
        uint256 _t
    ) external override onlyRole(STARTUP_ROLE) isInitialized canBuy(_token) {
        require(raiseStep > 0, "Market: setAdjustOptions");
        require(dev != address(0), "Market: setFeeOptions");
        require(f == 0, "Market: is started");
        uint256 worth1e18 = Math.convertDecimals(
            _w,
            stablecoinsDecimals[_token],
            18
        );
        require(
            worth1e18 > 0 && _t > 0 && Chaos.totalSupply() == 0,
            "Market: invalid startup"
        );
        IERC20(_token).safeTransferFrom(_msgSender(), address(this), _w);
        Chaos.mint(_msgSender(), _t);
        w = worth1e18;
        adjustMustSucceed(_t);
    }

    /**
     * @dev Get the number of stablecoins that can buy Chaos.
     */
    function stablecoinsCanBuyLength()
        external
        view
        override
        returns (uint256)
    {
        return stablecoinsCanBuy.length();
    }

    /**
     * @dev Get the address of the stablecoin that can buy Chaos according to the index.
     * @param index - Stablecoin index
     */
    function stablecoinsCanBuyAt(uint256 index)
        external
        view
        override
        returns (address)
    {
        return stablecoinsCanBuy.at(index);
    }

    /**
     * @dev Get whether the token can be used to buy Chaos.
     * @param token - Token address
     */
    function stablecoinsCanBuyContains(address token)
        external
        view
        override
        returns (bool)
    {
        return stablecoinsCanBuy.contains(token);
    }

    /**
     * @dev Get the number of stablecoins that can be exchanged with Chaos.
     */
    function stablecoinsCanSellLength()
        external
        view
        override
        returns (uint256)
    {
        return stablecoinsCanSell.length();
    }

    /**
     * @dev Get the address of the stablecoin that can be exchanged with Chaos,
     *      according to the index.
     * @param index - Stablecoin index
     */
    function stablecoinsCanSellAt(uint256 index)
        external
        view
        override
        returns (address)
    {
        return stablecoinsCanSell.at(index);
    }

    /**
     * @dev Get whether the token can be exchanged with Chaos.
     * @param token - Token address
     */
    function stablecoinsCanSellContains(address token)
        external
        view
        override
        returns (bool)
    {
        return stablecoinsCanSell.contains(token);
    }

    /**
     * @dev Calculate current funding ratio.
     */
    function currentFundingRatio()
        public
        view
        override
        isStarted
        returns (uint256 numerator, uint256 denominator)
    {
        return currentFundingRatio(Chaos.totalSupply());
    }

    /**
     * @dev Calculate current funding ratio.
     * @param _t - Total supply
     */
    function currentFundingRatio(uint256 _t)
        internal
        view
        returns (uint256 numerator, uint256 denominator)
    {
        if (_t > p) {
            uint256 temp = _t - p;
            numerator = temp * temp;
            denominator = 2 * f * _t * k + numerator;
        } else {
            denominator = 1;
        }
    }

    /**
     * @dev Estimate adjust result.
     * @param _k - Slope
     * @param _tar - Target funding ratio
     * @param _w - Total worth
     * @param _t - Total supply
     * @return success - Whether the calculation was successful
     * @return _c - Current price
     * @return _f - Floor price
     * @return _p - Point of intersection
     */
    function estimateAdjust(
        uint256 _k,
        uint256 _tar,
        uint256 _w,
        uint256 _t
    )
        public
        pure
        override
        returns (
            bool success,
            uint256 _c,
            uint256 _f,
            uint256 _p
        )
    {
        _f = (1e18 * _w - 1e14 * _w * _tar) / _t;
        uint256 temp = Math.sqrt(2 * _tar * _w * _k * 1e14);
        if (_t >= temp) {
            _p = _t - temp;
            _c = (temp + _k * _f) / _k;
            // make sure the price is greater than 0
            if (_f > 0 && _c > _f) {
                success = true;
            }
        }
    }

    /**
     * @dev Estimate next raise price.
     * @return success - Whether the calculation was successful
     * @return _t - The total supply when the funding ratio reaches targetAdjusted
     * @return _c - The price when the funding ratio reaches targetAdjusted
     * @return _w - The total worth when the funding ratio reaches targetAdjusted
     * @return raisedFloorPrice - The floor price after market adjusted
     */
    function estimateRaisePrice()
        external
        view
        override
        isStarted
        returns (
            bool success,
            uint256 _t,
            uint256 _c,
            uint256 _w,
            uint256 raisedFloorPrice
        )
    {
        return estimateRaisePrice(f, k, p, target, targetAdjusted);
    }

    /**
     * @dev Estimate raise price by input value.
     * @param _f - Floor price
     * @param _k - Slope
     * @param _p - Floor supply
     * @param _tar - Target funding ratio
     * @param _tarAdjusted - Target adjusted funding ratio
     * @return success - Whether the calculation was successful
     * @return _t - The total supply when the funding ratio reaches _tar
     * @return _c - The price when the funding ratio reaches _tar
     * @return _w - The total worth when the funding ratio reaches _tar
     * @return raisedFloorPrice - The floor price after market adjusted
     */
    function estimateRaisePrice(
        uint256 _f,
        uint256 _k,
        uint256 _p,
        uint256 _tar,
        uint256 _tarAdjusted
    )
        public
        pure
        override
        returns (
            bool success,
            uint256 _t,
            uint256 _c,
            uint256 _w,
            uint256 raisedFloorPrice
        )
    {
        uint256 temp = (2 * _f * _tarAdjusted * _k) / (10000 - _tarAdjusted);
        _t = (2 * _p + temp + Math.sqrt(temp * temp + 4 * temp * _p)) / 2;
        if (_t > _p) {
            temp = _t - _p;
            _c = (temp + _k * _f) / _k;
            _w = (temp * temp + 2 * _f * _t * _k) / (2 * _k * 1e18);
            // make sure the price is greater than 0
            if (_f > 0 && _c > _f) {
                // prettier-ignore
                (success, , raisedFloorPrice, ) = estimateAdjust(_k, _tar, _w, _t);
            }
        }
    }

    /**
     * @dev Adjust will call estimateAdjust and set the result to storage,
     *      if the adjustment fails, the transaction will be reverted
     * @param _t - Total supply
     */
    function adjustMustSucceed(uint256 _t) internal {
        // update timestamp
        latestUpdateTimestamp = block.timestamp;
        // prettier-ignore
        (bool success, uint256 _c, uint256 _f, uint256 _p) = estimateAdjust(k, target, w, _t);
        require(success, "Market: adjust failed");
        c = _c;
        f = _f;
        p = _p;
        emit Adjust(_c, _f, _p);
    }

    /**
     * @dev Adjust will call estimateAdjust and set the result to storage.
     * @param _t - Total supply
     * @param _trigger - Trigger user address, if it is address(0), the rise will never be triggered
     */
    function adjustAndRaise(uint256 _t, address _trigger) internal {
        // update timestamp
        latestUpdateTimestamp = block.timestamp;
        // prettier-ignore
        (bool success, uint256 _c, uint256 _f, uint256 _p) = estimateAdjust(k, target, w, _t);
        // only update the storage data when the estimate is successful
        if (success && _f >= f) {
            c = _c;
            f = _f;
            p = _p;
            emit Adjust(_c, _f, _p);
            if (_trigger != address(0) && targetAdjusted < maxTargetAdjusted) {
                uint32 raisedStep = raiseStep;
                if (targetAdjusted + raisedStep > maxTargetAdjusted) {
                    raisedStep = maxTargetAdjusted - targetAdjusted;
                }
                if (raisedStep > 0) {
                    target += raisedStep;
                    targetAdjusted += raisedStep;
                    emit Raise(_trigger, target, targetAdjusted);
                }
            }
        }
    }

    /**
     * @dev Lower target and targetAdjusted with lowerStep.
     */
    function lowerAndAdjust() public override isStarted whenNotPaused {
        lowerAndAdjust(Chaos.totalSupply());
    }

    /**
     * @dev Lower target and targetAdjusted with lowerStep.
     * @param _t - Total supply
     */
    function lowerAndAdjust(uint256 _t) internal {
        if (block.timestamp > latestUpdateTimestamp && lowerInterval > 0) {
            uint32 loweredStep = (lowerStep *
                uint32(block.timestamp - latestUpdateTimestamp)) /
                lowerInterval;
            if (loweredStep > 0) {
                // update timestamp.
                latestUpdateTimestamp = block.timestamp;
                if (target == minTarget) {
                    // there is no need to lower ratio.
                    return;
                }
                if (target < loweredStep || target - loweredStep < minTarget) {
                    loweredStep = target - minTarget;
                }
                target -= loweredStep;
                targetAdjusted -= loweredStep;
                emit Lower(target, targetAdjusted);
                // check if we need to adjust again
                (uint256 n, uint256 d) = currentFundingRatio(_t);
                if (n * 10000 > d * targetAdjusted) {
                    adjustAndRaise(_t, address(0));
                }
            }
        }
    }

    /**
     * @dev If the current funding ratio reaches targetAjusted,
     *      we will increase f and p to bring the funding ratio back to target,
     *      otherwise we will try to lower funding ratio
     */
    function lowerOrRaise(address user) internal {
        uint256 _t = Chaos.totalSupply();
        (uint256 n, uint256 d) = currentFundingRatio(_t);
        if (n * 10000 > d * targetAdjusted) {
            adjustAndRaise(_t, user);
        } else {
            lowerAndAdjust(_t);
        }
    }

    /**
     * @dev Set market options.
     *      The caller must has MANAGER_ROLE.
     *      This function can only be called before the market is started.
     * @param _k - Slope
     * @param _target - Target funding ratio
     * @param _targetAdjusted - Target adjusted funding ratio
     */
    function setMarketOptions(
        uint256 _k,
        uint32 _target,
        uint32 _targetAdjusted
    ) external override onlyRole(MANAGER_ROLE) {
        require(f == 0, "Market: is started");
        require(_k > 0, "Market: invalid slope");
        require(
            _target >= minTarget &&
                _targetAdjusted > _target &&
                _targetAdjusted <= maxTargetAdjusted,
            "Market: invalid ratio"
        );
        k = _k;
        target = _target;
        targetAdjusted = _targetAdjusted;
    }

    /**
     * @dev Set adjust options.
     *      The caller must has MANAGER_ROLE.
     * @param _minTarget - Minimum value of target
     * @param _maxTargetAdjusted - Maximum value of the targetAdjusted
     * @param _raiseStep - Step value of each raise
     * @param _lowerStep - Step value of each lower
     * @param _lowerInterval - Interval of each lower
     */
    function setAdjustOptions(
        uint32 _minTarget,
        uint32 _maxTargetAdjusted,
        uint32 _raiseStep,
        uint32 _lowerStep,
        uint32 _lowerInterval
    ) external override onlyRole(MANAGER_ROLE) {
        require(
            _minTarget > 0 && _minTarget <= target,
            "Market: invalid minTarget"
        );
        require(
            _maxTargetAdjusted <= 10000 && _maxTargetAdjusted >= targetAdjusted,
            "Market: invalid maxTargetAdjusted"
        );
        require(_raiseStep <= 10000, "Market: raiseStep is too large");
        require(_lowerStep <= 10000, "Market: lowerStep is too large");
        minTarget = _minTarget;
        maxTargetAdjusted = _maxTargetAdjusted;
        raiseStep = _raiseStep;
        lowerStep = _lowerStep;
        lowerInterval = _lowerInterval;
        emit AdjustOptionsChanged(
            _minTarget,
            _maxTargetAdjusted,
            _raiseStep,
            _lowerStep,
            _lowerInterval
        );
    }

    /**
     * @dev Set fee options.
     *      The caller must has MANAGER_ROLE.
     * @param _dev - Dev address
     * @param _vault - Vault address
     * @param _buyFee - Dev fee for buying Chaos
     * @param _sellFee - Vault fee for selling Chaos
     * @param _burnFee - Burn fee for selling Chaos
     */
    function setFeeOptions(
        address _dev,
        address _vault,
        uint32 _buyFee,
        uint32 _sellFee,
        uint32 _burnFee
    ) external override onlyRole(MANAGER_ROLE) {
        require(_dev != address(0), "Market: zero dev address");
        require(_vault != address(0), "Market: zero vault address");
        require(_buyFee <= 10000, "Market: invalid buyFee");
        require(_sellFee <= 10000, "Market: invalid sellFee");
        require(_burnFee <= 10000, "Market: invalid burnFee");
        dev = _dev;
        vault = _vault;
        buyFee = _buyFee;
        sellFee = _sellFee;
        burnFee = _burnFee;
        emit FeeOptionsChanged(_dev, _vault, _buyFee, _sellFee, _burnFee);
    }

    /**
     * @dev Add a stablecoin that can buy CHAOS.
     *      The caller must has ADD_STABLECOIN_ROLE.
     * @param token - Stablecoin address
     */
    function addBuyStablecoin(address token)
        external
        onlyRole(ADD_STABLECOIN_ROLE)
    {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals > 0, "Market: invalid token");
        stablecoinsDecimals[token] = decimals;
        stablecoinsCanBuy.add(token);
        emit StablecoinsChanged(token, true, true);
    }

    /**
     * @dev Manage stablecoins.
     *      Add/Delete token to/from stablecoinsCanBuy/stablecoinsCanSell.
     *      The caller must has MANAGER_ROLE.
     * @param token - Stablecoin address
     * @param buyOrSell - Buy or sell token
     * @param addOrDelete - Add or delete token
     */
    function manageStablecoins(
        address token,
        bool buyOrSell,
        bool addOrDelete
    ) external override onlyRole(MANAGER_ROLE) {
        if (addOrDelete) {
            uint8 decimals = IERC20Metadata(token).decimals();
            require(decimals > 0, "Market: invalid token");
            stablecoinsDecimals[token] = decimals;
            if (buyOrSell) {
                // we need to ensure that other stable coins will not be exchanged for air coins
                // stablecoinsCanBuy[token] = decimals;
                revert("Market: please call addBuyStablecoin!");
            } else {
                stablecoinsCanSell.add(token);
            }
        } else {
            if (buyOrSell) {
                stablecoinsCanBuy.remove(token);
            } else {
                stablecoinsCanSell.remove(token);
            }
        }
        emit StablecoinsChanged(token, buyOrSell, addOrDelete);
    }

    /**
     * @dev Estimate how much Chaos user can buy.
     * @param token - Stablecoin address
     * @param tokenWorth - Number of stablecoins
     * @return amount - Number of Chaos
     * @return fee - Dev fee
     * @return worth1e18 - The amount of stablecoins being exchanged(1e18)
     * @return newPrice - New Chaos price
     */
    function estimateBuy(address token, uint256 tokenWorth)
        public
        view
        override
        canBuy(token)
        isStarted
        returns (
            uint256 amount,
            uint256 fee,
            uint256 worth1e18,
            uint256 newPrice
        )
    {
        uint256 _c = c;
        uint256 _k = k;
        // convert token decimals to 18
        worth1e18 = Math.convertDecimals(
            tokenWorth,
            stablecoinsDecimals[token],
            18
        );
        uint256 a = Math.sqrt(_c * _c * _k * _k + 2 * worth1e18 * _k * 1e18);
        uint256 b = _c * _k;
        if (a > b) {
            uint256 _amount = a - b;
            uint256 _newPrice = (_c * _k + _amount) / _k;
            if (_newPrice > _c && _amount > 0) {
                amount = _amount;
                newPrice = _newPrice;
            }
        }
        // calculate developer fee
        fee = (amount * buyFee) / 10000;
        // calculate amount
        amount -= fee;
    }

    /**
     * @dev Estimate how many stablecoins will be needed to realize prChaos.
     * @param amount - Number of prChaos user want to realize
     * @param token - Stablecoin address
     * @return worth1e18 - The amount of stablecoins being exchanged(1e18)
     * @return worth - The amount of stablecoins being exchanged
     */
    function estimateRealize(uint256 amount, address token)
        public
        view
        override
        canBuy(token)
        isStarted
        returns (uint256 worth1e18, uint256 worth)
    {
        // calculate amount of stablecoins being exchanged at the floor price
        worth1e18 = (f * amount) / 1e18;
        // convert decimals
        uint8 decimals = stablecoinsDecimals[token];
        worth = Math.convertDecimalsCeil(worth1e18, 18, decimals);
        if (decimals < 18) {
            // if decimals is less than 18, drop precision
            worth1e18 = Math.convertDecimals(worth, decimals, 18);
        }
    }

    /**
     * @dev Estimate how much stablecoins user can sell.
     * @param amount - Number of Chaos user want to sell
     * @param token - Stablecoin address
     * @return fee - Vault fee
     * @return worth1e18 - The amount of stablecoins being exchanged(1e18)
     * @return worth - The amount of stablecoins being exchanged
     * @return newPrice - New Chaos price
     * @return newFloorPrice - New Chaos floor price
     */
    function estimateSell(uint256 amount, address token)
        public
        view
        override
        canSell(token)
        isStarted
        returns (
            uint256 fee,
            uint256 worth1e18,
            uint256 worth,
            uint256 newPrice,
            uint256 newFloorPrice
        )
    {
        uint256 _c = c;
        uint256 _f = f;
        uint256 _t = Chaos.totalSupply();
        // calculate developer fee
        fee = (amount * sellFee) / 10000;
        // calculate amount and burn amount
        amount -= fee;
        uint256 burnAmount = amount;
        // calculate the Chaos worth that can be sold with the slope
        if (_t > p) {
            uint256 available = _t - p;
            if (available <= amount) {
                uint256 _worth = ((_f + _c) * available) / (2 * 1e18);
                newPrice = _f;
                worth1e18 += _worth;
                amount -= available;
            } else {
                uint256 _newPrice = (_c * k - amount) / k;
                uint256 _worth = ((_newPrice + _c) * amount) / (2 * 1e18);
                if (_newPrice < _c && _newPrice >= _f && _worth > 0) {
                    newPrice = _newPrice;
                    worth1e18 += _worth;
                }
                amount = 0;
            }
        }
        // calculate the Chaos worth that can be sold at the floor price
        if (amount > 0) {
            newPrice = _f;
            worth1e18 += (amount * _f) / 1e18;
        }
        // a portion of the worth will be used to increase the price
        uint256 burnWorth = (worth1e18 * burnFee) / 10000;
        if (_t > burnAmount) {
            uint256 risingPrice = (burnWorth * 1e18) / (_t - burnAmount);
            newPrice += risingPrice;
            newFloorPrice = _f + risingPrice;
            worth1e18 -= burnWorth;
        } else {
            newFloorPrice = _f;
        }
        // convert decimals
        uint8 decimals = stablecoinsDecimals[token];
        worth = Math.convertDecimals(worth1e18, 18, decimals);
        if (decimals < 18) {
            // if decimals is less than 18, drop precision
            worth1e18 = Math.convertDecimals(worth, decimals, 18);
        }
    }

    /**
     * @dev Buy Chaos.
     * @param token - Address of stablecoin used to buy Chaos
     * @param tokenWorth - Number of stablecoins
     * @param desired - Minimum amount of Chaos user want to buy
     * @return amount - Number of Chaos
     * @return fee - Dev fee(Chaos)
     */
    function buy(
        address token,
        uint256 tokenWorth,
        uint256 desired
    ) external override whenNotPaused returns (uint256, uint256) {
        return buyFor(token, tokenWorth, desired, _msgSender());
    }

    /**
     * @dev Buy Chaos for user.
     * @param token - Address of stablecoin used to buy Chaos
     * @param tokenWorth - Number of stablecoins
     * @param desired - Minimum amount of Chaos user want to buy
     * @param user - User address
     * @return amount - Number of Chaos
     * @return fee - Dev fee(Chaos)
     */
    function buyFor(
        address token,
        uint256 tokenWorth,
        uint256 desired,
        address user
    ) public override whenNotPaused returns (uint256, uint256) {
        (
            uint256 amount,
            uint256 fee,
            uint256 worth1e18,
            uint256 newPrice
        ) = estimateBuy(token, tokenWorth);
        require(
            worth1e18 > 0 && amount > 0 && newPrice > 0,
            "Market: useless transaction"
        );
        require(
            amount >= desired,
            "Market: mint amount is less than desired amount"
        );
        IERC20(token).safeTransferFrom(_msgSender(), address(this), tokenWorth);
        pool.massUpdatePools();
        Chaos.mint(_msgSender(), amount);
        Chaos.mint(dev, fee);
        emit Buy(user, token, tokenWorth, amount, fee);
        // update current price
        c = newPrice;
        // cumulative total worth
        w += worth1e18;
        // lower or raise price
        lowerOrRaise(user);
        return (amount, fee);
    }

    /**
     * @dev Realize Chaos with floor price and equal amount of prChaos.
     * @param amount - Amount of prChaos user want to realize
     * @param token - Address of stablecoin used to realize prChaos
     * @param desired - Maximum amount of stablecoin users are willing to pay
     * @return worth - The amount of stablecoins being exchanged
     */
    function realize(
        uint256 amount,
        address token,
        uint256 desired
    ) public override whenNotPaused returns (uint256) {
        return realizeFor(amount, token, desired, _msgSender());
    }

    /**
     * @dev Realize Chaos with floor price and equal amount of prChaos for user.
     * @param amount - Amount of prChaos user want to realize
     * @param token - Address of stablecoin used to realize prChaos
     * @param desired - Maximum amount of stablecoin users are willing to pay
     * @param user - User address
     * @return worth - The amount of stablecoins being exchanged
     */
    function realizeFor(
        uint256 amount,
        address token,
        uint256 desired,
        address user
    ) public override whenNotPaused returns (uint256) {
        (uint256 worth1e18, uint256 worth) = estimateRealize(amount, token);
        require(worth > 0, "Market: useless transaction");
        require(
            worth <= desired,
            "Market: worth is greater than desired worth"
        );
        IERC20(token).safeTransferFrom(_msgSender(), address(this), worth);
        prChaos.burnFrom(_msgSender(), amount);
        pool.massUpdatePools();
        Chaos.mint(_msgSender(), amount);
        emit Realize(user, token, worth, amount);
        // cumulative total worth
        w += worth1e18;
        // let p translate to the right
        p += amount;
        // try to lower funding ratio
        lowerAndAdjust();
        return worth;
    }

    /**
     * @dev Sell Chaos.
     * @param amount - Amount of Chaos user want to sell
     * @param token - Address of stablecoin used to buy Chaos
     * @param desired - Minimum amount of stablecoins user want to get
     * @return fee - Vault fee(Chaos)
     * @return worth - The amount of stablecoins being exchanged
     */
    function sell(
        uint256 amount,
        address token,
        uint256 desired
    ) external override whenNotPaused returns (uint256, uint256) {
        return sellFor(amount, token, desired, _msgSender());
    }

    /**
     * @dev Sell Chaos for user.
     * @param amount - Amount of Chaos user want to sell
     * @param token - Address of stablecoin used to buy Chaos
     * @param desired - Minimum amount of stablecoins user want to get
     * @param user - User address
     * @return fee - Vault fee(Chaos)
     * @return worth - The amount of stablecoins being exchanged
     */
    function sellFor(
        uint256 amount,
        address token,
        uint256 desired,
        address user
    ) public override whenNotPaused returns (uint256, uint256) {
        (
            uint256 fee,
            uint256 worth1e18,
            uint256 worth,
            uint256 newPrice,
            uint256 newFloorPrice
        ) = estimateSell(amount, token);
        require(
            worth > 0 && newPrice > 0 && newFloorPrice > 0,
            "Market: useless transaction"
        );
        require(worth >= desired, "Market: worth is less than desired worth");
        pool.massUpdatePools();
        Chaos.burnFrom(_msgSender(), amount - fee);
        Chaos.transferFrom(_msgSender(), vault, fee);
        IERC20(token).safeTransfer(_msgSender(), worth);
        emit Sell(user, token, amount - fee, worth, fee);
        // update current price
        c = newPrice;
        // update floor price
        f = newFloorPrice;
        // reduce total worth
        w -= worth1e18;
        // if we reach the floor price,
        // let p translate to the left
        if (newPrice == f) {
            p = Chaos.totalSupply();
        }
        // lower or raise price
        lowerOrRaise(user);
        return (worth, fee);
    }

    /**
     * @dev Burn Chaos.
     *      It will preferentially transfer the excess value after burning to PSL.
     * @param amount - The amount of Chaos the user wants to burn
     */
    function burn(uint256 amount) external override isStarted whenNotPaused {
        burnFor(amount, _msgSender());
    }

    /**
     * @dev Burn Chaos for user.
     *      It will preferentially transfer the excess value after burning to PSL.
     * @param amount - The amount of Chaos the user wants to burn
     * @param user - User address
     */
    function burnFor(uint256 amount, address user)
        public
        override
        isStarted
        whenNotPaused
    {
        require(amount > 0, "Market: amount is zero");
        pool.massUpdatePools();
        Chaos.burnFrom(_msgSender(), amount);
        uint256 _t = Chaos.totalSupply();
        require(_t > 0, "Market: can't burn all chaos");
        uint256 _f = f;
        uint256 _k = k;
        uint256 _w = w;
        // x = t - p
        uint256 x = Math.sqrt(2 * _w * _k * 1e18 - 2 * _f * _t * _k);
        require(x > 0, "Market: amount is too small");
        if (x < _t) {
            uint256 _c = (_f * _k + x) / _k;
            require(_c > _f, "Market: amount is too small");
            c = _c;
            p = _t - x;
        } else {
            _f = (2 * _w * _k * 1e18 - _t * _t) / (2 * _t * _k);
            uint256 _c = (_f * _k + _t) / _k;
            require(_f > f && _c > _f, "Market: burn failed");
            c = _c;
            f = _f;
            p = 0;
        }
        emit Burn(user, amount);
        // lower or raise price
        lowerOrRaise(user);
    }

    /**
     * @dev Triggers stopped state.
     *      The caller must has MANAGER_ROLE.
     */
    function pause() external override onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     *      The caller must has MANAGER_ROLE.
     */
    function unpause() external override onlyRole(MANAGER_ROLE) {
        _unpause();
    }
}

