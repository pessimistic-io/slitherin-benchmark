// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./Address.sol";
import "./SafeMath.sol";

import "./IProtocolToken.sol";
import "./IXToken.sol";
import "./IXTokenUsage.sol";

/*
 * xToken is a escrowed governance token obtainable by converting ProtocolToken to it
 * It's non-transferable, except from/to whitelisted addresses
 * It can be converted back to ProtocolToken through a vesting process
 * This contract is made to receive xToken deposits from users in order to allocate them to Usages (plugins) contracts
 */
contract xToken is AccessControl, ReentrancyGuard, ERC20, IXToken {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IProtocolToken;
    using SafeMath for uint256; // solc >= 0.8 version to avoid certain math conversion bugs

    struct XTokenBalance {
        uint256 allocatedAmount; // Amount of xToken allocated to a Usage
        uint256 redeemingAmount; // Total amount of xToken currently being redeemed
    }

    struct RedeemInfo {
        uint256 protocolTokenAmount; // protocol token amount to receive when vesting has ended
        uint256 xTokenAmount; // xToken amount to redeem
        uint256 endTime;
        IXTokenUsage dividendsAddress;
        uint256 dividendsAllocation; // Share of redeeming xToken to allocate to the Dividends Usage contract
    }

    bytes32 public OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant MAX_DEALLOCATION_FEE = 200; // 2%
    uint256 public constant MAX_FIXED_RATIO = 100; // 100%

    // Redeeming min/max settings
    uint256 public minRedeemRatio = 50; // 1:0.5
    uint256 public maxRedeemRatio = 100; // 1:1
    uint256 public minRedeemDuration = 15 days; // 1296000s
    uint256 public maxRedeemDuration = 90 days; // 7776000s

    // Adjusted dividends rewards for redeeming xToken
    uint256 public redeemDividendsAdjustment = 0;

    address public treasury;
    IProtocolToken public protocolToken; // protocol token to convert to/from
    IXTokenUsage public dividendsAddress; //  dividends/fee sharing contract

    EnumerableSet.AddressSet private _transferWhitelist; // addresses allowed to send/receive xToken

    mapping(address => mapping(address => uint256)) public usageApprovals; // Usage approvals to allocate xToken
    mapping(address => mapping(address => uint256)) public override usageAllocations; // Active xToken allocations to usages
    mapping(address => uint256) public usagesDeallocationFee; // Fee paid when deallocating xToken
    mapping(address => XTokenBalance) public xTokenBalances; // User's xToken balances
    mapping(address => RedeemInfo[]) public userRedeems; // User's redeeming instances

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event ApproveUsage(address indexed userAddress, address indexed usageAddress, uint256 amount);
    event Convert(address indexed from, address to, uint256 amount);
    event UpdateRedeemSettings(
        uint256 minRedeemRatio,
        uint256 maxRedeemRatio,
        uint256 minRedeemDuration,
        uint256 maxRedeemDuration,
        uint256 redeemDividendsAdjustment
    );
    event UpdateDividendsAddress(address previousDividendsAddress, address newDividendsAddress);
    event UpdateDeallocationFee(address indexed usageAddress, uint256 fee);
    event SetTransferWhitelist(address account, bool add);
    event Redeem(address indexed userAddress, uint256 xTokenAmount, uint256 protocolTokenAmount, uint256 duration);
    event FinalizeRedeem(address indexed userAddress, uint256 xTokenAmount, uint256 protocolTokenAmount);
    event CancelRedeem(address indexed userAddress, uint256 xTokenAmount);
    event UpdateRedeemDividendsAddress(
        address indexed userAddress,
        uint256 redeemIndex,
        address previousDividendsAddress,
        address newDividendsAddress
    );
    event Allocate(address indexed userAddress, address indexed usageAddress, uint256 amount);
    event Deallocate(address indexed userAddress, address indexed usageAddress, uint256 amount, uint256 fee);
    event TreasuryUpdated(address previousAddress, address newAddress);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "Only admin");
        _;
    }

    /*
     * @dev Check if a redeem entry exists
     */
    modifier validateRedeem(address userAddress, uint256 redeemIndex) {
        require(redeemIndex < userRedeems[userAddress].length, "validateRedeem: redeem entry does not exist");
        _;
    }

    constructor(
        IProtocolToken _protocolToken,
        address _treasury,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(address(_protocolToken) != address(0), "ProtocolToken not provided");
        require(_treasury != address(0), "Treasury not provided");

        protocolToken = _protocolToken;
        treasury = _treasury;
        _transferWhitelist.add(address(this));
        _transferWhitelist.add(msg.sender);

        _grantRole(DEFAULT_ADMIN_ROLE, _treasury);
        _grantRole(OPERATOR_ROLE, _treasury);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /*
     * @dev Returns user's xToken balances
     */
    function getXTokenBalance(
        address userAddress
    ) external view returns (uint256 allocatedAmount, uint256 redeemingAmount) {
        XTokenBalance storage balance = xTokenBalances[userAddress];
        return (balance.allocatedAmount, balance.redeemingAmount);
    }

    /*
     * @dev returns redeemable ProtocolToken for "amount" of xToken vested for "duration" seconds
     */
    function getProtocolTokenByVestingDuration(uint256 amount, uint256 duration) public view returns (uint256) {
        if (duration < minRedeemDuration) {
            return 0;
        }

        // capped to maxRedeemDuration
        if (duration > maxRedeemDuration) {
            return (amount * maxRedeemRatio) / 100;
        }

        // uint256 ratio = minRedeemRatio.add(
        //     (duration.sub(minRedeemDuration)).mul(maxRedeemRatio.sub(minRedeemRatio)).div(
        //         maxRedeemDuration.sub(minRedeemDuration)
        //     )
        // );

        // Checks are needed for min/max redemption ratio and current min/max redemption time frame
        // Since protocol can update these later if wanted/needed

        // duration.sub(minRedeemDuration)
        // How far the selected duration is beyond the current required minimun time
        uint durationToMinRedeemDurationDiff = duration - minRedeemDuration;

        // Difference between current values for max ratio use to determine amount user receive when converting,
        // and the current min amount they must receive
        uint currentMinMaxRedeemRatioDiff = maxRedeemRatio - minRedeemRatio; // maxRedeemRatio.sub(minRedeemRatio)

        // duration.sub(minRedeemDuration)).mul(maxRedeemRatio.sub(minRedeemRatio)
        uint redeemDurationRedeemRatioProduct = durationToMinRedeemDurationDiff * currentMinMaxRedeemRatioDiff;

        // Will be our denominator
        // maxRedeemDuration.sub(minRedeemDuration)
        uint currentRedeemDurationMinMaxDiff = maxRedeemDuration - minRedeemDuration;

        // (duration.sub(minRedeemDuration)).mul(maxRedeemRatio.sub(minRedeemRatio)).div(maxRedeemDuration.sub(minRedeemDuration))
        uint256 addingToMinRedeemRatio = redeemDurationRedeemRatioProduct / currentRedeemDurationMinMaxDiff;

        uint256 ratio = minRedeemRatio + addingToMinRedeemRatio;

        return (amount * ratio) / 100;
    }

    /**
     * @dev returns quantity of "userAddress" pending redeems
     */
    function getUserRedeemsLength(address userAddress) external view returns (uint256) {
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
            uint256 protocolTokenAmount,
            uint256 xTokenAmount,
            uint256 endTime,
            address dividendsContract,
            uint256 dividendsAllocation
        )
    {
        RedeemInfo storage _redeem = userRedeems[userAddress][redeemIndex];
        return (
            _redeem.protocolTokenAmount,
            _redeem.xTokenAmount,
            _redeem.endTime,
            address(_redeem.dividendsAddress),
            _redeem.dividendsAllocation
        );
    }

    /**
     * @dev returns approved xToken to allocate from "userAddress" to "usageAddress"
     */
    function getUsageApproval(address userAddress, address usageAddress) external view returns (uint256) {
        return usageApprovals[userAddress][usageAddress];
    }

    /**
     * @dev returns allocated xToken from "userAddress" to "usageAddress"
     */
    function getUsageAllocation(address userAddress, address usageAddress) external view returns (uint256) {
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
     * @dev returns if "account" is allowed to send/receive xToken
     */
    function isTransferWhitelisted(address account) external view override returns (bool) {
        return _transferWhitelist.contains(account);
    }

    // /*****************************************************************/
    // /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    // /*****************************************************************/

    /**
     * @dev Approves "usage" address to get allocations up to "amount" of xToken from msg.sender
     * IXTokenUsage is the systems plugin interface.
     */
    function approveUsage(IXTokenUsage usage, uint256 amount) external nonReentrant {
        require(address(usage) != address(0), "approveUsage: approve to the zero address");

        usageApprovals[msg.sender][address(usage)] = amount;
        emit ApproveUsage(msg.sender, address(usage), amount);
    }

    /**
     * @dev Convert caller's "amount" of ProtocolToken to xToken
     */
    function convert(uint256 amount) external nonReentrant {
        _convert(amount, msg.sender);
    }

    /**
     * @dev Convert caller's "amount" of ProtocolToken to xToken to "to" address
     */
    function convertTo(uint256 amount, address to) external override nonReentrant {
        require(address(msg.sender).isContract(), "convertTo: not allowed");
        _convert(amount, to);
    }

    /**
     * @dev Initiates redeem process (xToken to ProtocolToken)
     *
     * Handles dividends' compensation allocation during the vesting process if needed
     */
    function redeem(uint256 xTokenAmount, uint256 duration) external nonReentrant {
        require(xTokenAmount > 0, "redeem: xTokenAmount cannot be null");
        require(duration >= minRedeemDuration, "redeem: duration too low");

        _transfer(msg.sender, address(this), xTokenAmount);
        XTokenBalance storage balance = xTokenBalances[msg.sender];

        // get corresponding ProtocolToken amount
        uint256 protocolTokenAmount = getProtocolTokenByVestingDuration(xTokenAmount, duration);
        emit Redeem(msg.sender, xTokenAmount, protocolTokenAmount, duration);

        // if redeeming is not immediate, go through vesting process
        if (duration > 0) {
            // add to SBT total
            balance.redeemingAmount += xTokenAmount;

            // handle dividends during the vesting process
            uint256 dividendsAllocation = (xTokenAmount * redeemDividendsAdjustment) / 100;
            // only if compensation is active
            if (dividendsAllocation > 0) {
                // allocate to dividends
                dividendsAddress.allocate(msg.sender, dividendsAllocation, new bytes(0));
            }

            // add redeeming entry
            userRedeems[msg.sender].push(
                RedeemInfo(
                    protocolTokenAmount,
                    xTokenAmount,
                    block.timestamp + duration,
                    dividendsAddress,
                    dividendsAllocation
                )
            );
        } else {
            // immediately redeem for ProtocolToken
            _finalizeRedeem(msg.sender, xTokenAmount, protocolTokenAmount);
        }
    }

    /**
     * @dev Finalizes redeem process when vesting duration has been reached
     *
     * Can only be called by the redeem entry owner
     */
    function finalizeRedeem(uint256 redeemIndex) external nonReentrant validateRedeem(msg.sender, redeemIndex) {
        XTokenBalance storage balance = xTokenBalances[msg.sender];
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];
        require(block.timestamp >= _redeem.endTime, "finalizeRedeem: vesting duration has not ended yet");

        // remove from SBT total
        balance.redeemingAmount -= _redeem.xTokenAmount;
        _finalizeRedeem(msg.sender, _redeem.xTokenAmount, _redeem.protocolTokenAmount);

        // handle dividends compensation if any was active
        if (_redeem.dividendsAllocation > 0) {
            // deallocate from dividends
            IXTokenUsage(_redeem.dividendsAddress).deallocate(msg.sender, _redeem.dividendsAllocation, new bytes(0));
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
        if (dividendsAddress != _redeem.dividendsAddress && address(dividendsAddress) != address(0)) {
            if (_redeem.dividendsAllocation > 0) {
                // deallocate from old dividends contract
                _redeem.dividendsAddress.deallocate(msg.sender, _redeem.dividendsAllocation, new bytes(0));
                // allocate to new used dividends contract
                dividendsAddress.allocate(msg.sender, _redeem.dividendsAllocation, new bytes(0));
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
    function cancelRedeem(uint256 redeemIndex) external nonReentrant validateRedeem(msg.sender, redeemIndex) {
        XTokenBalance storage balance = xTokenBalances[msg.sender];
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];

        uint256 xRedeemAmount = _redeem.xTokenAmount; // gas stash

        // make redeeming xToken available again
        balance.redeemingAmount -= xRedeemAmount;
        _transfer(address(this), msg.sender, xRedeemAmount);

        // handle dividends compensation if any was active
        if (_redeem.dividendsAllocation > 0) {
            // deallocate from dividends
            IXTokenUsage(_redeem.dividendsAddress).deallocate(msg.sender, _redeem.dividendsAllocation, new bytes(0));
        }

        emit CancelRedeem(msg.sender, xRedeemAmount);

        // remove redeem entry
        _deleteRedeemEntry(redeemIndex);
    }

    /**
     * @dev Allocates caller's "amount" of available xToken to "usageAddress" contract
     *
     * args specific to usage contract must be passed into "usageData"
     */
    function allocate(address usageAddress, uint256 amount, bytes calldata usageData) external nonReentrant {
        _allocate(msg.sender, usageAddress, amount);

        // allocates xToken to usageContract
        IXTokenUsage(usageAddress).allocate(msg.sender, amount, usageData);
    }

    /**
     * @dev Allocates "amount" of available xToken from "userAddress" to caller (ie usage contract)
     *
     * Caller must have an allocation approval for the required xToken from "userAddress"
     */
    function allocateFromUsage(address userAddress, uint256 amount) external override nonReentrant {
        _allocate(userAddress, msg.sender, amount);
    }

    /**
     * @dev Deallocates caller's "amount" of available xToken from "usageAddress" contract
     *
     * args specific to usage contract must be passed into "usageData"
     */
    function deallocate(address usageAddress, uint256 amount, bytes calldata usageData) external nonReentrant {
        _deallocate(msg.sender, usageAddress, amount);

        // deallocate xToken into usageContract
        IXTokenUsage(usageAddress).deallocate(msg.sender, amount, usageData);
    }

    /**
     * @dev Deallocates "amount" of allocated xToken belonging to "userAddress" from caller (ie usage contract)
     *
     * Caller can only deallocate xToken from itself
     */
    function deallocateFromUsage(address userAddress, uint256 amount) external override nonReentrant {
        _deallocate(userAddress, msg.sender, amount);
    }

    // /********************************************************/
    // /****************** INTERNAL FUNCTIONS ******************/
    // /********************************************************/

    /**
     * @dev Convert caller's "amount" of ProtocolToken into xToken to "to"
     */
    function _convert(uint256 amount, address to) internal {
        require(amount != 0, "convert: amount cannot be null");

        // mint new xToken
        _mint(to, amount);

        emit Convert(msg.sender, to, amount);
        protocolToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Finalizes the redeeming process for "userAddress"
     * by transferring him "protocolTokenAmount" and removing "xTokenAmount" from supply
     *
     * Any vesting check should be ran before calling this
     * ProtocolToken excess is automatically burnt
     */
    function _finalizeRedeem(address userAddress, uint256 xTokenAmount, uint256 protocolTokenAmount) internal {
        uint256 protocolTokenExcess = xTokenAmount - protocolTokenAmount;

        // sends due ProtocolToken tokens
        protocolToken.safeTransfer(userAddress, protocolTokenAmount);

        // burns ProtocolToken excess if any
        protocolToken.burn(protocolTokenExcess);
        _burn(address(this), xTokenAmount);

        emit FinalizeRedeem(userAddress, xTokenAmount, protocolTokenAmount);
    }

    /**
     * @dev Allocates "userAddress" user's "amount" of available xToken to "usageAddress" contract
     *
     */
    function _allocate(address userAddress, address usageAddress, uint256 amount) internal {
        require(amount > 0, "allocate: amount cannot be null");

        XTokenBalance storage balance = xTokenBalances[userAddress];

        // approval checks if allocation request amount has been approved by userAddress to be allocated to this usageAddress
        uint256 approvedXToken = usageApprovals[userAddress][usageAddress];
        require(approvedXToken >= amount, "allocate: non authorized amount");

        // remove allocated amount from usage's approved amount
        usageApprovals[userAddress][usageAddress] = approvedXToken - amount;

        // update usage's allocatedAmount for userAddress
        usageAllocations[userAddress][usageAddress] += amount;

        // adjust user's xToken balances
        balance.allocatedAmount = balance.allocatedAmount + amount;
        _transfer(userAddress, address(this), amount);

        emit Allocate(userAddress, usageAddress, amount);
    }

    /**
     * @dev Deallocates "amount" of available xToken to "usageAddress" contract
     *
     * args specific to usage contract must be passed into "usageData"
     */
    function _deallocate(address userAddress, address usageAddress, uint256 amount) internal {
        require(amount > 0, "deallocate: amount cannot be null");

        // check if there is enough allocated xToken to this usage to deallocate
        uint256 allocatedAmount = usageAllocations[userAddress][usageAddress];
        require(allocatedAmount >= amount, "deallocate: non authorized amount");

        // remove deallocated amount from usage's allocation
        usageAllocations[userAddress][usageAddress] = allocatedAmount - amount;

        uint256 deallocationFeeAmount = (amount * usagesDeallocationFee[usageAddress]) / 10000;

        // adjust user's xToken balances
        XTokenBalance storage balance = xTokenBalances[userAddress];
        balance.allocatedAmount -= amount;
        _transfer(address(this), userAddress, amount - deallocationFeeAmount);

        // burn corresponding ProtocolToken and xToken
        protocolToken.burn(deallocationFeeAmount);
        _burn(address(this), deallocationFeeAmount);

        emit Deallocate(userAddress, usageAddress, amount, deallocationFeeAmount);
    }

    function _deleteRedeemEntry(uint256 index) internal {
        userRedeems[msg.sender][index] = userRedeems[msg.sender][userRedeems[msg.sender].length - 1];
        userRedeems[msg.sender].pop();
    }

    /**
     * @dev Hook override to forbid transfers except from whitelisted addresses and minting
     */
    function _beforeTokenTransfer(address from, address to, uint256 /*amount*/) internal view override {
        require(
            from == address(0) || _transferWhitelist.contains(from) || _transferWhitelist.contains(to),
            "transfer: not allowed"
        );
    }

    // /*******************************************************/
    // /****************** OWNABLE FUNCTIONS ******************/
    // /*******************************************************/

    /**
     * @dev Updates all redeem ratios and durations
     *
     * Must only be called by owner
     */
    function updateRedeemSettings(
        uint256 _minRedeemRatio,
        uint256 _maxRedeemRatio,
        uint256 _minRedeemDuration,
        uint256 _maxRedeemDuration,
        uint256 _redeemDividendsAdjustment
    ) external onlyOperator {
        require(_minRedeemRatio <= _maxRedeemRatio, "updateRedeemSettings: wrong ratio values");
        require(_minRedeemDuration < _maxRedeemDuration, "updateRedeemSettings: wrong duration values");
        // should never exceed 100%
        require(
            _maxRedeemRatio <= MAX_FIXED_RATIO && _redeemDividendsAdjustment <= MAX_FIXED_RATIO,
            "updateRedeemSettings: wrong ratio values"
        );

        minRedeemRatio = _minRedeemRatio;
        maxRedeemRatio = _maxRedeemRatio;
        minRedeemDuration = _minRedeemDuration;
        maxRedeemDuration = _maxRedeemDuration;
        redeemDividendsAdjustment = _redeemDividendsAdjustment;

        emit UpdateRedeemSettings(
            _minRedeemRatio,
            _maxRedeemRatio,
            _minRedeemDuration,
            _maxRedeemDuration,
            _redeemDividendsAdjustment
        );
    }

    /**
     * @dev Updates dividends contract address
     *
     * Must only be called by owner
     */
    function updateDividendsAddress(IXTokenUsage _dividendsAddress) external onlyOperator {
        // if set to 0, also set divs earnings while redeeming to 0
        if (address(_dividendsAddress) == address(0)) {
            redeemDividendsAdjustment = 0;
        }

        emit UpdateDividendsAddress(address(dividendsAddress), address(_dividendsAddress));
        dividendsAddress = _dividendsAddress;
    }

    /**
     * @dev Updates fee paid by users when deallocating from "usageAddress"
     */
    function updateDeallocationFee(address usageAddress, uint256 fee) external onlyOperator {
        require(fee <= MAX_DEALLOCATION_FEE, "updateDeallocationFee: too high");

        usagesDeallocationFee[usageAddress] = fee;
        emit UpdateDeallocationFee(usageAddress, fee);
    }

    /**
     * @dev Adds or removes addresses from the transferWhitelist
     */
    function updateTransferWhitelist(address account, bool add) external onlyOperator {
        require(account != address(this), "updateTransferWhitelist: Cannot remove xToken from whitelist");

        if (add) _transferWhitelist.add(account);
        else _transferWhitelist.remove(account);

        emit SetTransferWhitelist(account, add);
    }

    function setTreasury(address _treasury) external onlyOperator {
        require(_treasury != address(0), "Treasury not provided");

        emit TreasuryUpdated(treasury, _treasury);

        treasury = _treasury;
    }
}

