// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { IVoteLockArchi } from "./IVoteLockArchi.sol";
import { TickMath } from "./TickMath.sol";
import { FullMath } from "./FullMath.sol";
import { FixedPoint96 } from "./FixedPoint96.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";

contract LiquidityFarmPool is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;

    struct RewardToken {
        uint256 accRewardPerShare;
        uint256 queuedRewards;
    }

    struct Position {
        address token0;
        address token1;
        uint128 liquidity;
    }

    struct Global {
        address token0;
        address token1;
        uint256 liquidity;
        bool initialized;
    }

    Global public g;

    IVoteLockArchi public voteLockArchi;
    INonfungiblePositionManager public nonfungiblePositionManager;

    mapping(uint256 => address) public owners;
    mapping(address => uint256[]) public tokenIds;
    mapping(uint256 => uint256) public liquidityOf;

    mapping(address => RewardToken) public rewardTokens; // reward Token
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid; // user => (rewardToken, rewards)
    mapping(address => mapping(address => uint256)) public userRewards; // user => (rewardToken, rewards)
    mapping(uint256 => uint256) public releaseAt;
    mapping(uint256 => bool) public isBlackListed;

    event Stake(uint256 _tokenId, address _recipient, uint256 _totalLiquidity, uint256 _liquidity);
    event Withdraw(uint256 _tokenId, uint256 _totalLiquidity, uint256 _liquidity, uint256 _releaseAt);
    event Redeem(uint256 _tokenId);
    event Claim(address _recipient, address _token, uint256 _rewards);
    event Collect(uint256 _tokenId, address _recipient, uint256 _amount0, uint256 _amount1);
    event Distribute(uint256 _rewards, uint256 _liquidity, uint256 _accRewardPerShare);
    event RemovedBlackList(uint256 _tokenId);

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _nonfungiblePositionManager, address _voteLockArchi) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        voteLockArchi = IVoteLockArchi(_voteLockArchi);
    }

    function initializeV3() external reinitializer(3) {
        uint256 totalRewardTokens = _totalRewardTokens();

        g.liquidity = 0;

        uint256 totalBalance = INonfungiblePositionManager(nonfungiblePositionManager).balanceOf(address(this));
        (int24 tick, ) = getPoolInfo(_factoryAddress(), _poolKey());

        for (uint256 i = 0; i < totalBalance; i++) {
            uint256 tokenId = INonfungiblePositionManager(nonfungiblePositionManager).tokenOfOwnerByIndex(address(this), i);

            (, int24 tickLower, int24 tickUpper) = positions(tokenId);
            bool isPriceRange = positionIsCrossed(tick, tickLower, tickUpper);
            address user = owners[tokenId];

            for (uint256 j = 0; j < totalRewardTokens; j++) {
                address token = _rewardToken(j + 1);
                userRewards[user][token] = 0;
                userRewardPerTokenPaid[user][token] = 0;
            }

            if (releaseAt[tokenId] == 0) {
                if (isPriceRange) {
                    g.liquidity += liquidityOf[tokenId];
                } else {
                    liquidityOf[tokenId] = 0;
                }
            }
        }

        for (uint256 i = 0; i < totalRewardTokens; i++) {
            address token = _rewardToken(i + 1);
            RewardToken storage rewardToken = rewardTokens[token];
            uint256 rewards = IERC20Upgradeable(token).balanceOf(address(this));

            if (rewards > 0) {
                rewardToken.accRewardPerShare = (rewards * PRECISION) / g.liquidity;

                emit Distribute(rewards, g.liquidity, rewardToken.accRewardPerShare);
            } else {
                rewardToken.accRewardPerShare = 0;
            }
        }

        isBlackListed[676102] = true;
        isBlackListed[676097] = true;
        isBlackListed[672889] = true;
        isBlackListed[673287] = true;
        isBlackListed[673163] = true;
        isBlackListed[679136] = true;
    }

    function _updateLiquidityWorth(int24 _tick, uint256 _tokenId) internal {
        if (releaseAt[_tokenId] == 0) {
            (Position memory p, int24 tickLower, int24 tickUpper) = positions(_tokenId);
            bool isPriceRange = positionIsCrossed(_tick, tickLower, tickUpper);

            if (isPriceRange) {
                (, , uint256 liquidityWorth) = calcLiquidityWorth(tickLower, tickUpper, p.liquidity);
                uint256 oldLiquidity = liquidityOf[_tokenId];

                g.liquidity -= oldLiquidity;
                g.liquidity += liquidityWorth;

                liquidityOf[_tokenId] = liquidityWorth;
            } else {
                g.liquidity -= liquidityOf[_tokenId];
                liquidityOf[_tokenId] = 0;
            }
        }
    }

    function _scanTokenRange() internal {
        uint256 totalBalance = INonfungiblePositionManager(nonfungiblePositionManager).balanceOf(address(this));
        (int24 tick, ) = getPoolInfo(_factoryAddress(), _poolKey());

        for (uint256 i = 0; i < totalBalance; i++) {
            uint256 tokenId = INonfungiblePositionManager(nonfungiblePositionManager).tokenOfOwnerByIndex(address(this), i);
            _updateLiquidityWorth(tick, tokenId);
        }
    }

    function scanTokenRange() public onlyOwner {
        _scanTokenRange();
    }

    function setGlobal(address _token0, address _token1) public onlyOwner {
        require(g.initialized == false, "LiquidityFarmPool: Cannot run this function twice");

        (address token0, address token1) = _sortToken(_token0, _token1);

        g.token0 = token0;
        g.token1 = token1;
        g.liquidity = 0;
        g.initialized = true;
    }

    function tokenIdsLength(address _owner) public view returns (uint256) {
        return tokenIds[_owner].length;
    }

    function positions(uint256 _tokenId) public view returns (Position memory, int24, int24) {
        (, , address token0, address token1, , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(_tokenId);

        Position memory p;

        p.token0 = token0;
        p.token1 = token1;
        p.liquidity = liquidity;

        return (p, tickLower, tickUpper);
    }

    function getPoolInfo(address _factory, uint24 _poolFee) public view returns (int24, uint256) {
        (address _token0, address _token1) = _sortToken(g.token0, g.token1);

        IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(_factory).getPool(_token0, _token1, _poolFee));

        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        // int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        uint256 amount0 = FullMath.mulDiv(pool.liquidity(), FixedPoint96.Q96, sqrtPriceX96);
        uint256 amount1 = FullMath.mulDiv(pool.liquidity(), sqrtPriceX96, FixedPoint96.Q96);
        uint256 price = (amount0 * 10 ** 18) / amount1;

        return (tick, price);
    }

    function calcLiquidityWorth(int24 _tickLower, int24 _tickUpper, uint128 _liquidity) public view returns (uint256, uint256, uint256) {
        (int24 tick, uint256 price) = getPoolInfo(_factoryAddress(), _poolKey());
        bool isPriceRange = positionIsCrossed(tick, _tickLower, _tickUpper);

        require(isPriceRange, "LiquidityFarmPool: Out of range");

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(tick),
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _liquidity
        );

        return (amount0, amount1, amount0 + (amount1 * price) / 1e18);
    }

    function _sortToken(address _token0, address _token1) internal pure returns (address, address) {
        if (_token0 < _token1) return (_token0, _token1);

        return (_token1, _token0);
    }

    function positionIsCrossed(int24 tick, int24 tickLower, int24 tickUpper) public pure returns (bool) {
        return tickLower <= tick && tickUpper > tick;
    }

    function stake(uint256 _tokenId) external nonReentrant {
        _distribute();
        _updateReward(msg.sender);

        (address _token0, address _token1) = _sortToken(g.token0, g.token1);
        (Position memory p, int24 _tickLower, int24 _tickUpper) = positions(_tokenId);

        require(p.token0 == _token0, "LiquidityFarmPool: token0 does not match");
        require(p.token1 == _token1, "LiquidityFarmPool: token1 does not match");
        require(p.liquidity > 0, "LiquidityFarmPool: Insufficient liquidity");

        nonfungiblePositionManager.transferFrom(msg.sender, address(this), _tokenId);

        (, , uint256 liquidityWorth) = calcLiquidityWorth(_tickLower, _tickUpper, p.liquidity);

        owners[_tokenId] = msg.sender;
        tokenIds[msg.sender].push(_tokenId);

        liquidityOf[_tokenId] = liquidityWorth;
        g.liquidity += liquidityWorth;

        emit Stake(_tokenId, msg.sender, g.liquidity, liquidityWorth);
    }

    function _findIndex(uint256[] memory array, uint256 element) internal pure returns (uint256 i) {
        for (i = 0; i < array.length; i++) {
            if (array[i] == element) {
                break;
            }
        }
    }

    function _remove(uint256[] storage array, uint256 element) internal {
        uint256 _index = _findIndex(array, element);
        uint256 _length = array.length;

        if (_index >= _length) return;

        if (_index < _length - 1) {
            array[_index] = array[_length - 1];
        }

        array.pop();
    }

    function withdraw(uint256 _tokenId) external nonReentrant {
        require(owners[_tokenId] == msg.sender, "LiquidityFarmPool: _tokenId does not exist");
        require(releaseAt[_tokenId] == 0, "LiquidityFarmPool: Already processed");

        _distribute();
        _updateReward(msg.sender);
        _collect(_tokenId, msg.sender);

        releaseAt[_tokenId] = block.timestamp + 24 hours;

        uint256 liquidity = liquidityOf[_tokenId];
        delete liquidityOf[_tokenId];
        g.liquidity -= liquidity;

        emit Withdraw(_tokenId, g.liquidity, liquidity, releaseAt[_tokenId]);
    }

    function redeem(uint256 _tokenId) public nonReentrant {
        require(owners[_tokenId] == msg.sender, "LiquidityFarmPool: _tokenId does not exist");
        require(releaseAt[_tokenId] > 0, "LiquidityFarmPool: Please withdraw first");
        require(block.timestamp >= releaseAt[_tokenId], "LiquidityFarmPool: _tokenId is still frozen");
        require(!isBlackListed[_tokenId], "LiquidityFarmPool: Banned");

        _collect(_tokenId, msg.sender);
        _remove(tokenIds[msg.sender], _tokenId);

        delete owners[_tokenId];
        delete releaseAt[_tokenId];

        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, _tokenId);

        emit Redeem(_tokenId);
    }

    function pendingRewards(address _recipient) public view returns (uint256[] memory) {
        uint256 totalRewardTokens = _totalRewardTokens();
        uint256[] memory rewards = new uint256[](totalRewardTokens);

        for (uint256 i = 0; i < totalRewardTokens; i++) {
            address token = _rewardToken(i + 1);
            RewardToken storage rewardToken = rewardTokens[token];

            for (uint256 j = 0; j < tokenIds[_recipient].length; j++) {
                rewards[i] += (((rewardToken.accRewardPerShare - userRewardPerTokenPaid[_recipient][token]) * liquidityOf[tokenIds[_recipient][j]]) /
                    PRECISION);
            }

            rewards[i] += userRewards[_recipient][token];
        }

        return rewards;
    }

    function claim() external nonReentrant returns (uint256[] memory) {
        _distribute();
        _updateReward(msg.sender);

        uint256 totalRewardTokens = _totalRewardTokens();
        uint256[] memory rewards = new uint256[](totalRewardTokens);

        for (uint256 i = 0; i < totalRewardTokens; i++) {
            address token = _rewardToken(i + 1);

            rewards[i] = userRewards[msg.sender][token];

            if (rewards[i] > 0) {
                userRewards[msg.sender][token] = 0;
                IERC20Upgradeable(token).safeTransfer(msg.sender, rewards[i]);

                emit Claim(msg.sender, token, rewards[i]);
            }
        }

        return rewards;
    }

    function _collect(uint256 _tokenId, address _recipient) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: _tokenId,
            recipient: _recipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        emit Collect(_tokenId, _recipient, amount0, amount1);
    }

    function collect(uint256 _tokenId) external returns (uint256 amount0, uint256 amount1) {
        address recipient = owners[_tokenId];
        require(recipient != address(0), "LiquidityFarmPool: _tokenId does not exist");

        return _collect(_tokenId, recipient);
    }

    function _updateReward(address _recipient) internal {
        uint256[] memory rewards = pendingRewards(_recipient);

        for (uint256 i = 0; i < _totalRewardTokens(); i++) {
            address token = _rewardToken(i + 1);
            RewardToken storage rewardToken = rewardTokens[token];

            userRewards[_recipient][token] = rewards[i];
            userRewardPerTokenPaid[_recipient][token] = rewardToken.accRewardPerShare;
        }
    }

    function _distribute() internal {
        uint256[] memory rewards = voteLockArchi.claim();

        _scanTokenRange();

        for (uint256 i = 0; i < _totalRewardTokens(); i++) {
            address token = _rewardToken(i + 1);
            RewardToken storage rewardToken = rewardTokens[token];

            if (rewards[i] > 0) {
                if (g.liquidity == 0) {
                    rewardToken.queuedRewards = rewardToken.queuedRewards + rewards[i];
                } else {
                    rewards[i] = rewards[i] + rewardToken.queuedRewards;
                    rewardToken.accRewardPerShare = rewardToken.accRewardPerShare + (rewards[i] * PRECISION) / g.liquidity;
                    rewardToken.queuedRewards = 0;

                    emit Distribute(rewards[i], g.liquidity, rewardToken.accRewardPerShare);
                }
            }
        }
    }

    function donate(address _token, uint256 _rewards) public onlyOwner {
        RewardToken storage rewardToken = rewardTokens[_token];

        _scanTokenRange();

        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _rewards);

        if (_rewards > 0) {
            if (g.liquidity == 0) {
                rewardToken.queuedRewards = rewardToken.queuedRewards + _rewards;
            } else {
                _rewards = _rewards + rewardToken.queuedRewards;
                rewardToken.accRewardPerShare = rewardToken.accRewardPerShare + (_rewards * PRECISION) / g.liquidity;
                rewardToken.queuedRewards = 0;

                emit Distribute(_rewards, g.liquidity, rewardToken.accRewardPerShare);
            }
        }
    }

    function removeBlackList(uint256 _tokenId) public onlyOwner {
        isBlackListed[_tokenId] = false;
        emit RemovedBlackList(_tokenId);
    }

    function delegateVoting(address _delegatee) external onlyOwner {
        address wrappedToken = voteLockArchi.wrappedToken();
        uint256 stakeAmounts = IERC20Upgradeable(wrappedToken).balanceOf(address(this));

        _approve(wrappedToken, address(voteLockArchi), stakeAmounts);

        voteLockArchi.stake(stakeAmounts, _delegatee);
    }

    function changeDelegator(address _delegatee) external onlyOwner {
        voteLockArchi.delegate(_delegatee);
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _totalRewardTokens() internal view returns (uint256) {
        return voteLockArchi.totalRewardTokens();
    }

    function _rewardToken(uint256 _index) internal view returns (address) {
        return voteLockArchi.getRewardToken(_index);
    }

    function _factoryAddress() internal pure returns (address) {
        return 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    }

    function _poolKey() internal pure returns (uint24) {
        return 3000;
    }
}

