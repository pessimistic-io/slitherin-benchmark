// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import { IVoteLockArchi } from "./IVoteLockArchi.sol";

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

    event Stake(uint256 _tokenId, address _recipient, uint256 _totalLiquidity, uint256 _liquidity);
    event Withdraw(uint256 _tokenId, uint256 _totalLiquidity, uint256 _liquidity);
    event Claim(address _recipient, address _token, uint256 _rewards);
    event Collect(uint256 _tokenId, address _recipient, uint256 _amount0, uint256 _amount1);
    event Distribute(uint256 _rewards, uint256 _accRewardPerShare);

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

    function setGlobal(address _token0, address _token1) public onlyOwner {
        require(g.initialized == false, "LiquidityFarmPool: Cannot run this function twice");

        g.token0 = _token0;
        g.token1 = _token1;
        g.liquidity = 0;
        g.initialized = true;
    }

    function _position(uint256 _tokenId) internal view returns (Position memory p) {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(_tokenId);

        p.token0 = token0;
        p.token1 = token1;
        p.liquidity = liquidity;
    }

    function _sortToken(address _token0, address _token1) public pure returns (address, address) {
        if (_token0 < _token1) return (_token0, _token1);

        return (_token1, _token0);
    }

    function stake(uint256 _tokenId) external nonReentrant {
        _distribute();
        _updateReward(msg.sender);

        (address _token0, address _token1) = _sortToken(g.token0, g.token1);

        Position memory p = _position(_tokenId);

        require(p.token0 == _token0, "LiquidityFarmPool: token0 does not match");
        require(p.token1 == _token1, "LiquidityFarmPool: token1 does not match");
        require(p.liquidity > 0, "LiquidityFarmPool: Insufficient liquidity");

        nonfungiblePositionManager.transferFrom(msg.sender, address(this), _tokenId);

        owners[_tokenId] = msg.sender;
        tokenIds[msg.sender].push(_tokenId);

        liquidityOf[_tokenId] = p.liquidity;
        g.liquidity += p.liquidity;

        emit Stake(_tokenId, msg.sender, g.liquidity, p.liquidity);
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

    function _withdraw(uint256 _tokenId) internal {
        uint256 liquidity = liquidityOf[_tokenId];

        delete liquidityOf[_tokenId];
        delete owners[_tokenId];

        _remove(tokenIds[msg.sender], _tokenId);

        g.liquidity -= liquidity;

        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, _tokenId);

        emit Withdraw(_tokenId, g.liquidity, liquidity);
    }

    function withdraw(uint256 _tokenId) external {
        require(owners[_tokenId] == msg.sender, "LiquidityFarmPool: _tokenId does not exist");

        _distribute();
        _updateReward(msg.sender);

        _withdraw(_tokenId);
    }

    function withdrawAll() external {
        _distribute();
        _updateReward(msg.sender);

        uint256[] memory tokens = tokenIds[msg.sender];

        for (uint256 i = 0; i < tokens.length; i++) {
            _withdraw(tokens[i]);
        }
    }

    function pendingRewards(address _recipient) public view returns (uint256[] memory) {
        uint256 totalRewardTokens = _totalRewardTokens();
        uint256[] memory rewards = new uint256[](totalRewardTokens);
        uint256[] memory tokens = tokenIds[msg.sender];

        for (uint256 i = 0; i < totalRewardTokens; i++) {
            address token = _rewardToken(i + 1);
            RewardToken storage rewardToken = rewardTokens[token];

            for (uint256 j = 0; j < tokens.length; j++) {
                rewards[i] =
                    userRewards[_recipient][token] +
                    (((rewardToken.accRewardPerShare - userRewardPerTokenPaid[_recipient][token]) * liquidityOf[tokens[j]]) / PRECISION);
            }
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

    function collect(uint256 _tokenId) external returns (uint256 amount0, uint256 amount1) {
        address recipient = owners[_tokenId];

        require(recipient != address(0), "LiquidityFarmPool: _tokenId does not exist");

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: _tokenId,
            recipient: recipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        if (amount0 > 0) {
            IERC20Upgradeable(g.token0).safeTransfer(recipient, amount0);
        }

        if (amount1 > 0) {
            IERC20Upgradeable(g.token1).safeTransfer(recipient, amount1);
        }

        emit Collect(_tokenId, recipient, amount0, amount1);
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

    function _totalRewardTokens() internal view returns (uint256) {
        return voteLockArchi.totalRewardTokens();
    }

    function _rewardToken(uint256 _index) internal view returns (address) {
        return voteLockArchi.getRewardToken(_index);
    }

    function _distribute() internal {
        uint256[] memory rewards = voteLockArchi.claim();

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

                    emit Distribute(rewards[i], rewardToken.accRewardPerShare);
                }
            }
        }
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
}

