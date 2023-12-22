// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IERC20, IERC20Metadata, ERC20} from "./ERC20.sol";
import {ERC20Permit, IERC20Permit} from "./draft-ERC20Permit.sol";
import {ERC4626} from "./ERC4626.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {SafeERC20} from "./SafeERC20.sol";

/// @title Revenue Distribution Token
/// @author lumenlimitless.eth
/// @notice Allows token rewards to be distributed linearly over a vesting period.
/// @notice Inspired by https://github.com/maple-labs/revenue-distribution-token
contract RevenueDistributionToken is ERC20, ERC20Permit, ERC4626, ReentrancyGuard, Ownable2Step {
    // =============================================================
    //                       LIBRARIES
    // =============================================================

    using SafeERC20 for IERC20;

    // =============================================================
    //                       EVENTS
    // =============================================================

    ///  @dev   Issuance parameters have been updated after a `_mint` or `_burn`.
    ///  @param freeAssets_   Resulting `freeAssets` (y-intercept) value after accounting update.
    ///  @param issuanceRate_ The new issuance rate of `asset` until `vestingPeriodFinish_`.
    event IssuanceParamsUpdated(uint256 freeAssets_, uint256 issuanceRate_);

    ///  @dev   `distributor_` has updated the VestingPool vesting schedule to end at `vestingPeriodFinish_`.
    ///  @param distributor_   The distributor who initiated the vesting schedule update.
    ///  @param vestingPeriodFinish_ When the unvested balance will finish vesting.
    event VestingScheduleUpdated(address indexed distributor_, uint256 vestingPeriodFinish_);

    // =============================================================
    //                       ERRORS
    // =============================================================

    error NotRewardDistributor();
    error ZeroReceiver();
    error ZeroShares();
    error ZeroAssets();
    error ZeroSupply();
    error InsufficientPermit();

    // =============================================================
    //                       IMMUTABLES
    // =============================================================

    /// @dev Precision of rates, equals max deposit amounts before rounding errors occur
    uint256 private immutable precision;

    // =============================================================
    //                       STORAGE
    // =============================================================

    /// @notice Amount of assets unlocked regardless of time passed.
    uint256 public freeAssets;

    /// @notice asset/second rate dependent on aggregate vesting schedule.
    uint256 public issuanceRate;

    /// @notice Timestamp of when issuance equation was last updated.
    uint256 public lastUpdated;

    ///@notice Timestamp when current vesting schedule ends.
    uint256 public vestingPeriodFinish;

    ///@notice Tracks if an address can call updateVestingSchedule()
    mapping(address => bool) public distributor;

    // =============================================================
    //                       CONSTRUCTOR
    // =============================================================

    constructor(address initialOwner, IERC20 asset_, uint256 precision_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        ERC4626(asset_)
    {
        require(initialOwner != address(0));
        require(address(asset_) != address(0));

        _transferOwnership(initialOwner);

        precision = precision_;
    }

    // =============================================================
    //                       ADMIN FUNCTIONS
    // =============================================================

    ///  @notice Allow the owner to add or remove distributor accounts.
    ///  @param  account The address of the distributor.
    ///  @param  allowed Whether or not the owner is a distributor.
    function setDistributor(address account, bool allowed) external payable onlyOwner {
        distributor[account] = allowed;
    }

    ///  @notice    Updates the current vesting formula based on the amount of total unvested funds in the contract and the new `vestingPeriod_`.
    ///  @param  vestingPeriod The amount of time over which all currently unaccounted underlying assets will be vested over.
    ///  @return issuanceRate_  The new issuance rate.
    ///  @return freeAssets_    The new amount of underlying assets that are unlocked.
    function updateVestingSchedule(uint256 vestingPeriod)
        external
        payable
        returns (uint256 issuanceRate_, uint256 freeAssets_)
    {
        if (!distributor[msg.sender]) revert NotRewardDistributor();
        if (totalSupply() == uint256(0)) revert ZeroSupply();

        // Update "y-intercept" to reflect current available asset.
        freeAssets_ = freeAssets = totalAssets();

        // Calculate slope.
        issuanceRate_ =
            issuanceRate = ((IERC20(asset()).balanceOf(address(this)) - freeAssets_) * precision) / vestingPeriod;

        // Update timestamp and period finish.
        vestingPeriodFinish = (lastUpdated = block.timestamp) + vestingPeriod;

        emit IssuanceParamsUpdated(freeAssets_, issuanceRate_);
        emit VestingScheduleUpdated(msg.sender, vestingPeriodFinish);
    }

    // =============================================================
    //                       USER FUNCTIONS
    // =============================================================

    /// @notice This function allows a user to deposit assets using a permit signature instead of an approval.
    /// @param assets The number of assets to deposit.
    /// @param receiver The address to receive the shares.
    /// @param deadline The deadline for the permit signature.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function depositWithPermit(uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        virtual
        nonReentrant
        returns (uint256)
    {
        SafeERC20.safePermit((IERC20Permit(asset())), msg.sender, address(this), assets, deadline, v, r, s);
        return super.deposit(assets, receiver);
    }

    /// @notice This function allows a user to mint shares using a permit signature instead of an approval.
    /// @param shares The number of shares to mint.
    /// @param receiver The address to receive the shares.
    /// @param maxAssets The maximum number of assets that can be used to mint the shares.
    /// @param deadline The deadline for the permit signature.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    function mintWithPermit(
        uint256 shares,
        address receiver,
        uint256 maxAssets,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual nonReentrant returns (uint256) {
        if (previewMint(shares) > maxAssets) revert InsufficientPermit();

        SafeERC20.safePermit(IERC20Permit(asset()), msg.sender, address(this), maxAssets, deadline, v, r, s);
        return super.mint(shares, receiver);
    }

    /// @notice see {IERC4626-deposit}
    function deposit(uint256 assets, address receiver) public virtual override nonReentrant returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice see {IERC4626-mint}
    function mint(uint256 shares, address receiver) public virtual override nonReentrant returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @notice see {IERC4626-withdraw}
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice see {IERC4626-redeem}
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    ///  @notice    Returns the amount of underlying assets managed by the vault.
    /// @return assets  Amount of assets managed.
    function totalAssets() public view override returns (uint256) {
        uint256 issuanceRate_ = issuanceRate;

        if (issuanceRate_ == 0) return freeAssets;

        uint256 vestingPeriodFinish_ = vestingPeriodFinish;
        uint256 lastUpdated_ = lastUpdated;

        uint256 vestingTimePassed = block.timestamp > vestingPeriodFinish_
            ? vestingPeriodFinish_ - lastUpdated_
            : block.timestamp - lastUpdated_;

        return ((issuanceRate_ * vestingTimePassed) / precision) + freeAssets;
    }

    ///  @notice    Returns the amount of underlying assets owned by the specified account.
    ///  @param  account Address of the account.
    ///  @return assets  Amount of assets owned.
    function balanceOfAssets(address account) public view returns (uint256) {
        return convertToAssets(balanceOf(account));
    }

    /// @notice see {IERC20Metadata-decimals}
    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }
    // =============================================================
    //                       INTERNAL FUNCTIONS
    // =============================================================

    /// @dev Deposit/mint common workflow.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        if (receiver == address(0)) revert ZeroReceiver();
        if (shares == uint256(0)) revert ZeroShares();
        if (assets == uint256(0)) revert ZeroAssets();

        _mint(receiver, shares);

        uint256 freeAssetsCache = freeAssets = totalAssets() + assets;

        uint256 issuanceRate_ = _updateIssuanceParams();

        emit Deposit(caller, receiver, assets, shares);
        emit IssuanceParamsUpdated(freeAssetsCache, issuanceRate_);

        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
    }

    /// @dev Withdraw/redeem common workflow.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        if (receiver == address(0)) revert ZeroReceiver();
        if (shares == uint256(0)) revert ZeroShares();
        if (assets == uint256(0)) revert ZeroAssets();

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        uint256 freeAssetsCache = freeAssets = totalAssets() - assets;

        uint256 issuanceRate_ = _updateIssuanceParams();

        emit Withdraw(caller, receiver, owner, assets, shares);
        emit IssuanceParamsUpdated(freeAssetsCache, issuanceRate_);

        IERC20(asset()).safeTransfer(receiver, assets);
    }

    /// @dev updates the issuance rate and returns the new value
    function _updateIssuanceParams() private returns (uint256) {
        return issuanceRate = (lastUpdated = block.timestamp) > vestingPeriodFinish ? 0 : issuanceRate;
    }
}

