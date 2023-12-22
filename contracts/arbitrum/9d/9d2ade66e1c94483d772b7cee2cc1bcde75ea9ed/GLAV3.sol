// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Context.sol";
import "./IMarket.sol";

struct UserInfo {
    // remaining unreleased Chaos
    uint256 left;
    // the timestamp of the last claim
    uint256 latestTimestamp;
}

/**
 * Change log:
 * Refactor, add linear release logic, cancel whitelist.
 */
contract GenesisLaunchAuctionV3 is Context {
    using SafeERC20 for IERC20;

    // Chaos price
    uint256 public price;
    // sale phase start time
    uint256 public startAt;
    // sale phase end time
    uint256 public endAt;
    // Chaos release duration
    uint256 public duration;
    // soft USD cap,
    // if the final USD cap does not reach softCap, the market will not start
    uint256 public softCap;
    // hard USD cap,
    // the final USD cap will not exceed hardCap
    uint256 public hardCap;

    // Chaos token address
    IERC20 public Chaos;
    // USD token address
    IERC20 public USD;
    // Market contract address
    IMarket public market;

    // initialization time
    uint256 public initAt;
    // a flag to mark if it has been initialized
    bool public initialized = false;
    // total shares
    uint256 public totalShares;
    // share per user
    mapping(address => uint256) public sharesOf;
    // user release information
    mapping(address => UserInfo) public userInfo;

    constructor(
        uint256 _price,
        uint256 _startAt,
        uint256 _endAt,
        uint256 _duration,
        uint256 _softCap,
        uint256 _hardCap,
        IERC20 _Chaos,
        IERC20 _USD,
        IMarket _market
    ) {
        require(
            _price > 0 &&
                _startAt >= block.timestamp &&
                _endAt > _startAt &&
                _duration > 0 &&
                _softCap > 0 &&
                _hardCap > _softCap,
            "GLA: invalid constructor args"
        );
        price = _price;
        startAt = _startAt;
        endAt = _endAt;
        duration = _duration;
        softCap = _softCap;
        hardCap = _hardCap;
        Chaos = _Chaos;
        USD = _USD;
        market = _market;
    }

    modifier buyable() {
        require(
            !initialized &&
                block.timestamp >= startAt &&
                block.timestamp < endAt,
            "GLA: unbuyable"
        );
        _;
    }

    modifier initializable() {
        require(
            !initialized && initAt == 0 && block.timestamp >= endAt,
            "GLA: uninitializable"
        );
        _;
        initialized = true;
        initAt = block.timestamp;
    }

    modifier claimable() {
        require(
            initialized && block.timestamp > initAt && totalShares >= softCap,
            "GLA: unclaimable"
        );
        _;
    }

    modifier withdrawable() {
        require(
            initialized && block.timestamp > initAt && totalShares < softCap,
            "GLA: unwithdrawable"
        );
        _;
    }

    /**
     * @dev Get total Chaos supply(1e18).
     */
    function getTotalSupply() public view returns (uint256) {
        if (totalShares >= hardCap) {
            return (hardCap * 1e18) / price;
        } else {
            return (totalShares * 1e18) / price;
        }
    }

    /**
     * @dev Get the current phase enumeration.
     */
    function getPhase() external view returns (uint8) {
        if (block.timestamp < startAt) {
            // before sale phase
            return 0;
        } else if (block.timestamp >= startAt && block.timestamp < endAt) {
            // sale phase
            return 1;
        } else {
            if (!initialized) {
                // waiting for initial phase
                return 2;
            } else if (totalShares >= softCap) {
                // claim phase
                return 3;
            } else {
                // withdraw phase
                return 4;
            }
        }
    }

    /**
     * @dev Esimate how many Chaos you can buy.
     * @param amount - USD amount
     */
    function estimateBuy(uint256 amount) external view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 _totalShares = totalShares + amount;
        if (_totalShares >= hardCap) {
            return (amount * hardCap * 1e18) / _totalShares / price;
        } else {
            return (amount * 1e18) / price;
        }
    }

    /**
     * @dev Buy Chaos.
     * @param amount - USD amount
     */
    function buy(uint256 amount) external buyable {
        require(amount > 0, "GLA: zero amount");
        USD.safeTransferFrom(_msgSender(), address(this), amount);
        totalShares += amount;
        sharesOf[_msgSender()] += amount;
    }

    /**
     * @dev Initialize GLA.
     */
    function initialize() external initializable {
        uint256 _totalCap;
        if (totalShares >= hardCap) {
            _totalCap = hardCap;
        } else if (totalShares >= softCap) {
            _totalCap = totalShares;
        } else {
            // launch failed,
            // enter the withdraw phase
            return;
        }
        uint256 _totalSupply = (_totalCap * 1e18) / price;

        USD.safeApprove(address(market), _totalCap);
        uint256 _USDBalance1 = USD.balanceOf(address(this));
        uint256 _CHAOSBalance1 = Chaos.balanceOf(address(this));
        market.startup(address(USD), _totalCap, _totalSupply);
        uint256 _USDBalance2 = USD.balanceOf(address(this));
        uint256 _CHAOSBalance2 = Chaos.balanceOf(address(this));
        require(
            _USDBalance1 - _USDBalance2 == _totalCap &&
                _CHAOSBalance2 - _CHAOSBalance1 == _totalSupply,
            "GLA: initialize failed"
        );

        // launch successfully,
        // enter the claim phase
    }

    function _estimateTotalChaosFirstTime(address user)
        private
        view
        returns (uint256 total, uint256 refunded)
    {
        if (totalShares >= hardCap) {
            uint256 amount = (sharesOf[user] * hardCap) / totalShares;
            total = (amount * 1e18) / price;
            refunded = sharesOf[user] - amount;
        } else {
            total = (sharesOf[user] * 1e18) / price;
        }
    }

    /**
     * @dev Estimate how many Chaos you can claim.
     * @param user - User address
     * @return total - Chaos amount
     * @return refunded - Refund USD amount
     * @return released - Release Chaos amount
     */
    function estimateClaim(address user)
        external
        view
        returns (
            uint256 total,
            uint256 refunded,
            uint256 released
        )
    {
        uint256 latestTimestamp;
        UserInfo memory ui = userInfo[user];
        if (ui.latestTimestamp == 0) {
            (total, refunded) = _estimateTotalChaosFirstTime(user);
            latestTimestamp = initAt;
        } else {
            total = ui.left;
            latestTimestamp = ui.latestTimestamp;
        }
        if (initAt > 0) {
            uint256 endTimestamp = initAt + duration;
            if (
                latestTimestamp < block.timestamp &&
                block.timestamp < endTimestamp
            ) {
                // we are releasing,
                // linearly calculate the number of Chaos released
                released =
                    (total * (block.timestamp - latestTimestamp)) /
                    (endTimestamp - latestTimestamp);
                if (released > total) {
                    released = total;
                }
            } else if (
                latestTimestamp < endTimestamp &&
                endTimestamp <= block.timestamp
            ) {
                // release all Chaos
                released = total;
            }
        }
    }

    /**
     * @dev Claim Chaos.
     *      Upon first claim, the excess amount will be automatically refunded.
     *      Can only be called after successfully launch.
     */
    function claim() external claimable {
        uint256 total;
        uint256 refunded;
        uint256 released;
        uint256 latestTimestamp;
        UserInfo storage ui = userInfo[_msgSender()];
        if (ui.latestTimestamp == 0) {
            // calculate total Chaos and refund USD
            (total, refunded) = _estimateTotalChaosFirstTime(_msgSender());
            latestTimestamp = initAt;
            delete sharesOf[_msgSender()];
        } else {
            total = ui.left;
            latestTimestamp = ui.latestTimestamp;
        }

        uint256 endTimestamp = initAt + duration;
        if (
            latestTimestamp < block.timestamp && block.timestamp < endTimestamp
        ) {
            // we are releasing,
            // linearly calculate the number of Chaos released
            released =
                (total * (block.timestamp - latestTimestamp)) /
                (endTimestamp - latestTimestamp);
            if (released > total) {
                released = total;
            }
            // update timestamp
            ui.latestTimestamp = block.timestamp;
        } else if (
            latestTimestamp < endTimestamp && endTimestamp <= block.timestamp
        ) {
            // release all Chaos
            released = total;
            // update timestamp
            ui.latestTimestamp = endTimestamp;
        }
        // update remaining Chaos
        ui.left = total - released;

        // transfer released Chaos
        if (released > 0) {
            uint256 max = Chaos.balanceOf(address(this));
            Chaos.transfer(_msgSender(), max < released ? max : released);
        }

        // refund USD
        if (refunded > 0) {
            uint256 max = USD.balanceOf(address(this));
            USD.safeTransfer(_msgSender(), max < refunded ? max : refunded);
        }
    }

    /**
     * @dev Withdraw USD.
     *      Can only be called after failed launch.
     */
    function withdraw() external withdrawable {
        uint256 shares = sharesOf[_msgSender()];
        require(shares > 0, "GLA: zero shares");
        uint256 max = USD.balanceOf(address(this));
        USD.safeTransfer(_msgSender(), max < shares ? max : shares);
        delete sharesOf[_msgSender()];
    }
}

