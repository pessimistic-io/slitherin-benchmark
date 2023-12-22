// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";

import "./IZyberTokenV2.sol";
import "./IXZyberToken.sol";
import "./IXZyberTokenUsage.sol";

/*
 * sZYB is Zyberswaps escrowed governance token obtainable by converting ZYB to it
 * It's non-transferable, except from/to whitelisted addresses
 * It can be converted back to ZYB through a vesting process
 * This contract is made to receive sZYB deposits from users in order to allocate them to Usages (plugins) contracts
 */
contract sZyberToken is
    Ownable,
    ReentrancyGuard,
    ERC20("Staked Zyber Token", "sZYB"),
    IXZyberToken
{
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IZyberTokenV2;

    struct XZyberBalance {
        uint256 allocatedAmount; // Amount of sZYB allocated to a Usage
        uint256 redeemingAmount; // Total amount of sZYB currently being redeemed
    }

    struct RedeemInfo {
        uint256 zybAmount; // ZYB amount to receive when vesting has ended
        uint256 xZyberAmount; // sZYB amount to redeem
        uint256 endTime; // end time of redeeming if left for the desired duration
        IXZyberTokenUsage dividendsAddress;
        uint256 dividendsAllocation; // Share of redeeming sZYB to allocate to the Dividends Usage contract
        uint256 startTime; // start time of redeem action
    }

    IZyberTokenV2 public immutable zybToken; // ZYB token to convert to/from
    IXZyberTokenUsage public dividendsAddress; // Zyberswap dividends contract

    EnumerableSet.AddressSet private _transferWhitelist; // addresses allowed to send/receive sZYB

    mapping(address => mapping(address => uint256)) public usageApprovals; // Usage approvals to allocate sZYB
    mapping(address => mapping(address => uint256))
        public
        override usageAllocations; // Active sZYB allocations to usages

    uint256 public constant MAX_DEALLOCATION_FEE = 200; // 2%
    mapping(address => uint256) public usagesDeallocationFee; // Fee paid when deallocating sZYB

    uint256 public constant MAX_FIXED_RATIO = 1 ether; // 100%

    // Redeeming min/max settings
    uint256 public minRedeemRatio = MAX_FIXED_RATIO / 2; // 1:0.5 precision is 1**18
    uint256 public maxRedeemRatio = MAX_FIXED_RATIO; // 1:1 precision is 1**18
    uint256 public minRedeemDuration = 14 days;
    uint256 public maxRedeemDuration = 180 days;
    // Adjusted dividends rewards for redeeming sZYB
    uint256 public redeemDividendsAdjustment = MAX_FIXED_RATIO / 2; // 50% precision is 1**18

    address internal constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    mapping(address => XZyberBalance) public xZyberBalances; // User's sZYB balances
    mapping(address => RedeemInfo[]) public userRedeems; // User's redeeming instances

    constructor(IZyberTokenV2 _zybToken) {
        zybToken = _zybToken;
        _transferWhitelist.add(address(this));
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event ApproveUsage(
        address indexed userAddress,
        address indexed usageAddress,
        uint256 amount
    );
    event Convert(address indexed from, address to, uint256 amount);
    event UpdateRedeemSettings(
        uint256 minRedeemRatio,
        uint256 maxRedeemRatio,
        uint256 minRedeemDuration,
        uint256 maxRedeemDuration,
        uint256 redeemDividendsAdjustment
    );
    event UpdateDividendsAddress(
        address previousDividendsAddress,
        address newDividendsAddress
    );
    event UpdateDeallocationFee(address indexed usageAddress, uint256 fee);
    event SetTransferWhitelist(address account, bool add);
    event Redeem(
        address indexed userAddress,
        uint256 xZyberAmount,
        uint256 zybAmount,
        uint256 duration
    );
    event FinalizeRedeem(
        address indexed userAddress,
        uint256 xZyberAmount,
        uint256 zybAmount
    );
    event CancelRedeem(address indexed userAddress, uint256 xZyberAmount);
    event UpdateRedeemDividendsAddress(
        address indexed userAddress,
        uint256 redeemIndex,
        address previousDividendsAddress,
        address newDividendsAddress
    );
    event Allocate(
        address indexed userAddress,
        address indexed usageAddress,
        uint256 amount
    );
    event Deallocate(
        address indexed userAddress,
        address indexed usageAddress,
        uint256 amount,
        uint256 fee
    );

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /*
     * @dev Check if a redeem entry exists
     */
    modifier validateRedeem(address userAddress, uint256 redeemIndex) {
        require(
            redeemIndex < userRedeems[userAddress].length,
            "validateRedeem: redeem entry does not exist"
        );
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /*
     * @dev Returns user's sZYB balances
     */
    function getXZyberBalance(
        address userAddress
    ) external view returns (uint256 allocatedAmount, uint256 redeemingAmount) {
        XZyberBalance storage balance = xZyberBalances[userAddress];
        return (balance.allocatedAmount, balance.redeemingAmount);
    }

    /*
     * @dev returns redeemable ZYB for "amount" of sZYB vested for "duration" seconds
     */
    function getZyberByVestingDuration(
        uint256 amount,
        uint256 duration
    ) public view returns (uint256) {
        if (duration < minRedeemDuration) {
            return 0;
        }

        // capped to maxRedeemDuration
        if (duration > maxRedeemDuration) {
            return (amount * maxRedeemRatio) / MAX_FIXED_RATIO;
        }

        uint256 ratio = minRedeemRatio +
            ((duration - minRedeemDuration) *
                (maxRedeemRatio - minRedeemRatio)) /
            (maxRedeemDuration - minRedeemDuration);

        return (amount * ratio) / MAX_FIXED_RATIO;
    }

    /**
     * @dev returns quantity of "userAddress" pending redeems
     */
    function getUserRedeemsLength(
        address userAddress
    ) external view returns (uint256) {
        return userRedeems[userAddress].length;
    }

    /**
     * @dev returns "userAddress" info for a pending redeem identified by "redeemIndex"
     */
    function getUserRedeem(
        address userAddress,
        uint256 redeemIndex
    )
        external
        view
        validateRedeem(userAddress, redeemIndex)
        returns (
            uint256 zybAmount,
            uint256 xZyberAmount,
            uint256 endTime,
            address dividendsContract,
            uint256 dividendsAllocation
        )
    {
        RedeemInfo storage _redeem = userRedeems[userAddress][redeemIndex];
        return (
            _redeem.zybAmount,
            _redeem.xZyberAmount,
            _redeem.endTime,
            address(_redeem.dividendsAddress),
            _redeem.dividendsAllocation
        );
    }

    /**
     * @dev returns approved xToken to allocate from "userAddress" to "usageAddress"
     */
    function getUsageApproval(
        address userAddress,
        address usageAddress
    ) external view returns (uint256) {
        return usageApprovals[userAddress][usageAddress];
    }

    /**
     * @dev returns allocated xToken from "userAddress" to "usageAddress"
     */
    function getUsageAllocation(
        address userAddress,
        address usageAddress
    ) external view returns (uint256) {
        return usageAllocations[userAddress][usageAddress];
    }

    /**
     * @dev returns length of transferWhitelist array
     */
    function transferWhitelistLength() external view returns (uint256) {
        return _transferWhitelist.length();
    }

    /**
     * @dev returns transferWhitelist array item's address for "index"
     */
    function transferWhitelist(uint256 index) external view returns (address) {
        return _transferWhitelist.at(index);
    }

    /**
     * @dev returns if "account" is allowed to send/receive sZYB
     */
    function isTransferWhitelisted(
        address account
    ) external view override returns (bool) {
        return _transferWhitelist.contains(account);
    }

    /*******************************************************/
    /****************** OWNABLE FUNCTIONS ******************/
    /*******************************************************/

    /**
     * @dev Updates all redeem ratios and durations
     *
     * Must only be called by owner
     */
    function updateRedeemSettings(
        uint256 minRedeemRatio_,
        uint256 maxRedeemRatio_,
        uint256 minRedeemDuration_,
        uint256 maxRedeemDuration_,
        uint256 redeemDividendsAdjustment_
    ) external onlyOwner {
        require(
            minRedeemRatio_ <= maxRedeemRatio_,
            "updateRedeemSettings: wrong ratio values"
        );
        require(
            minRedeemDuration_ < maxRedeemDuration_,
            "updateRedeemSettings: wrong duration values"
        );
        // should never exceed 100%
        require(
            maxRedeemRatio_ <= MAX_FIXED_RATIO &&
                redeemDividendsAdjustment_ <= MAX_FIXED_RATIO,
            "updateRedeemSettings: wrong ratio values"
        );

        minRedeemRatio = minRedeemRatio_;
        maxRedeemRatio = maxRedeemRatio_;
        minRedeemDuration = minRedeemDuration_;
        maxRedeemDuration = maxRedeemDuration_;
        redeemDividendsAdjustment = redeemDividendsAdjustment_;

        emit UpdateRedeemSettings(
            minRedeemRatio_,
            maxRedeemRatio_,
            minRedeemDuration_,
            maxRedeemDuration_,
            redeemDividendsAdjustment_
        );
    }

    /**
     * @dev Updates dividends contract address
     *
     * Must only be called by owner
     */
    function updateDividendsAddress(
        IXZyberTokenUsage dividendsAddress_
    ) external onlyOwner {
        // if set to 0, also set divs earnings while redeeming to 0
        if (address(dividendsAddress_) == address(0)) {
            redeemDividendsAdjustment = 0;
        }

        emit UpdateDividendsAddress(
            address(dividendsAddress),
            address(dividendsAddress_)
        );
        dividendsAddress = dividendsAddress_;
    }

    /**
     * @dev Updates fee paid by users when deallocating from "usageAddress"
     */
    function updateDeallocationFee(
        address usageAddress,
        uint256 fee
    ) external onlyOwner {
        require(fee <= MAX_DEALLOCATION_FEE, "updateDeallocationFee: too high");

        usagesDeallocationFee[usageAddress] = fee;
        emit UpdateDeallocationFee(usageAddress, fee);
    }

    /**
     * @dev Adds or removes addresses from the transferWhitelist
     */
    function updateTransferWhitelist(
        address account,
        bool add
    ) external onlyOwner {
        require(
            account != address(this),
            "updateTransferWhitelist: Cannot remove xToken from whitelist"
        );

        if (add) _transferWhitelist.add(account);
        else _transferWhitelist.remove(account);

        emit SetTransferWhitelist(account, add);
    }

    /*****************************************************************/
    /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    /*****************************************************************/

    /**
     * @dev Approves "usage" address to get allocations up to "amount" of sZYB from msg.sender
     */
    function approveUsage(
        IXZyberTokenUsage usage,
        uint256 amount
    ) external nonReentrant {
        require(
            address(usage) != address(0),
            "approveUsage: approve to the zero address"
        );

        usageApprovals[msg.sender][address(usage)] = amount;
        emit ApproveUsage(msg.sender, address(usage), amount);
    }

    /**
     * @dev Convert caller's "amount" of ZYB to sZYB
     */
    function convert(uint256 amount) external nonReentrant {
        _convert(amount, msg.sender);
    }

    /**
     * @dev Convert caller's "amount" of ZYB to sZYB to "to" address
     */
    function convertTo(
        uint256 amount,
        address to
    ) external override nonReentrant {
        require(address(msg.sender).isContract(), "convertTo: not allowed");
        _convert(amount, to);
    }

    /**
     * @dev Initiates redeem process (sZYB to ZYB)
     *
     * Handles dividends' compensation allocation during the vesting process if needed
     */
    function redeem(
        uint256 xZyberAmount,
        uint256 duration
    ) external nonReentrant {
        require(xZyberAmount > 0, "redeem: xZyberAmount cannot be null");
        require(duration >= minRedeemDuration, "redeem: duration too low");

        _transfer(msg.sender, address(this), xZyberAmount);
        XZyberBalance storage balance = xZyberBalances[msg.sender];

        // get corresponding ZYB amount
        uint256 zybAmount = getZyberByVestingDuration(xZyberAmount, duration);
        emit Redeem(msg.sender, xZyberAmount, zybAmount, duration);

        // if redeeming is not immediate, go through vesting process
        if (duration > 0) {
            // add to SBT total
            balance.redeemingAmount += xZyberAmount;

            // handle dividends during the vesting process
            uint256 dividendsAllocation = (xZyberAmount *
                redeemDividendsAdjustment) / MAX_FIXED_RATIO;

            // only if compensation is active
            if (dividendsAllocation > 0) {
                // allocate to dividends
                dividendsAddress.allocate(
                    msg.sender,
                    dividendsAllocation,
                    new bytes(0)
                );
            }

            // add redeeming entry
            userRedeems[msg.sender].push(
                RedeemInfo(
                    zybAmount,
                    xZyberAmount,
                    _currentBlockTimestamp() + duration,
                    dividendsAddress,
                    dividendsAllocation,
                    _currentBlockTimestamp()
                )
            );
        } else {
            // immediately redeem for ZYB
            _finalizeRedeem(msg.sender, xZyberAmount, zybAmount);
        }
    }

    /**
     * @dev Finalizes redeem process when vesting duration has been reached
     *
     * Can only be called by the redeem entry owner
     */
    function finalizeRedeem(
        uint256 redeemIndex
    ) external nonReentrant validateRedeem(msg.sender, redeemIndex) {
        XZyberBalance storage balance = xZyberBalances[msg.sender];
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];
        require(
            _currentBlockTimestamp() >= _redeem.startTime + minRedeemDuration,
            "finalizeRedeem: min duration before redeem"
        );

        // remove from total
        balance.redeemingAmount -= _redeem.xZyberAmount;

        uint256 duration = _currentBlockTimestamp() - _redeem.startTime;
        uint256 zybAmount = getZyberByVestingDuration(
            _redeem.xZyberAmount,
            duration
        );
        _finalizeRedeem(msg.sender, _redeem.xZyberAmount, zybAmount);

        // handle dividends compensation if any was active
        if (_redeem.dividendsAllocation > 0) {
            // deallocate from dividends
            IXZyberTokenUsage(_redeem.dividendsAddress).deallocate(
                msg.sender,
                _redeem.dividendsAllocation,
                new bytes(0)
            );
        }

        // remove redeem entry
        _deleteRedeemEntry(redeemIndex);
    }

    /**
     * @dev Updates dividends address for an existing active redeeming process
     *
     * Can only be called by the involved user
     * Should only be used if dividends contract was to be migrated
     */
    function updateRedeemDividendsAddress(
        uint256 redeemIndex
    ) external nonReentrant validateRedeem(msg.sender, redeemIndex) {
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];

        // only if the active dividends contract is not the same anymore
        if (
            dividendsAddress != _redeem.dividendsAddress &&
            address(dividendsAddress) != address(0)
        ) {
            if (_redeem.dividendsAllocation > 0) {
                // deallocate from old dividends contract
                _redeem.dividendsAddress.deallocate(
                    msg.sender,
                    _redeem.dividendsAllocation,
                    new bytes(0)
                );
                // allocate to new used dividends contract
                dividendsAddress.allocate(
                    msg.sender,
                    _redeem.dividendsAllocation,
                    new bytes(0)
                );
            }

            emit UpdateRedeemDividendsAddress(
                msg.sender,
                redeemIndex,
                address(_redeem.dividendsAddress),
                address(dividendsAddress)
            );
            _redeem.dividendsAddress = dividendsAddress;
        }
    }

    /**
     * @dev Cancels an ongoing redeem entry
     *
     * Can only be called by its owner
     */
    function cancelRedeem(
        uint256 redeemIndex
    ) external nonReentrant validateRedeem(msg.sender, redeemIndex) {
        XZyberBalance storage balance = xZyberBalances[msg.sender];
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];

        // make redeeming sZYB available again
        balance.redeemingAmount -= _redeem.xZyberAmount;

        _transfer(address(this), msg.sender, _redeem.xZyberAmount);

        // handle dividends compensation if any was active
        if (_redeem.dividendsAllocation > 0) {
            // deallocate from dividends
            IXZyberTokenUsage(_redeem.dividendsAddress).deallocate(
                msg.sender,
                _redeem.dividendsAllocation,
                new bytes(0)
            );
        }

        emit CancelRedeem(msg.sender, _redeem.xZyberAmount);

        // remove redeem entry
        _deleteRedeemEntry(redeemIndex);
    }

    /**
     * @dev Allocates caller's "amount" of available sZYB to "usageAddress" contract
     *
     * args specific to usage contract must be passed into "usageData"
     */
    function allocate(
        address usageAddress,
        uint256 amount,
        bytes calldata usageData
    ) external nonReentrant {
        _allocate(msg.sender, usageAddress, amount);

        // allocates sZYB to usageContract
        IXZyberTokenUsage(usageAddress).allocate(msg.sender, amount, usageData);
    }

    /**
     * @dev Allocates "amount" of available sZYB from "userAddress" to caller (ie usage contract)
     *
     * Caller must have an allocation approval for the required xToken sZYB from "userAddress"
     */
    function allocateFromUsage(
        address userAddress,
        uint256 amount
    ) external override nonReentrant {
        _allocate(userAddress, msg.sender, amount);
    }

    /**
     * @dev Deallocates caller's "amount" of available sZYB from "usageAddress" contract
     *
     * args specific to usage contract must be passed into "usageData"
     */
    function deallocate(
        address usageAddress,
        uint256 amount,
        bytes calldata usageData
    ) external nonReentrant {
        _deallocate(msg.sender, usageAddress, amount);

        // deallocate sZYB into usageContract
        IXZyberTokenUsage(usageAddress).deallocate(
            msg.sender,
            amount,
            usageData
        );
    }

    /**
     * @dev Deallocates "amount" of allocated sZYB belonging to "userAddress" from caller (ie usage contract)
     *
     * Caller can only deallocate sZYB from itself
     */
    function deallocateFromUsage(
        address userAddress,
        uint256 amount
    ) external override nonReentrant {
        _deallocate(userAddress, msg.sender, amount);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev Convert caller's "amount" of ZYB into sZYB to "to"
     */
    function _convert(uint256 amount, address to) internal {
        require(amount != 0, "convert: amount cannot be null");

        // mint new sZYB
        _mint(to, amount);

        emit Convert(msg.sender, to, amount);
        zybToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Finalizes the redeeming process for "userAddress" by transferring him "zybAmount" and removing "xZyberAmount" from supply
     *
     * Any vesting check should be ran before calling this
     * ZYB excess is automatically burnt
     */
    function _finalizeRedeem(
        address userAddress,
        uint256 xZyberAmount,
        uint256 zybAmount
    ) internal {
        uint256 zybExcess = xZyberAmount - zybAmount;

        // sends due ZYB tokens
        zybToken.safeTransfer(userAddress, zybAmount);

        // burns ZYB excess if any
        if (zybExcess > 0) {
            zybToken.safeTransfer(BURN_ADDRESS, zybExcess);
        }

        _burn(address(this), xZyberAmount);

        emit FinalizeRedeem(userAddress, xZyberAmount, zybAmount);
    }

    /**
     * @dev Allocates "userAddress" user's "amount" of available sZYB to "usageAddress" contract
     *
     */
    function _allocate(
        address userAddress,
        address usageAddress,
        uint256 amount
    ) internal {
        require(amount > 0, "allocate: amount cannot be null");

        XZyberBalance storage balance = xZyberBalances[userAddress];

        // approval checks if allocation request amount has been approved by userAddress to be allocated to this usageAddress
        uint256 approvedXZyber = usageApprovals[userAddress][usageAddress];
        require(approvedXZyber >= amount, "allocate: non authorized amount");

        // remove allocated amount from usage's approved amount
        usageApprovals[userAddress][usageAddress] = approvedXZyber - amount;

        // update usage's allocatedAmount for userAddress
        usageAllocations[userAddress][usageAddress] =
            usageAllocations[userAddress][usageAddress] +
            amount;

        // adjust user's sZYB balances
        balance.allocatedAmount = balance.allocatedAmount + amount;
        _transfer(userAddress, address(this), amount);

        emit Allocate(userAddress, usageAddress, amount);
    }

    /**
     * @dev Deallocates "amount" of available sZYB to "usageAddress" contract
     *
     * args specific to usage contract must be passed into "usageData"
     */
    function _deallocate(
        address userAddress,
        address usageAddress,
        uint256 amount
    ) internal {
        require(amount > 0, "deallocate: amount cannot be null");

        // check if there is enough allocated sZYB to this usage to deallocate
        uint256 allocatedAmount = usageAllocations[userAddress][usageAddress];
        require(allocatedAmount >= amount, "deallocate: non authorized amount");

        // remove deallocated amount from usage's allocation
        usageAllocations[userAddress][usageAddress] = allocatedAmount - amount;

        uint256 deallocationFeeAmount = (amount *
            usagesDeallocationFee[usageAddress]) / 10000;

        // adjust user's sZYB balances
        XZyberBalance storage balance = xZyberBalances[userAddress];
        balance.allocatedAmount -= amount;

        _transfer(address(this), userAddress, amount - deallocationFeeAmount);
        // burn corresponding ZYB and XSYNTH
        zybToken.safeTransfer(BURN_ADDRESS, deallocationFeeAmount);
        _burn(address(this), deallocationFeeAmount);

        emit Deallocate(
            userAddress,
            usageAddress,
            amount,
            deallocationFeeAmount
        );
    }

    function _deleteRedeemEntry(uint256 index) internal {
        userRedeems[msg.sender][index] = userRedeems[msg.sender][
            userRedeems[msg.sender].length - 1
        ];
        userRedeems[msg.sender].pop();
    }

    /**
     * @dev Hook override to forbid transfers except from whitelisted addresses and minting
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 /*amount*/
    ) internal view override {
        require(
            from == address(0) ||
                _transferWhitelist.contains(from) ||
                _transferWhitelist.contains(to),
            "transfer: not allowed"
        );
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }
}

