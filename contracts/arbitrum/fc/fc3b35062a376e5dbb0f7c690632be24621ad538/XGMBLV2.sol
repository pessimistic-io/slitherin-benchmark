// SPDX-License-Identifier: BUSL1.1
pragma solidity ^0.8.0;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC20} from "./ERC20.sol";
import {GMBL} from "./GMBL.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Kernel, Module, Keycode} from "./Kernel.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

import "./IxGMBLToken.sol";
import "./IxGMBLTokenUsage.sol";

import {Address} from "./Address.sol";

/*
 * xGMBL is escrowed governance token obtainable by converting GMBL to it
 * It's non-transferable, except from/to whitelisted addresses
 * It can be converted back to GMBL through a vesting process
 * This contract is made to receive xGMBL deposits from users in order to allocate them to rewards contracts
 */
contract XGMBLV2 is
    ReentrancyGuard,
    ERC20("GMBL escrowed token", "xGMBL", 18),
    Module,
    IxGMBLToken
{
    using Address for address;
    using SafeTransferLib for ERC20;
    using SafeTransferLib for GMBL;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct xGMBLBalance {
        uint256 allocatedAmount; // Amount of xGMBL allocated to a Usage
        uint256 redeemingAmount; // Total amount of xGMBL currently being redeemed
    }

    mapping(address => xGMBLBalance) public xGMBLBalances;

    // A redeem entry appended for a user
    struct RedeemInfo {
        uint256 GMBLAmount; // GMBL amount to receive when vesting has ended
        uint256 xGMBLAmount; // xGMBL amount to redeem
        uint256 endTime;
        IxGMBLTokenUsage RewardsAddress;
        uint256 RewardsAllocation; // Share of redeeming xGMBL to allocate to the Rewards Usage contract
    }

    mapping(address => RedeemInfo[]) public userRedeems; // User's redeeming instances

    uint256 public constant MAX_FIXED_RATIO = 100; // 100%

    GMBL public immutable GMBLToken; // GMBL token to convert to/from
    IxGMBLTokenUsage public RewardsAddress; // Rewards contract
    mapping(address => uint256) public rewardsAllocations; // Active xGMBL allocations to Rewards

    EnumerableSet.AddressSet private _transferWhitelist; // addresses allowed to send/receive xGMBL

    // Redeeming min/max settings
    uint256 public minRedeemRatio = 50; // 1:0.5
    uint256 public maxRedeemRatio = 100; // 1:1
    uint256 public minRedeemDuration = 0 days; // 0s - instant redeem with burn discount
    uint256 public maxRedeemDuration = 180 days; // 7776000s - full redeem with no burn

    // Adjusted rewards for redeeming xGMBL
    uint256 public redeemRewardsAdjustment = 20; // 20%

    constructor(GMBL GMBLToken_, Kernel kernel_) Module(kernel_) {
        GMBLToken = GMBLToken_;
        _transferWhitelist.add(address(this));
    }

    /********************************************/
    /****************** ERRORS ******************/
    /********************************************/

    error XGMBL_Convert_NullAmount();
    error XGMBL_ConvertTo_SenderIsEOA();
    error XGMBL_ConvertTo_BadSender();
    error XGMBL_Allocate_NullAmount();
    error XGMBL_Redeem_AmountIsZero();
    error XGMBL_Redeem_DurationBelowMinimum();
    error XGMBL_FinalizeReedem_VestingNotOver();
    error XGMBL_ValidateRedeem_NullEntry();
    error XGMBL_Deallocate_NullAmount();
    error XGMBL_Deallocate_UnauthorizedAmount();
    error XGMBL_AllocateFromUsage_BadUsageAddress();
    error XGMBL_DeallocateFromUsage_BadUsageAddress();
    error XGMBL_UpdateRedeemSettings_BadRatio();
    error XGMBL_UpdateRedeemSettings_BadDuration();
    error XMGBL_UpdateTransferWhitelist_CannotRemoveSelf();
    error XGMBL_Transfer_NotPermitted();

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Convert(address indexed from, address to, uint256 amount);

    event UpdateRedeemSettings(
        uint256 minRedeemRatio,
        uint256 maxRedeemRatio,
        uint256 minRedeemDuration,
        uint256 maxRedeemDuration,
        uint256 redeemRewardsAdjustment
    );

    event UpdateRewardsAddress(
        address previousRewardsAddress,
        address newRewardsAddress
    );

    event SetTransferWhitelist(address account, bool add);

    event Redeem(
        address indexed account,
        uint256 xGMBLAmount,
        uint256 GMBLAmount,
        uint256 duration
    );

    event FinalizeRedeem(
        address indexed account,
        uint256 xGMBLAmount,
        uint256 GMBLAmount
    );

    event CancelRedeem(address indexed account, uint256 xGMBLAmount);

    event UpdateRedeemRewardsAddress(
        address indexed account,
        uint256 redeemIndex,
        address previousRewardsAddress,
        address newRewardsAddress
    );

    event Allocate(
        address indexed account,
        address indexed rewardsAddress,
        uint256 amount
    );

    event Deallocate(
        address indexed account,
        address indexed rewardsAddress,
        uint256 amount
    );

    event DeallocateAndLock(
        address indexed account,
        address indexed rewardsAddress,
        uint256 amount
    );

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /// @dev Check if a redeem entry exists
    modifier validateRedeem(address account, uint256 redeemIndex) {
        if (redeemIndex >= userRedeems[account].length)
            revert XGMBL_ValidateRedeem_NullEntry();
        _;
    }

    /// @dev Hook override to forbid transfers except from whitelisted addresses and minting
    modifier transferWhitelisted(address from, address to) {
        if (
            from != address(0) &&
            !_transferWhitelist.contains(from) &&
            !_transferWhitelist.contains(to)
        ) revert XGMBL_Transfer_NotPermitted();
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return Keycode.wrap("XGBLB");
    }

    function getGMBL() external view returns (address) {
        return address(GMBLToken);
    }

    /**
     * @notice returns `account`'s `allocatedAmount` and `redeemingAmount` amount
     * @return allocatedAmount Total amount of xGMBL currently allocated to usage address(s) for user
     * @return redeemingAmount Total amount of xGMBL being redeemed for user
     */
    function getxGMBLBalance(
        address account
    ) external view returns (uint256 allocatedAmount, uint256 redeemingAmount) {
        xGMBLBalance storage balance = xGMBLBalances[account];
        return (balance.allocatedAmount, balance.redeemingAmount);
    }

    /// @notice returns redeemable GMBL for `amount` of xGMBL vested for `duration` seconds
    function getGMBLByVestingDuration(
        uint256 amount,
        uint256 duration
    ) public view returns (uint256) {
        // Invalid redeem duration
        if (duration < minRedeemDuration) {
            return 0;
        }

        // Min redeem duration burns (100 - minRedeemRatio)% (default 50%) of gmbl
        if (duration == minRedeemDuration) {
            return (amount * minRedeemRatio) / 100;
        }

        // Max redeem duration burns (100 - maxRedeemRatio)% (default 0%) of gmbl
        if (duration >= maxRedeemDuration) {
            return (amount * maxRedeemRatio) / 100;
        }

        // Min redeem % + reamining % up to max redeem linearly
        uint256 ratio = minRedeemRatio +
            (((duration - minRedeemDuration) *
                (maxRedeemRatio - minRedeemRatio)) /
                (maxRedeemDuration - minRedeemDuration));

        return (amount * ratio) / 100;
    }

    /// @notice returns quantity of `account`'s pending redeems
    function getUserRedeemsLength(
        address account
    ) external view returns (uint256) {
        return userRedeems[account].length;
    }

    /// @notice returns rewards `allocation` of `account`
    function usageAllocations(
        address account
    ) external view returns (uint256 allocation) {
        return rewardsAllocations[account];
    }

    /// @notice returns `account` info for a pending redeem identified by `redeemIndex`
    function getUserRedeem(
        address account,
        uint256 redeemIndex
    )
        external
        view
        validateRedeem(account, redeemIndex)
        returns (
            uint256 GMBLAmount,
            uint256 xGMBLAmount,
            uint256 endTime,
            address RewardsContract,
            uint256 RewardsAllocation
        )
    {
        RedeemInfo storage _redeem = userRedeems[account][redeemIndex];
        return (
            _redeem.GMBLAmount,
            _redeem.xGMBLAmount,
            _redeem.endTime,
            address(_redeem.RewardsAddress),
            _redeem.RewardsAllocation
        );
    }


    /// @notice returns allocated xGMBL from `account` to Rewards
    function getRewardsAllocation(
        address account
    ) external view returns (uint256) {
        return rewardsAllocations[account];
    }

    /// @notice returns length of transferWhitelist array
    function transferWhitelistLength() external view returns (uint256) {
        return _transferWhitelist.length();
    }

    /// @notice returns transferWhitelist array item's address for `index`
    function transferWhitelist(uint256 index) external view returns (address) {
        return _transferWhitelist.at(index);
    }

    /// @dev returns if `account` is allowed to send/receive xGMBL
    function isTransferWhitelisted(
        address account
    ) external view override returns (bool) {
        return _transferWhitelist.contains(account);
    }

    /*****************************************************************/
    /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    /*****************************************************************/

    /// @notice Transfers `amount` of xGMBL from msg.sender to `to`
    /// @dev Override ERC20 transfer. Cannot externally transfer staked tokens unless whitelisted
    function transfer(
        address to,
        uint256 amount
    ) public override transferWhitelisted(msg.sender, to) returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfers `amount` of xGMBL from `from` to `to`
    /// @dev Override ERC20 transferFrom. Cannot externally transfer staked tokens unless whitelisted
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override transferWhitelisted(from, to) returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// @notice Convert's `account`'s `amount` of GMBL to xGMBL
    /// @dev policy dictates boosted amount for potential stake boost
    function convert(
        uint256 amount,
        uint256 boostedAmount,
        address account
    ) external nonReentrant permissioned {
        _convert(amount, boostedAmount, account);
    }

    /// @notice Convert caller's `amount` of GMBL to xGMBL to `to` address
    function convertTo(
        uint256 amount,
        address to
    ) external override nonReentrant {
        if(msg.sender != address(RewardsAddress))
            revert XGMBL_ConvertTo_BadSender();

        if (!address(msg.sender).isContract())
            revert XGMBL_ConvertTo_SenderIsEOA();

        _convert(amount, amount, to);
    }

    /**
     * @notice Initiates redeem process (xGMBL to GMBL) of `xGMBLAmount` over `duration` period
     * @param xGMBLAmount Amount of xGMBL to redeem (from either sender's balance, their rewards allocation, or a mix)
     * @param duration Time to redeem for...
     *    - minimum redeem duration instantly unlcoks gmbl at the min redeem ratio (default 50%)
     *    - see getGMBLByVestingDuration() for more details
     */
    function redeem(
        address account,
        uint256 xGMBLAmount,
        uint256 duration
    ) external nonReentrant permissioned {
        if (xGMBLAmount == 0) revert XGMBL_Redeem_AmountIsZero();
        if (duration < minRedeemDuration)
            revert XGMBL_Redeem_DurationBelowMinimum();

        // get corresponding GMBL amount
        uint256 GMBLAmount = getGMBLByVestingDuration(xGMBLAmount, duration);
        emit Redeem(account, xGMBLAmount, GMBLAmount, duration);

        // handle Rewards during the vesting process
        uint256 CurrentRewardsAllocation = rewardsAllocations[account];

        if (xGMBLAmount > balanceOf[account] + CurrentRewardsAllocation)
            revert("bad xgmbl amount");

        // Staked balance may be larger than allocated balance
        uint256 RewardsRedeemAmount = xGMBLAmount > CurrentRewardsAllocation
            ? CurrentRewardsAllocation
            : xGMBLAmount;

        xGMBLBalance storage balance = xGMBLBalances[account];

        // if redeeming is not immediate, go through vesting process
        if (duration > 0) {
            // add to SBT total
            balance.redeemingAmount += xGMBLAmount;

            // Rewards discount (deallocation) of redeem amount. max 100% (0 deallocation during redemption), default 20%
            uint256 NewRewardsAllocation = (RewardsRedeemAmount *
                redeemRewardsAdjustment) / 100;

            _deallocateAndLock(
                account,
                RewardsRedeemAmount - NewRewardsAllocation,
                balance
            );

            // lock up
            if (xGMBLAmount > RewardsRedeemAmount) {
                _transferFromSelf(
                    account,
                    address(this),
                    xGMBLAmount - RewardsRedeemAmount
                );
            }

            // add redeeming entry
            userRedeems[account].push(
                RedeemInfo({
                    GMBLAmount: GMBLAmount,
                    xGMBLAmount: xGMBLAmount,
                    endTime: _currentBlockTimestamp() + duration,
                    RewardsAddress: RewardsAddress,
                    RewardsAllocation: NewRewardsAllocation
                })
            );
        }
        // immediately redeem for GMBL
        else {
            // deallocate all rewards <= xGBML redeem amount
            _deallocateAndLock(account, RewardsRedeemAmount, balance);
            // lock up any free xGMBL (xGMBLAmount <= acount's xGMBL)
            _transferFromSelf(
                account,
                address(this),
                xGMBLAmount - RewardsRedeemAmount
            );

            _finalizeRedeem(account, xGMBLAmount, GMBLAmount);
        }
    }

    /// @notice Finalizes redeem process when vesting duration has been reached of `redeemIndex`'s redeem entry
    function finalizeRedeem(
        address account,
        uint256 redeemIndex
    ) external nonReentrant permissioned validateRedeem(account, redeemIndex) {
        xGMBLBalance storage balance = xGMBLBalances[account];
        RedeemInfo storage _redeem = userRedeems[account][redeemIndex];

        if (_currentBlockTimestamp() < _redeem.endTime)
            revert XGMBL_FinalizeReedem_VestingNotOver();

        // remove from SBT total
        balance.redeemingAmount -= _redeem.xGMBLAmount;
        _finalizeRedeem(account, _redeem.xGMBLAmount, _redeem.GMBLAmount);

        // handle Rewards compensation if any was active
        if (_redeem.RewardsAllocation > 0) {
            // deallocate from Rewards
            IxGMBLTokenUsage(_redeem.RewardsAddress).deallocate(
                account,
                _redeem.RewardsAllocation,
                new bytes(0)
            );

            // update internal accounting of deallocation
            balance.allocatedAmount -= _redeem.RewardsAllocation;
            rewardsAllocations[account] -= _redeem.RewardsAllocation;
        }

        // remove redeem entry
        _deleteRedeemEntry(account, redeemIndex);
    }

    /**
     * @notice Updates Rewards address for an existing active redeeming process
     *
     * @dev Can only be called by the involved user
     * Should only be used if Rewards contract was to be migrated
     */
    function updateRedeemRewardsAddress(
        address account,
        uint256 redeemIndex
    ) external nonReentrant permissioned validateRedeem(account, redeemIndex) {
        RedeemInfo storage _redeem = userRedeems[account][redeemIndex];

        // only if the active Rewards contract is not the same anymore
        if (
            RewardsAddress != _redeem.RewardsAddress &&
            address(RewardsAddress) != address(0)
        ) {
            if (_redeem.RewardsAllocation > 0) {
                // deallocate from old Rewards contract
                _redeem.RewardsAddress.deallocate(
                    account,
                    _redeem.RewardsAllocation,
                    new bytes(0)
                );

                // allocate to new used Rewards contract
                RewardsAddress.allocate(
                    account,
                    _redeem.RewardsAllocation,
                    new bytes(0)
                );
            }

            emit UpdateRedeemRewardsAddress(
                account,
                redeemIndex,
                address(_redeem.RewardsAddress),
                address(RewardsAddress)
            );

            _redeem.RewardsAddress = RewardsAddress;
        }
    }

    /// @notice Cancels an ongoing redeem entry at `redeemIndex`
    /// @dev Can only be called by its owner
    function cancelRedeem(
        address account,
        uint256 redeemIndex
    ) external nonReentrant permissioned validateRedeem(account, redeemIndex) {
        xGMBLBalance storage balance = xGMBLBalances[account];
        RedeemInfo storage _redeem = userRedeems[account][redeemIndex];

        // make redeeming xGMBL available again
        balance.redeemingAmount -= _redeem.xGMBLAmount;
        _transferFromSelf(address(this), account, _redeem.xGMBLAmount);

        // handle Rewards compensation if any was active
        if (_redeem.RewardsAllocation > 0) {
            // deallocate from Rewards
            IxGMBLTokenUsage(_redeem.RewardsAddress).deallocate(
                account,
                _redeem.RewardsAllocation,
                new bytes(0)
            );

            // update internal accounting of deallocate
            balance.allocatedAmount -= _redeem.RewardsAllocation;
            rewardsAllocations[account] -= _redeem.RewardsAllocation;
        }

        emit CancelRedeem(account, _redeem.xGMBLAmount);

        // remove redeem entry
        _deleteRedeemEntry(account, redeemIndex);
    }

    /// @notice Allocates caller's `amount` of available xGMBL to `usageAddress` contract
    /// @dev args specific to usage contract must be passed into "usageData"
    function allocate(
        address account,
        uint256 amount,
        bytes calldata usageData
    ) external nonReentrant permissioned {
        _allocate(account, amount);

        // allocates xGMBL to usageContract
        RewardsAddress.allocate(account, amount, usageData);
    }

    /// @notice Allocates `amount` of available xGMBL from `account` to caller (ie usage contract)
    /// @dev Caller must have an allocation approval for the required xGMBL xGMBL from `account`
    function allocateFromUsage(
        address account,
        uint256 amount
    ) external override nonReentrant {
        if (msg.sender != address(RewardsAddress))
            revert XGMBL_AllocateFromUsage_BadUsageAddress();

        _allocate(account, amount);

        // allocates xGMBL to usageContract
        RewardsAddress.allocate(account, amount, hex'00');
    }

    /// @notice Deallocates caller's `amount` of available xGMBL from rewards usage contract
    /// @dev args specific to usage contract must be passed into "usageData"
    function deallocate(
        address account,
        uint256 amount,
        bytes calldata usageData
    ) external nonReentrant permissioned {
        _deallocate(account, amount);

        // deallocate xGMBL into usageContract
        RewardsAddress.deallocate(account, amount, usageData);
    }

    /// @notice Deallocates `amount` of allocated xGMBL belonging to `account` from caller (ie usage contract)
    /// @dev Caller can only deallocate xGMBL from itself
    function deallocateFromUsage(
        address account,
        uint256 amount
    ) external override nonReentrant {
        if(msg.sender != address(RewardsAddress))
            revert XGMBL_DeallocateFromUsage_BadUsageAddress();

        _deallocate(account, amount);
    }

    /// @notice Burns `account`'s `amount` of xGMBL with the option of burning the underlying gmbl as well
    function burn(address account, uint256 amount) external permissioned {
        _burn(account, amount);
        GMBLToken.burn(amount);
    }

    /*******************************************************/
    /****************** OWNABLE FUNCTIONS ******************/
    /*******************************************************/

    /// @notice Updates all redeem ratios and durations
    /// @dev Must only be called by owner
    function updateRedeemSettings(
        uint256 minRedeemRatio_,
        uint256 maxRedeemRatio_,
        uint256 minRedeemDuration_,
        uint256 maxRedeemDuration_,
        uint256 redeemRewardsAdjustment_
    ) external permissioned {
        if (minRedeemRatio_ > maxRedeemRatio_)
            revert XGMBL_UpdateRedeemSettings_BadRatio();
        if (minRedeemDuration_ >= maxRedeemDuration_)
            revert XGMBL_UpdateRedeemSettings_BadDuration();
        // should never exceed 100%
        if (
            maxRedeemRatio_ > MAX_FIXED_RATIO ||
            redeemRewardsAdjustment_ > MAX_FIXED_RATIO
        ) revert XGMBL_UpdateRedeemSettings_BadRatio();

        minRedeemRatio = minRedeemRatio_;
        maxRedeemRatio = maxRedeemRatio_;
        minRedeemDuration = minRedeemDuration_;
        maxRedeemDuration = maxRedeemDuration_;
        redeemRewardsAdjustment = redeemRewardsAdjustment_;

        emit UpdateRedeemSettings(
            minRedeemRatio_,
            maxRedeemRatio_,
            minRedeemDuration_,
            maxRedeemDuration_,
            redeemRewardsAdjustment_
        );
    }

    /// @notice Updates Rewards contract address
    /// @dev Must only be called by owner
    function updateRewardsAddress(
        IxGMBLTokenUsage RewardsAddress_
    ) external permissioned {
        // if set to 0, also set divs earnings while redeeming to 0
        if (address(RewardsAddress_) == address(0)) {
            redeemRewardsAdjustment = 0;
        }

        emit UpdateRewardsAddress(
            address(RewardsAddress),
            address(RewardsAddress_)
        );
        RewardsAddress = RewardsAddress_;
    }

    /// @notice Adds or removes `account` from the transferWhitelist
    function updateTransferWhitelist(
        address account,
        bool add
    ) external permissioned {
        if (account == address(this) && !add)
            revert XMGBL_UpdateTransferWhitelist_CannotRemoveSelf();

        if (add) _transferWhitelist.add(account);
        else _transferWhitelist.remove(account);

        emit SetTransferWhitelist(account, add);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    ///  @dev Convert caller's `amount` of GMBL into xGMBL to `to`
    function _convert(
        uint256 amount,
        uint256 boostedAmount,
        address from
    ) internal {
        if (amount == 0) revert XGMBL_Convert_NullAmount();

        // mint new xGMBL
        _mint(from, boostedAmount);

        emit Convert(from, address(this), amount);
        GMBLToken.safeTransferFrom(from, address(this), amount);
    }

    /**
     * @dev Finalizes the redeeming process for `account` by transferring them `GMBLAmount` and removing `xGMBLAmount` from supply
     *
     * Any vesting check should be ran before calling this
     * GMBL excess is automatically burnt
     */
    function _finalizeRedeem(
        address account,
        uint256 xGMBLAmount,
        uint256 GMBLAmount
    ) internal {
        uint256 GMBLExcess = xGMBLAmount - GMBLAmount;

        // sends due GMBL tokens
        GMBLToken.safeTransfer(account, GMBLAmount);

        // burns GMBL excess if any
        GMBLToken.burn(GMBLExcess);

        // burns redeem-locked XGMBL
        _burn(address(this), xGMBLAmount);

        emit FinalizeRedeem(account, xGMBLAmount, GMBLAmount);
    }

    /// @dev Allocates `account` user's `amount` of available xGMBL to `usageAddress` contract
    function _allocate(address account, uint256 amount) internal {
        if (amount == 0) revert XGMBL_Allocate_NullAmount();

        xGMBLBalance storage balance = xGMBLBalances[account];

        // update rewards allocatedAmount for account
        rewardsAllocations[account] += amount;

        // adjust user's xGMBL balances
        balance.allocatedAmount += amount;
        _transferFromSelf(account, address(this), amount);

        emit Allocate(account, address(RewardsAddress), amount);
    }

    /// @dev Deallocates `amount` of available xGMBL of `account`'s xGMBL from rewards contracts
    function _deallocate(address account, uint256 amount) internal {
        if (amount == 0) revert XGMBL_Deallocate_NullAmount();

        // check if there is enough allocated xGMBL to Rewards to deallocate
        uint256 allocatedAmount = rewardsAllocations[account];

        if (amount > allocatedAmount)
            revert XGMBL_Deallocate_UnauthorizedAmount();

        uint256 redeemsAllocations;
        RedeemInfo[] memory redeemEntries = userRedeems[account];
        for(uint256 i = 0; i < redeemEntries.length; ++i) {
            redeemsAllocations += redeemEntries[i].RewardsAllocation;
        }

        if(redeemsAllocations > allocatedAmount - amount)
            revert XGMBL_Deallocate_UnauthorizedAmount();

        // remove deallocated amount from Reward's allocation
        rewardsAllocations[account] = allocatedAmount - amount;

        // adjust user's xGMBL balances
        xGMBLBalance storage balance = xGMBLBalances[account];
        balance.allocatedAmount -= amount;
        _transferFromSelf(address(this), account, amount);

        emit Deallocate(account, address(RewardsAddress), amount);
    }

    /// @dev Deallocates excess from usage to be called during the redeem process
    function _deallocateAndLock(
        address account,
        uint256 rewardsRedeemAmount,
        xGMBLBalance storage balance
    ) internal {
        balance.allocatedAmount -= rewardsRedeemAmount;
        rewardsAllocations[account] -= rewardsRedeemAmount;

        RewardsAddress.deallocate(
            account,
            rewardsRedeemAmount,
            new bytes(0)
        );

        emit DeallocateAndLock(
            account,
            address(RewardsAddress),
            rewardsRedeemAmount
        );
    }

    /// @dev logic to handle deletion of redeem entry
    function _deleteRedeemEntry(address account, uint256 index) internal {
        userRedeems[account][index] = userRedeems[account][
            userRedeems[account].length - 1
        ];
        userRedeems[account].pop();
    }

    /// @dev Utility function to get the current block timestamp
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }

    /// @dev Utility function to tranfer xGMBL balances without approvals according to the logic of this contract
    function _transferFromSelf(
        address who,
        address to,
        uint256 amount
    ) internal {
        balanceOf[who] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
    }
}

