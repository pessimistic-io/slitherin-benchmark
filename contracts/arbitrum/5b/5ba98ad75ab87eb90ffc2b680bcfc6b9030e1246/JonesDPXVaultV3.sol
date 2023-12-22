// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20, IERC20Metadata} from "./IERC20Metadata.sol";
import {JonesVaultV3} from "./JonesVaultV3.sol";
import {DopexFarmWrapper} from "./DopexFarmWrapper.sol";
import {IDPXSingleStaking} from "./IDPXSingleStaking.sol";
import {IUniswapV2Router01} from "./IUniswapV2Router01.sol";

contract JonesDPXVaultV3 is JonesVaultV3 {
    using DopexFarmWrapper for IDPXSingleStaking;

    /// Role for the keeper used to call the farm methods
    bytes32 public constant KEEPER = keccak256("KEEPER_ROLE");

    /// The amount of rewards that can be kept in the vault when the management window is closed.
    /// `0` means that all rewards need to be swapped before closing the management window
    uint256 public rewardsTolerance;

    /// The DPX farm
    IDPXSingleStaking internal _farm;
    /// The router to swap rewards
    IUniswapV2Router01 internal _router;
    /// The address of the reward asset that needs to be swapped for the base asset
    address internal _rewardAsset;
    /// The route used for swapping rewards
    address[] internal _rewardSwapRoute;

    constructor(
        address _asset,
        address _share,
        address _governor,
        address _feeDistributor,
        uint256 _vaultCap
    ) JonesVaultV3(_asset, _share, _governor, _feeDistributor, _vaultCap) {
        _farm = IDPXSingleStaking(0xc6D714170fE766691670f12c2b45C1f34405AAb6);
        _router = IUniswapV2Router01(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );
        _rewardAsset = 0x32Eb7902D4134bf98A28b963D26de779AF92A212;

        // Setup swap route
        _rewardSwapRoute = new address[](3);
        _rewardSwapRoute[0] = _rewardAsset;
        _rewardSwapRoute[1] = _router.WETH();
        _rewardSwapRoute[2] = asset;

        // Setup a default value for rewards tolerance
        // 1 `rDPX` is small enough to keep on the vault and not hurt the performance
        // 1 `rDPX` is big enough to discourage users from sending tokens directly to the vault
        // Can be modified by using `updateRewardsTolerance`
        rewardsTolerance = 10**IERC20Metadata(_rewardAsset).decimals();

        // Give allowance to the farm
        IERC20(_asset).approve(address(_farm), type(uint256).max);
        // Give allowance to the router to sell rewards
        IERC20(_rewardAsset).approve(address(_router), type(uint256).max);
        _grantRole(KEEPER, _governor);
    }

    /**
     * @notice Returns the total assets managed by the vault + the ones on the farm
     * @inheritdoc JonesVaultV3
     */
    function totalAssets() public view virtual override returns (uint256) {
        return
            state == State.MANAGED
                ? super.totalAssets()
                : (super.totalAssets() + _farm.balanceOf(address(this)));
    }

    /**
     * @notice Sell all rewards for the base asset
     * @dev Can be called only by `GOVERNOR` and on `State.MANAGED`
     * @param _minOutputAmount the minimum asset amount to receive from the swap
     */
    function sellRewards(uint256 _minOutputAmount)
        public
        virtual
        onlyRole(GOVERNOR)
    {
        _onState(State.MANAGED);
        // If we have rewards
        uint256 rewardsBalance = IERC20(_rewardAsset).balanceOf(address(this));
        if (rewardsBalance > 0) {
            // Swap them for the base asset
            _router.swapExactTokensForTokens(
                rewardsBalance,
                _minOutputAmount,
                _rewardSwapRoute,
                address(this),
                block.timestamp
            );
        }
    }

    function grantKeeperRole(address _to) public onlyRole(GOVERNOR) {
        if (_to == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }
        _grantRole(KEEPER, _to);
    }

    function revokeKeeperRole(address _from) public onlyRole(GOVERNOR) {
        _revokeRole(KEEPER, _from);
    }

    /**
     * @notice Stakes a specific `_amount` of `asset` into the farm
     * @param _amount The amount to stake
     */
    function stake(uint256 _amount) public virtual onlyRole(KEEPER) {
        _farm.stake(_amount);
        emit Stake(msg.sender, _amount);
    }

    /**
     * @notice Stakes the complete amount of `asset` into the farm
     */
    function stakeAll() public virtual onlyRole(KEEPER) {
        stake(IERC20(asset).balanceOf(address(this)));
    }

    /**
     * @notice Unstakes a specific `_amount` of `asset` from the farm
     * @param _amount The amount to unstake
     * @param _claimRewards It will try to claim rewards if `true`
     */
    function unstake(uint256 _amount, bool _claimRewards)
        public
        virtual
        onlyRole(KEEPER)
    {
        _farm.removeSingleStakeAsset(_amount, _claimRewards);
        emit Unstake(msg.sender, _amount, _claimRewards);
    }

    /**
     * @notice Unstakes everything & claim rewards from the farm
     */
    function unstakeAll() public virtual onlyRole(KEEPER) {
        unstake(_farm.balanceOf(address(this)), true);
    }

    /**
     * @notice Used to update the rewards tolerance value
     * @dev Can be called only by `GOVERNOR` role
     * @param _newRewardsTolerance The new rewards tolerance
     */
    function updateRewardsTolerance(uint256 _newRewardsTolerance)
        public
        virtual
        onlyRole(GOVERNOR)
    {
        rewardsTolerance = _newRewardsTolerance;
    }

    /**
     * @inheritdoc JonesVaultV3
     */
    function _beforeCloseManagementWindow() internal virtual override {
        // To help us prevent getting locked if people sends rewards tokens directly to the vault
        if (IERC20(_rewardAsset).balanceOf(address(this)) >= rewardsTolerance) {
            revert VAULT_STILL_HAS_REWARDS();
        }

        super._beforeCloseManagementWindow();
    }

    /**
     * @inheritdoc JonesVaultV3
     */
    function _afterCloseManagementWindow() internal virtual override {
        // Deposit all DPX into the farm again
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        if (currentBalance > 0) {
            _farm.depositAllIfWhitelisted(address(this));
        }
    }

    /**
     * @notice Withdraws from farm before snapshot, claim rewards after snapshot
     * @inheritdoc JonesVaultV3
     */
    function _beforeOpenManagementWindow() internal virtual override {
        // Withdraw from farm
        if (_farm.balanceOf(address(this)) > 0) {
            _farm.removeAll(address(this));
        }

        super._beforeOpenManagementWindow();

        // Claim rewards
        // Internally it checks if the sender has DPX or rDPX rewards
        // Won't fail if rewards are zero
        _farm.getReward(2);
    }

    /**
     * @inheritdoc JonesVaultV3
     */
    function _afterOpenManagementWindow() internal virtual override {}

    /**
     * @inheritdoc JonesVaultV3
     */
    function _afterDeposit(uint256, uint256) internal virtual override {
        // Deposit DPX into farm
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        if (currentBalance > 0) {
            _farm.depositAllIfWhitelisted(address(this));
        }
    }

    /**
     * @inheritdoc JonesVaultV3
     */
    function _beforeWithdraw(uint256 assets, uint256)
        internal
        virtual
        override
    {
        // If not enough DPX on vault withdraw from farm
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        if (assets > currentBalance) {
            uint256 diff = assets - currentBalance;
            _farm.removeSingleStakeAsset(diff, false);
        }
    }

    // Events

    /**
     * @notice Emitted when a `GOVERNOR` stakes into the farm
     * @param _governor The `GOVERNOR` that staked
     * @param _amount The amount that was staked
     */
    event Stake(address indexed _governor, uint256 _amount);
    /**
     * @notice Emitted when a `GOVERNOR` unstakes from the farm
     * @param _governor The `GOVERNOR` that unstaked
     * @param _amount The amount that was unstaked
     * @param _claimRewards Whether the rewards were claimed or not
     */
    event Unstake(
        address indexed _governor,
        uint256 _amount,
        bool _claimRewards
    );

    // Errors

    error VAULT_STILL_HAS_REWARDS();
    error ADDRESS_CANNOT_BE_ZERO_ADDRESS();
}

