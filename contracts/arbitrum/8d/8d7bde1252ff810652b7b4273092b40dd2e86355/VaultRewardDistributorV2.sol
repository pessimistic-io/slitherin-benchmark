// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { IBaseReward } from "./IBaseReward.sol";
import { ICommonReward } from "./ICommonReward.sol";
import { IVaultRewardDistributorV2 } from "./IVaultRewardDistributorV2.sol";
import { ICreditTokenStaker } from "./ICreditTokenStaker.sol";
import { IStorageAddresses } from "./IStorageAddresses.sol";

import "./console.sol";

/* 
The VaultRewardDistributor is used to control the distribution ratio of the supplyRewardPool and borrowedRewardPool in the vault contract. 
When profits are sent to the VaultRewardDistributor's distribute function, 
the contract will also send them to the supplyRewardPool and borrowedRewardPool according to the preset ratio.
*/

contract VaultRewardDistributorV2 is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IVaultRewardDistributorV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    bytes32 public constant SUPPLY_POOL = keccak256(abi.encode("SUPPLY_POOL"));
    bytes32 public constant BORROWED_POOL = keccak256(abi.encode("BORROWED_POOL"));

    uint256 private constant PRECISION = 1000;
    uint256 private constant MAX_RATIO = 1000;
    uint256 private constant INITIAL_RATIO = 500;

    address public rewardPools;
    address public vault;
    uint256 public supplyRewardPoolRatio;
    uint256 public borrowedRewardPoolRatio;

    mapping(address => bool) public stakers;
    mapping(address => bool) public distributors;

    modifier onlyStakers() {
        require(stakers[msg.sender], "VaultRewardDistributor: Caller is not the staker");
        _;
    }

    modifier onlyDistributors() {
        require(distributors[msg.sender], "VaultRewardDistributor: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice used to initialize the contract
    function initialize(address _rewardPools, address _vault) external initializer {
        require(_rewardPools != address(0), "VaultRewardDistributor: _rewardPools cannot be 0x0");
        require(_rewardPools.isContract(), "VaultRewardDistributor: _rewardPools is not a contract");
        require(_vault != address(0), "VaultRewardDistributor: _vault cannot be 0x0");
        require(_vault.isContract(), "VaultRewardDistributor: _vault is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();

        rewardPools = _rewardPools;
        vault = _vault;

        supplyRewardPoolRatio = INITIAL_RATIO;
        borrowedRewardPoolRatio = INITIAL_RATIO;
    }

    /// @notice add staker
    /// @param _staker staker address
    function addStaker(address _staker) public onlyOwner {
        require(_staker != address(0), "VaultRewardDistributor: _staker cannot be 0x0");
        require(!stakers[_staker], "VaultRewardDistributor: _staker is already staker");

        stakers[_staker] = true;

        emit NewStaker(msg.sender, _staker);
    }

    /// @notice remove staker
    /// @param _staker staker address
    function removeStaker(address _staker) external onlyOwner {
        require(_staker != address(0), "VaultRewardDistributor: _staker cannot be 0x0");
        require(stakers[_staker], "VaultRewardDistributor: _staker is not the staker");

        stakers[_staker] = false;

        emit RemoveStaker(msg.sender, _staker);
    }

    /// @notice add distributor
    /// @param _distributor distributor address
    function addDistributor(address _distributor) public onlyOwner {
        require(_distributor != address(0), "VaultRewardDistributor: _distributor cannot be 0x0");
        require(!distributors[_distributor], "VaultRewardDistributor: _distributor is already distributor");

        distributors[_distributor] = true;

        emit NewDistributor(msg.sender, _distributor);
    }

    /// @notice remove distributor
    /// @param _distributor distributor address
    function removeDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "VaultRewardDistributor: _distributor cannot be 0x0");
        require(distributors[_distributor], "VaultRewardDistributor: _distributor is not the distributor");

        distributors[_distributor] = false;

        emit RemoveDistributor(msg.sender, _distributor);
    }

    /// @notice set suppliers reward pool ratio
    /// @param _ratio ratio
    function setSupplyRewardPoolRatio(uint256 _ratio) public onlyOwner {
        require(_ratio <= MAX_RATIO, "VaultRewardDistributor: Maximum limit exceeded");

        supplyRewardPoolRatio = _ratio;
        borrowedRewardPoolRatio = MAX_RATIO - supplyRewardPoolRatio;

        emit SetSupplyRewardPoolRatio(_ratio);
    }

    /// @notice set borrowers reward pool ratio
    /// @param _ratio ratio
    function setBorrowedRewardPoolRatio(uint256 _ratio) public onlyOwner {
        require(_ratio <= MAX_RATIO, "VaultRewardDistributor: Maximum limit exceeded");

        borrowedRewardPoolRatio = _ratio;
        supplyRewardPoolRatio = MAX_RATIO - borrowedRewardPoolRatio;

        emit SetBorrowedRewardPoolRatio(_ratio);
    }

    function _setPool(bytes32 _name, address _stakingToken, address _rewardToken, address _pool) internal {
        require(_stakingToken != address(0), "VaultRewardDistributor: _stakingToken cannot be 0x0");
        require(_rewardToken != address(0), "VaultRewardDistributor: _rewardToken cannot be 0x0");
        require(_pool != address(0), "VaultRewardDistributor: _pool cannot be 0x0");

        IStorageAddresses(rewardPools).setAddress(_generateKey(_name, vault, _stakingToken, _rewardToken), _pool, true);

        emit SetPool(_name, _stakingToken, _rewardToken, _pool);
    }

    /// @notice set supply reward pool
    /// @param _rewardToken reward token
    /// @param _pool reward pool
    function setSupplyPool(address _rewardToken, address _pool) public onlyOwner {
        _setPool(SUPPLY_POOL, vault, _rewardToken, _pool);
    }

    /// @notice set borrowed reward pool
    /// @param _stakingToken staking token
    /// @param _rewardToken reward token
    /// @param _pool reward pool
    function setBorrowedPool(address _stakingToken, address _rewardToken, address _pool) public onlyOwner {
        _setPool(BORROWED_POOL, _stakingToken, _rewardToken, _pool);
    }

    /// @notice deposit credit token
    /// @dev execute by staker only
    /// @param _amountIn token amount
    function stake(uint256 _amountIn) external override onlyStakers {
        require(_amountIn > 0, "VaultRewardDistributor: _amountIn cannot be 0");

        address creditToken = ICreditTokenStaker(msg.sender).creditToken();

        uint256 before = IERC20Upgradeable(creditToken).balanceOf(address(this));
        IERC20Upgradeable(creditToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(creditToken).balanceOf(address(this)) - before;

        emit Stake(_amountIn);
    }

    /// @notice withdraw credit token
    /// @dev execute by staker only
    /// @param _amountOut token amount
    function withdraw(uint256 _amountOut) external override onlyStakers returns (uint256) {
        require(_amountOut > 0, "VaultRewardDistributor: _amountOut cannot be 0");

        address creditToken = ICreditTokenStaker(msg.sender).creditToken();

        IERC20Upgradeable(creditToken).safeTransfer(msg.sender, _amountOut);

        emit Withdraw(_amountOut);

        return _amountOut;
    }

    /// @notice reward distribution
    /// @dev the distribution function will transfer from the caller to rewards
    /// @param _rewards reward amount
    function distribute(uint256 _rewards) external override nonReentrant onlyDistributors {
        require(_rewards > 0, "VaultRewardDistributor: _rewards cannot be 0");

        address stakingToken = ICommonReward(msg.sender).stakingToken();
        address rewardToken = ICommonReward(msg.sender).rewardToken();

        console.log("VaultRewardDistributorV2 vault", vault);
        console.log("VaultRewardDistributorV2 stakingToken", stakingToken);
        console.log("VaultRewardDistributorV2 rewardToken", rewardToken);

        address supplyRewardPool = IStorageAddresses(rewardPools).getAddress(_generateKey(SUPPLY_POOL, vault, vault, rewardToken));
        address borrowedRewardPool = IStorageAddresses(rewardPools).getAddress(_generateKey(BORROWED_POOL, vault, stakingToken, rewardToken));

        console.log("VaultRewardDistributorV2 supplyRewardPool", supplyRewardPool);
        console.log("VaultRewardDistributorV2 borrowedRewardPool", borrowedRewardPool);

        IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
        _rewards = IERC20Upgradeable(rewardToken).balanceOf(address(this));

        uint256 supplyRewards = (_rewards * supplyRewardPoolRatio) / PRECISION;
        uint256 borrowedRewards = (_rewards * borrowedRewardPoolRatio) / PRECISION;

        if (supplyRewards > 0) {
            _approve(rewardToken, supplyRewardPool, supplyRewards);
            IBaseReward(supplyRewardPool).distribute(supplyRewards);
            emit Distribute(supplyRewardPool, _rewards, supplyRewards);
        }

        if (borrowedRewards > 0) {
            _approve(rewardToken, borrowedRewardPool, borrowedRewards);
            IBaseReward(borrowedRewardPool).distribute(borrowedRewards);
            emit Distribute(borrowedRewardPool, _rewards, borrowedRewards);
        }
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("VaultRewardDistributor: Not allowed");
    }

    function _generateKey(bytes32 _name, address _vault, address _stakingToken, address _rewardToken) internal pure returns (bytes32) {
        return keccak256(abi.encode(_name, _vault, _stakingToken, _rewardToken));
    }
}

