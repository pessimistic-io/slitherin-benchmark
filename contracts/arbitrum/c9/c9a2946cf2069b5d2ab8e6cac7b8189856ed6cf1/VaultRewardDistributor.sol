// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

// import { IAbstractReward } from "./interfaces/IAbstractReward.sol";
import { ICommonReward } from "./ICommonReward.sol";
import { IVaultRewardDistributor } from "./IVaultRewardDistributor.sol";

contract VaultRewardDistributor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IVaultRewardDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1000;
    uint256 private constant MAX_RATIO = 1000;
    uint256 private constant INITIAL_RATIO = 500;

    address public override stakingToken;
    address public override rewardToken;
    address public staker;
    address public distributor;
    address public supplyRewardPool;
    address public borrowedRewardPool;

    uint256 public supplyRewardPoolRatio;
    uint256 public borrowedRewardPoolRatio;

    modifier onlyStaker() {
        require(staker == msg.sender, "VaultRewardDistributor: Caller is not the staker");
        _;
    }

    modifier onlyDistributor() {
        require(distributor == msg.sender, "VaultRewardDistributor: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(
        address _staker,
        address _distributor,
        address _stakingToken,
        address _rewardToken
    ) external initializer {
        require(_staker != address(0), "VaultRewardDistributor: _staker cannot be 0x0");
        require(_distributor != address(0), "VaultRewardDistributor: _distributor cannot be 0x0");
        require(_stakingToken != address(0), "VaultRewardDistributor: _stakingToken cannot be 0x0");
        require(_rewardToken != address(0), "VaultRewardDistributor: _rewardToken cannot be 0x0");

        require(_staker.isContract(), "VaultRewardDistributor: _staker is not a contract");
        require(_stakingToken.isContract(), "VaultRewardDistributor: _stakingToken is not a contract");
        require(_rewardToken.isContract(), "VaultRewardDistributor: _rewardToken is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();

        staker = _staker;
        distributor = _distributor;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;

        supplyRewardPoolRatio = INITIAL_RATIO;
        borrowedRewardPoolRatio = INITIAL_RATIO;
    }

    function setSupplyRewardPoolRatio(uint256 _ratio) public onlyOwner {
        supplyRewardPoolRatio = _ratio;
        borrowedRewardPoolRatio = MAX_RATIO - supplyRewardPoolRatio;

        require((supplyRewardPoolRatio + borrowedRewardPoolRatio) == MAX_RATIO, "VaultRewardDistributor: Maximum limit exceeded");

        emit SetSupplyRewardPoolRatio(_ratio);
    }

    function setBorrowedRewardPoolRatio(uint256 _ratio) public onlyOwner {
        borrowedRewardPoolRatio = _ratio;
        supplyRewardPoolRatio = MAX_RATIO - borrowedRewardPoolRatio;

        require((borrowedRewardPoolRatio + supplyRewardPoolRatio) == MAX_RATIO, "VaultRewardDistributor: Maximum limit exceeded");

        emit SetBorrowedRewardPoolRatio(_ratio);
    }

    function setSupplyRewardPool(address _rewardPool) public onlyOwner {
        require(_rewardPool != address(0), "VaultRewardDistributor: _rewardPool cannot be 0x0");
        require(supplyRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        supplyRewardPool = _rewardPool;

         emit SetSupplyRewardPool(_rewardPool);
    }

    function setBorrowedRewardPool(address _rewardPool) public onlyOwner {
        require(_rewardPool != address(0), "VaultRewardDistributor: _rewardPool cannot be 0x0");
        require(borrowedRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        borrowedRewardPool = _rewardPool;

         emit SetBorrowedRewardPool(_rewardPool);
    }

    function stake(uint256 _amountIn) external override onlyStaker {
        require(_amountIn > 0, "VaultRewardDistributor: _amountIn cannot be 0");

        uint256 before = IERC20Upgradeable(stakingToken).balanceOf(address(this));
        IERC20Upgradeable(stakingToken).safeTransferFrom(staker, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(stakingToken).balanceOf(address(this)) - before;

        emit Stake(_amountIn);
    }

    function withdraw(uint256 _amountOut) external override onlyStaker returns (uint256) {
        require(_amountOut > 0, "VaultRewardDistributor: _amountOut cannot be 0");

        IERC20Upgradeable(stakingToken).safeTransfer(staker, _amountOut);

        emit Withdraw(_amountOut);

        return _amountOut;
    }

    function distribute(uint256 _rewards) external override nonReentrant onlyDistributor {
        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
            _rewards = IERC20Upgradeable(rewardToken).balanceOf(address(this));

            uint256 vaultRewards = (_rewards * supplyRewardPoolRatio) / PRECISION;
            uint256 borrowedRewards = (_rewards * borrowedRewardPoolRatio) / PRECISION;

            if (vaultRewards > 0) {
                _approve(rewardToken, supplyRewardPool, vaultRewards);
                ICommonReward(supplyRewardPool).distribute(vaultRewards);
            }

            if (borrowedRewards > 0) {
                _approve(rewardToken, borrowedRewardPool, borrowedRewards);

                ICommonReward(borrowedRewardPool).distribute(borrowedRewards);
            }

            emit Distribute(_rewards, 0);
        }
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

