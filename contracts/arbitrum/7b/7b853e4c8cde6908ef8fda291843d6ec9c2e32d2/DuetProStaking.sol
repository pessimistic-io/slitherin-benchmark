// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IPool } from "./IPool.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "./IERC20MetadataUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { IDeriLens } from "./IDeriLens.sol";
import { Adminable } from "./Adminable.sol";
import { DuetMath } from "./DuetMath.sol";

import { IBoosterOracle } from "./IBoosterOracle.sol";
import { ArbSys } from "./ArbSys.sol";
import { IVault } from "./IVault.sol";

contract DuetProStaking is ReentrancyGuardUpgradeable, Adminable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    uint256 public constant PRECISION = 1e12;
    uint256 public constant LIQUIDITY_DECIMALS = 18;
    uint256 public constant PRICE_DECIMALS = 8;
    uint256 public constant MIN_BOOSTER_TOKENS = 10 ** 18;
    uint256 public constant MIN_LIQUIDITY_OPS = 10 ** 18;

    IPool public pool;
    IDeriLens public deriLens;
    IBoosterOracle public boosterOracle;
    IERC20MetadataUpgradeable public usdLikeUnderlying;
    uint256 public totalShares;
    uint256 public totalBoostedShares;
    uint256 public lastNormalLiquidity;
    uint256 public lastBoostedLiquidity;
    uint256 public totalStakedBoosterValue;
    uint256 public totalStakedBoosterAmount;

    uint256 public lastActionTime;
    uint256 public lastActionBlock;

    // user => token => amount
    mapping(address => mapping(address => uint256)) public userStakedBooster;

    // token => isSupported
    mapping(address => bool) public supportedBoosterTokens;

    // user => UserInfo
    mapping(address => UserInfo) public userInfos;

    uint256 public boosterLockDuration = 7 days;
    // user => block.timestamp
    mapping(address => uint256) public lastBoosterOperatedAt;

    struct UserInfo {
        uint256 shares;
        uint256 boostedShares;
        uint256 stakedBoosterValue;
        uint256 stakedBoosterAmount;
        uint256 lastActionTime;
        uint256 lastActionBlock;
        uint256 accAddedLiquidity;
        uint256 accRemovedLiquidity;
    }

    event AddSupportedBoosterToken(address indexed user, address token);
    event RemoveSupportedBoosterToken(address indexed user, address token);
    event StakeBooster(address indexed user, address booster, uint256 amount, uint256 value);
    event UnstakeBooster(address indexed user, address booster, uint256 amount, uint256 value);
    event AddLiquidity(address indexed user, uint256 liquidity);
    event RemoveLiquidity(address indexed user, uint256 liquidity);

    constructor() {
        // 30097 is the chain id of hardhat in hardhat.config.ts
        if (block.chainid != 30097) {
            _disableInitializers();
        }
    }

    function initialize(
        IPool pool_,
        IDeriLens deriLens_,
        IERC20MetadataUpgradeable usdLikeUnderlying_,
        IBoosterOracle boosterOracle_,
        address admin_
    ) external initializer {
        require(address(pool_) != address(0), "DuetProStaking: pool cannot be zero address");
        require(address(deriLens_) != address(0), "DuetProStaking: deriLens cannot be zero address");
        require(address(usdLikeUnderlying_) != address(0), "DuetProStaking: usdLikeUnderlying_ cannot be zero address");
        require(address(boosterOracle_) != address(0), "DuetProStaking: boosterOracle cannot be zero address");
        require(admin_ != address(0), "DuetProStaking: admin cannot be zero address");
        require(
            usdLikeUnderlying_.decimals() <= 18,
            "DuetProStaking: usdLikeUnderlying_ decimals must be less than 18"
        );

        boosterOracle = boosterOracle_;
        __ReentrancyGuard_init();
        pool = pool_;
        usdLikeUnderlying = usdLikeUnderlying_;
        deriLens = deriLens_;
        _setAdmin(admin_);
    }

    function setBoosterOracle(IBoosterOracle boosterOracle_) external onlyAdmin {
        boosterOracle = boosterOracle_;
    }

    function addSupportedBooster(IERC20MetadataUpgradeable booster_) external onlyAdmin {
        supportedBoosterTokens[address(booster_)] = true;
        emit AddSupportedBoosterToken(msg.sender, address(booster_));
    }

    function removeSupportedBooster(IERC20MetadataUpgradeable booster_) external onlyAdmin {
        delete supportedBoosterTokens[address(booster_)];
        emit RemoveSupportedBoosterToken(msg.sender, address(booster_));
    }

    function stakeBooster(IERC20MetadataUpgradeable booster_, uint256 amount_) external nonReentrant {
        require(supportedBoosterTokens[address(booster_)], "DuetProStaking: unsupported booster");

        uint256 normalizedAmount = normalizeDecimals(amount_, booster_.decimals(), LIQUIDITY_DECIMALS);
        require(
            normalizedAmount >= MIN_BOOSTER_TOKENS,
            "DuetProStaking: amount must be greater than MIN_BOOSTER_TOKENS"
        );
        address user = msg.sender;
        UserInfo storage userInfo = userInfos[user];
        lastBoosterOperatedAt[user] = block.timestamp;
        _updatePool();

        booster_.safeTransferFrom(user, address(this), amount_);
        userStakedBooster[user][address(booster_)] += normalizedAmount;
        userInfo.stakedBoosterAmount += normalizedAmount;
        totalStakedBoosterAmount += normalizedAmount;

        uint256 boosterValue = _getBoosterValue(booster_, normalizedAmount);
        userInfo.stakedBoosterValue += boosterValue;
        totalStakedBoosterValue += boosterValue;

        _touchUser(user);
        _updateUserBoostedShares(user);
        emit StakeBooster(user, address(booster_), amount_, boosterValue);
    }

    function unstakeBooster(IERC20MetadataUpgradeable booster_, uint256 amount_) external nonReentrant {
        address user = msg.sender;
        require(userStakedBooster[user][address(booster_)] >= amount_, "DuetProStaking: insufficient staked booster");
        // The lastBoosterOperatedAt value of the user who staked before the lock went live is 0
        if (lastBoosterOperatedAt[user] > 0 && block.timestamp < lastBoosterOperatedAt[user] + boosterLockDuration) {
            revert("DuetProStaking: booster locked");
        }
        UserInfo storage userInfo = userInfos[user];
        _updatePool();

        userStakedBooster[user][address(booster_)] -= amount_;
        userInfo.stakedBoosterAmount -= amount_;
        totalStakedBoosterAmount -= amount_;

        uint256 boosterValue = _getBoosterValue(booster_, amount_);
        if (userInfo.stakedBoosterValue <= boosterValue) {
            userInfo.stakedBoosterValue = 0;
        } else {
            userInfo.stakedBoosterValue -= boosterValue;
        }
        if (totalStakedBoosterValue <= boosterValue) {
            totalStakedBoosterValue = 0;
        } else {
            totalStakedBoosterValue -= boosterValue;
        }

        booster_.safeTransfer(user, amount_);
        _touchUser(user);
        _updateUserBoostedShares(user);
        emit UnstakeBooster(user, address(booster_), amount_, boosterValue);
    }

    function addLiquidity(uint256 underlyingAmount_, IPool.PythData calldata pythData) external payable nonReentrant {
        uint256 amount = normalizeDecimals(underlyingAmount_, usdLikeUnderlying.decimals(), LIQUIDITY_DECIMALS);
        require(amount >= MIN_LIQUIDITY_OPS, "DuetProStaking: amount must be greater than MIN_LIQUIDITY_OPS");
        _updatePool();
        address user = msg.sender;
        usdLikeUnderlying.safeTransferFrom(user, address(this), underlyingAmount_);
        usdLikeUnderlying.approve(address(pool), underlyingAmount_);
        pool.addLiquidity{ value: msg.value }(address(usdLikeUnderlying), underlyingAmount_, pythData);
        UserInfo storage userInfo = userInfos[user];
        uint256 totalNormalShares = totalShares - totalBoostedShares;

        uint256 addNormalShares = totalNormalShares > 0
            ? DuetMath.mulDiv(totalNormalShares, amount, lastNormalLiquidity)
            : amount;
        // Add to normal liquidity first, calc boosted shares post liquidity added, see _updateUserBoostedShares
        lastNormalLiquidity += amount;
        totalShares += addNormalShares;
        userInfo.shares += addNormalShares;
        _touchUser(user);
        userInfo.accAddedLiquidity += amount;
        _updateUserBoostedShares(user);
        emit AddLiquidity(user, amount);
    }

    function removeLiquidity(
        uint256 amount_,
        IPool.PythData calldata pythData
    )
        external
        payable
        nonReentrant
        returns (
            uint256 userNormalLiquidity,
            uint256 userBoostedLiquidity,
            uint256 normalSharesToRemove,
            uint256 userNormalShares,
            uint256 normalLiquidityToRemove
        )
    {
        uint256 amount = normalizeDecimals(amount_, usdLikeUnderlying.decimals(), LIQUIDITY_DECIMALS);
        _updatePool();
        address user = msg.sender;
        UserInfo storage userInfo = userInfos[user];
        (userNormalLiquidity, userBoostedLiquidity) = sharesToLiquidity(userInfo.shares, userInfo.boostedShares);
        uint256 userTotalLiquidity = userNormalLiquidity + userBoostedLiquidity;
        if (
            amount >= userTotalLiquidity ||
            userTotalLiquidity <= MIN_LIQUIDITY_OPS ||
            userTotalLiquidity - amount <= MIN_LIQUIDITY_OPS
        ) {
            amount = userTotalLiquidity;
        }
        userNormalShares = userInfo.shares - userInfo.boostedShares;
        uint256 boostedSharesToRemove;
        uint256 boostedLiquidityToRemove;
        if (amount <= userNormalLiquidity) {
            normalSharesToRemove = DuetMath.mulDiv(userNormalShares, amount, userNormalLiquidity);
            normalLiquidityToRemove = amount;
        } else {
            normalSharesToRemove = userNormalShares;
            normalLiquidityToRemove = userNormalLiquidity;
            boostedLiquidityToRemove = amount - userNormalLiquidity;

            boostedSharesToRemove = DuetMath.mulDiv(
                userInfo.boostedShares,
                boostedLiquidityToRemove,
                userBoostedLiquidity
            );
        }
        userInfo.shares -= (normalSharesToRemove + boostedSharesToRemove);
        totalShares -= (normalSharesToRemove + boostedSharesToRemove);
        lastNormalLiquidity -= normalLiquidityToRemove;

        userInfo.boostedShares -= boostedSharesToRemove;
        totalBoostedShares -= boostedSharesToRemove;
        lastBoostedLiquidity -= boostedLiquidityToRemove;

        _touchUser(user);
        userInfo.accRemovedLiquidity += amount;
        uint256 usdLikeAmount = normalizeDecimals(amount, LIQUIDITY_DECIMALS, usdLikeUnderlying.decimals());
        pool.removeLiquidity{ value: msg.value }(address(usdLikeUnderlying), usdLikeAmount, pythData);
        usdLikeUnderlying.safeTransfer(user, usdLikeAmount);

        emit RemoveLiquidity(user, amount);
    }

    function sharesToLiquidity(
        uint256 shares_,
        uint256 boostedShares_
    ) public view returns (uint256 normalLiquidity, uint256 boostedLiquidity) {
        (uint256 totalNormalLiquidity, uint256 totalBoostedLiquidity) = calcPool();
        uint256 normalShares = shares_ - boostedShares_;
        uint256 totalNormalShares = totalShares - totalBoostedShares;

        return (
            normalShares > 0 ? DuetMath.mulDiv(totalNormalLiquidity, normalShares, totalNormalShares) : 0,
            boostedShares_ > 0 ? DuetMath.mulDiv(totalBoostedLiquidity, boostedShares_, totalBoostedShares) : 0
        );
    }

    function amountToShares(uint256 amount_) external view returns (uint256) {
        (uint256 normalLiquidity, uint256 boostedLiquidity) = calcPool();
        return totalShares > 0 ? (amount_ * totalShares) / (normalLiquidity + boostedLiquidity) : amount_;
    }

    function getUserInfo(
        address user_
    ) external view returns (UserInfo memory info, uint256 normalLiquidity, uint256 boostedLiquidity) {
        (normalLiquidity, boostedLiquidity) = sharesToLiquidity(
            userInfos[user_].shares,
            userInfos[user_].boostedShares
        );
        return (userInfos[user_], normalLiquidity, boostedLiquidity);
    }

    function calcPool() public view returns (uint256 normalLiquidity, uint256 boostedLiquidity) {
        if (lastActionBlock == blockNumber()) {
            return (lastNormalLiquidity, lastBoostedLiquidity);
        }
        if (totalShares == 0) {
            return (0, 0);
        }
        IDeriLens.LpInfo memory lpInfo = getRemoteInfo();

        int256 intBalanceB0 = lpInfo.amountB0;
        if (lpInfo.vaultLiquidity > 0 && lpInfo.markets.length > 0) {
            require(
                lpInfo.markets[0].underlying == address(usdLikeUnderlying),
                "DuetProStaking: calc pool error, market underlying mismatch"
            );
            intBalanceB0 += int256(lpInfo.markets[0].vTokenBalance);
        }
        require(intBalanceB0 > 0, "DuetProStaking: calc pool error, negative balanceB0");
        uint256 balanceB0 = uint256(intBalanceB0);

        if (balanceB0 == 0) {
            return (0, 0);
        }
        int256 liquidityDelta = int256(balanceB0) - int256(lastNormalLiquidity + lastBoostedLiquidity);

        if (liquidityDelta == 0) {
            return (lastNormalLiquidity, lastBoostedLiquidity);
        }

        uint256 uintLiquidityDelta = uint256(liquidityDelta > 0 ? liquidityDelta : 0 - liquidityDelta);
        if (liquidityDelta < 0) {
            // no boost when pnl is negative
            uint256 boostedPnl = DuetMath.mulDiv(
                uintLiquidityDelta,
                lastBoostedLiquidity,
                lastNormalLiquidity + lastBoostedLiquidity
            );
            uint256 normalPnl = uintLiquidityDelta - boostedPnl;
            // To simplify subsequent calculations, negative numbers are not allowed in liquidity.
            // As an extreme case, when it occurs, the development team intervenes to handle it.
            // @see forceAddLiquidity
            require(lastNormalLiquidity >= normalPnl, "DuetProStaking: calc pool error, negative normal pnl");
            require(lastBoostedLiquidity >= boostedPnl, "DuetProStaking: calc pool error, negative boosted pnl");
            return (lastNormalLiquidity - normalPnl, lastBoostedLiquidity - boostedPnl);
        }

        uint256 boostedPnl = DuetMath.mulDiv(
            uintLiquidityDelta,
            // boostedShares can boost 2x
            lastBoostedLiquidity * 2,
            lastBoostedLiquidity * 2 + lastNormalLiquidity
        );
        uint256 normalPnl = uintLiquidityDelta - boostedPnl;
        return (lastNormalLiquidity + normalPnl, lastBoostedLiquidity + boostedPnl);
    }

    function _updatePool() internal {
        (lastNormalLiquidity, lastBoostedLiquidity) = calcPool();
        lastActionTime = block.timestamp;
        lastActionBlock = blockNumber();
    }

    function setBoosterLockDuration(uint256 duration) external onlyAdmin {
        boosterLockDuration = duration;
    }

    function getRemoteInfo() public view returns (IDeriLens.LpInfo memory lpInfo) {
        return deriLens.getLpInfo(address(pool), address(this));
    }

    function _boosterValue(IERC20MetadataUpgradeable booster_, uint256 amount_) internal view returns (uint256) {
        uint256 boosterPrice = boosterOracle.getPrice(address(booster_));
        uint256 boosterDecimals = booster_.decimals();
        require(boosterPrice > 0, "DuetProStaking: booster price is zero");
        return uint256(normalizeDecimals(boosterPrice * amount_, boosterDecimals, LIQUIDITY_DECIMALS));
    }

    function forceAddLiquidity(uint256 amount_, IPool.PythData calldata pythData) external payable {
        usdLikeUnderlying.safeTransferFrom(msg.sender, address(this), amount_);
        usdLikeUnderlying.approve(address(pool), amount_);
        pool.addLiquidity{ value: msg.value }(address(usdLikeUnderlying), amount_, pythData);
    }

    function normalizeDecimals(
        uint256 value_,
        uint256 sourceDecimals_,
        uint256 targetDecimals_
    ) public pure returns (uint256) {
        if (targetDecimals_ == sourceDecimals_) {
            return value_;
        }
        if (targetDecimals_ > sourceDecimals_) {
            return value_ * 10 ** (targetDecimals_ - sourceDecimals_);
        }
        return value_ / 10 ** (sourceDecimals_ - targetDecimals_);
    }

    /**
     * @dev Returns the amount of shares that the user has in the pool.
     * @param booster_ The address of the booster token.
     * @param normalizedAmount_ Amount with liquidity decimals.
     */
    function _getBoosterValue(
        IERC20MetadataUpgradeable booster_,
        uint256 normalizedAmount_
    ) internal view returns (uint256 boosterValue) {
        uint256 boosterPrice = boosterOracle.getPrice(address(booster_));
        return
            normalizeDecimals(
                (boosterPrice * normalizedAmount_) / (10 ** LIQUIDITY_DECIMALS),
                PRICE_DECIMALS,
                LIQUIDITY_DECIMALS
            );
    }

    function _touchUser(address user_) internal {
        userInfos[user_].lastActionBlock = blockNumber();
        userInfos[user_].lastActionTime = block.timestamp;
    }

    /**
     * @dev update user boosted share after user's booster stake or unstake and liquidity change to make sure
     *       the user's boosted share is correct.
     * @param user_ The address of the user.
     */
    function _updateUserBoostedShares(address user_) internal {
        UserInfo storage userInfo = userInfos[user_];
        require(lastActionBlock == blockNumber(), "DuetProStaking: update pool first");
        require(userInfo.lastActionBlock == blockNumber(), "DuetProStaking: update user shares first");
        if (userInfo.shares == 0) {
            userInfo.boostedShares = 0;
            return;
        }
        uint256 userNormalShares = userInfo.shares - userInfo.boostedShares;
        (uint256 userNormalLiquidity, uint256 userBoostedLiquidity) = sharesToLiquidity(
            userInfo.shares,
            userInfo.boostedShares
        );
        if (userBoostedLiquidity == userInfo.stakedBoosterValue) {
            return;
        }
        if (userBoostedLiquidity > userInfo.stakedBoosterValue) {
            uint256 exceededBoostedLiquidity = userBoostedLiquidity - userInfo.stakedBoosterValue;
            uint256 exceededBoostedShares = DuetMath.mulDiv(
                userInfo.boostedShares,
                exceededBoostedLiquidity,
                userBoostedLiquidity
            );
            uint256 exchangedNormalShares = DuetMath.mulDiv(
                totalShares - totalBoostedShares,
                exceededBoostedLiquidity,
                lastNormalLiquidity
            );

            userInfo.boostedShares -= exceededBoostedShares;
            totalBoostedShares -= exceededBoostedShares;

            userInfo.shares -= exceededBoostedShares;
            userInfo.shares += exchangedNormalShares;

            totalShares -= exceededBoostedShares;
            totalShares += exchangedNormalShares;

            lastBoostedLiquidity -= exceededBoostedLiquidity;
            lastNormalLiquidity += exceededBoostedLiquidity;

            return;
        }
        if (userNormalLiquidity == 0) {
            return;
        }

        uint256 missingBoostedLiquidity = userInfo.stakedBoosterValue - userBoostedLiquidity;
        missingBoostedLiquidity = missingBoostedLiquidity >= userNormalLiquidity
            ? userNormalLiquidity
            : missingBoostedLiquidity;

        uint256 missingBoostedShares = totalBoostedShares > 0
            ? DuetMath.mulDiv(totalBoostedShares, missingBoostedLiquidity, lastBoostedLiquidity)
            : missingBoostedLiquidity;
        if (missingBoostedShares == 0) {
            return;
        }

        uint256 exchangedNormalShares = userNormalShares > 0 && missingBoostedShares > 0
            ? DuetMath.mulDiv(userNormalShares, missingBoostedLiquidity, userNormalLiquidity)
            : 0;

        userInfo.boostedShares += missingBoostedShares;
        userInfo.shares -= exchangedNormalShares;
        userInfo.shares += missingBoostedShares;

        totalBoostedShares += missingBoostedShares;
        totalShares -= exchangedNormalShares;
        totalShares += missingBoostedShares;

        lastBoostedLiquidity += missingBoostedLiquidity;
        lastNormalLiquidity -= missingBoostedLiquidity;
    }

    function chainId() public view returns (uint256) {
        return block.chainid;
    }

    function blockNumber() public view returns (uint256) {
        // 42170 421611 421613
        if (
            // arbitrum one
            block.chainid == 42161 ||
            // arbitrum xDai
            block.chainid == 200 ||
            // arbitrum nova
            block.chainid == 42170 ||
            // arbitrum rinkeby
            block.chainid == 421611 ||
            // arbitrum Goerli
            block.chainid == 421613
        ) {
            return ArbSys(address(100)).arbBlockNumber();
        }
        return block.number;
    }
}

