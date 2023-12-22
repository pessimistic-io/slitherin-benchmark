pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

pragma solidity ^0.8.0;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

pragma solidity 0.8.16;

interface ICamelFarmPair {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function initialize(address, address) external;
}

pragma solidity 0.8.16;

interface IBoringERC20 {
    function mint(address to, uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /// @notice EIP 2612
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

pragma solidity 0.8.16;

library BoringERC20 {
    bytes4 private constant SIG_SYMBOL = 0x95d89b41; // symbol()
    bytes4 private constant SIG_NAME = 0x06fdde03; // name()
    bytes4 private constant SIG_DECIMALS = 0x313ce567; // decimals()
    bytes4 private constant SIG_TRANSFER = 0xa9059cbb; // transfer(address,uint256)
    bytes4 private constant SIG_TRANSFER_FROM = 0x23b872dd; // transferFrom(address,address,uint256)

    function returnDataToString(bytes memory data)
        internal
        pure
        returns (string memory)
    {
        if (data.length >= 64) {
            return abi.decode(data, (string));
        } else if (data.length == 32) {
            uint8 i = 0;
            while (i < 32 && data[i] != 0) {
                i++;
            }
            bytes memory bytesArray = new bytes(i);
            for (i = 0; i < 32 && data[i] != 0; i++) {
                bytesArray[i] = data[i];
            }
            return string(bytesArray);
        } else {
            return "???";
        }
    }

    /// @notice Provides a safe ERC20.symbol version which returns '???' as fallback string.
    /// @param token The address of the ERC-20 token contract.
    /// @return (string) Token symbol.
    function safeSymbol(IBoringERC20 token)
        internal
        view
        returns (string memory)
    {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeWithSelector(SIG_SYMBOL)
        );
        return success ? returnDataToString(data) : "???";
    }

    /// @notice Provides a safe ERC20.name version which returns '???' as fallback string.
    /// @param token The address of the ERC-20 token contract.
    /// @return (string) Token name.
    function safeName(IBoringERC20 token)
        internal
        view
        returns (string memory)
    {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeWithSelector(SIG_NAME)
        );
        return success ? returnDataToString(data) : "???";
    }

    /// @notice Provides a safe ERC20.decimals version which returns '18' as fallback value.
    /// @param token The address of the ERC-20 token contract.
    /// @return (uint8) Token decimals.
    function safeDecimals(IBoringERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeWithSelector(SIG_DECIMALS)
        );
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    /// @notice Provides a safe ERC20.transfer version for different ERC-20 implementations.
    /// Reverts on a failed transfer.
    /// @param token The address of the ERC-20 token.
    /// @param to Transfer tokens to.
    /// @param amount The token amount.
    function safeTransfer(
        IBoringERC20 token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(SIG_TRANSFER, to, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "BoringERC20: Transfer failed"
        );
    }

    /// @notice Provides a safe ERC20.transferFrom version for different ERC-20 implementations.
    /// Reverts on a failed transfer.
    /// @param token The address of the ERC-20 token.
    /// @param from Transfer tokens from.
    /// @param to Transfer tokens to.
    /// @param amount The token amount.
    function safeTransferFrom(
        IBoringERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(SIG_TRANSFER_FROM, from, to, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "BoringERC20: TransferFrom failed"
        );
    }
}

pragma solidity 0.8.16;

interface IMultipleRewards {
    function onCamelReward(
        uint256 pid,
        address user,
        uint256 newLpAmount
    ) external;

    function pendingTokens(uint256 pid, address user)
        external
        view
        returns (uint256 pending);

    function rewardToken() external view returns (IBoringERC20);

    function poolRewardsPerSec(uint256 pid) external view returns (uint256);
}

pragma solidity 0.8.16;

contract CamelChef is Ownable, ReentrancyGuard {
    using BoringERC20 for IBoringERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
    }

    // Info of each pool.
    struct PoolInfo {
        IBoringERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Camelto distribute per block.
        uint256 lastRewardTimestamp; // Last block number that Cameldistribution occurs.
        uint256 accCamelPerShare; // Accumulated Camelper share, times 1e18. See below.
        uint16 withdrawFeeBP; // Deposit fee in basis points
        uint256 harvestInterval; // Harvest interval in seconds
        uint256 totalLp; // Total token in Pool
        IMultipleRewards[] rewarders; // Array of rewarder contract for pools with incentives
    }

    IBoringERC20 public camel;

    // Cameltokens created per second
    uint256 public camelPerSec;

    // Max harvest interval: 14 days
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 14 days;

    // Maximum deposit fee rate: 10%
    uint16 public constant MAXIMUM_DEPOSIT_FEE_RATE = 1000;

    // Info of each pool
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // The timestamp when Camelmining starts.
    uint256 public startTimestamp;

    // Total locked up rewards
    uint256 public totalLockedUpRewards;

    // Total Camelin CamelPools (can be multiple pools)
    uint256 public totalCamelInPools;

    // xCAMEL address.
    address public xCAMELAddress;

    // deposit fee address if needed
    address public feeAddress;

    // Percentage of pool rewards that goto the team.
    uint256 public xCAMELPercent;

    // The precision factor
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "Pool does not exist");
        _;
    }

    event Add(
        uint256 indexed pid,
        uint256 allocPoint,
        IBoringERC20 indexed lpToken,
        uint16 withdrawFeeBP,
        uint256 harvestInterval,
        IMultipleRewards[] indexed rewarders
    );

    event Set(
        uint256 indexed pid,
        uint256 allocPoint,
        uint16 withdrawFeeBP,
        uint256 harvestInterval,
        IMultipleRewards[] indexed rewarders
    );

    event UpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTimestamp,
        uint256 lpSupply,
        uint256 accCamelPerShare
    );

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    event EmissionRateUpdated(
        address indexed caller,
        uint256 previousValue,
        uint256 newValue
    );

    event RewardLockedUp(
        address indexed user,
        uint256 indexed pid,
        uint256 amountLockedUp
    );

    event AllocPointsUpdated(
        address indexed caller,
        uint256 previousAmount,
        uint256 newAmount
    );

    event SetxCAMELAddress(
        address indexed oldAddress,
        address indexed newAddress
    );

    event SetFeeAddress(address indexed oldAddress, address indexed newAddress);

    event SetInvestorAddress(
        address indexed oldAddress,
        address indexed newAddress
    );

    event SetxCAMELPercent(uint256 oldPercent, uint256 newPercent);

    constructor(
        IBoringERC20 _camel,
        uint256 _camelPerSec,
        address _xCAMELAddress,
        uint256 _xCAMELPercent,
        address _feeAddress
    ) {
        require(
            _xCAMELPercent <= 1000,
            "constructor: invalid xCAMEL percent value"
        );

        startTimestamp = block.timestamp + (60 * 60 * 24 * 365);

        camel = _camel;
        camelPerSec = _camelPerSec;
        xCAMELAddress = _xCAMELAddress;
        xCAMELPercent = _xCAMELPercent;
        feeAddress = _feeAddress;
    }

    // Set farming start, can call only once
    function startFarming() public onlyOwner {
        require(block.timestamp < startTimestamp, "farm already started");

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTimestamp = block.timestamp;
        }

        startTimestamp = block.timestamp;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // Can add multiple pool with same lp token without messing up rewards, because each pool's balance is tracked using its own totalLp
    function add(
        uint256 _allocPoint,
        IBoringERC20 _lpToken,
        uint16 _withdrawFeeBP,
        uint256 _harvestInterval,
        IMultipleRewards[] calldata _rewarders
    ) public onlyOwner {
        require(_rewarders.length <= 10, "add: too many rewarders");
        require(
            _withdrawFeeBP <= MAXIMUM_DEPOSIT_FEE_RATE,
            "add: deposit fee too high"
        );
        require(
            _harvestInterval <= MAXIMUM_HARVEST_INTERVAL,
            "add: invalid harvest interval"
        );
        for (
            uint256 rewarderId = 0;
            rewarderId < _rewarders.length;
            ++rewarderId
        ) {
            require(
                Address.isContract(address(_rewarders[rewarderId])),
                "add: rewarder must be contract"
            );
        }

        _massUpdatePools();

        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;

        totalAllocPoint += _allocPoint;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accCamelPerShare: 0,
                withdrawFeeBP: _withdrawFeeBP,
                harvestInterval: _harvestInterval,
                totalLp: 0,
                rewarders: _rewarders
            })
        );

        emit Add(
            poolInfo.length - 1,
            _allocPoint,
            _lpToken,
            _withdrawFeeBP,
            _harvestInterval,
            _rewarders
        );
    }

    // Update the given pool's Camelallocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _withdrawFeeBP,
        uint256 _harvestInterval,
        IMultipleRewards[] calldata _rewarders
    ) public onlyOwner validatePoolByPid(_pid) {
        require(_rewarders.length <= 10, "set: too many rewarders");

        require(
            _withdrawFeeBP <= MAXIMUM_DEPOSIT_FEE_RATE,
            "set: deposit fee too high"
        );
        require(
            _harvestInterval <= MAXIMUM_HARVEST_INTERVAL,
            "set: invalid harvest interval"
        );

        for (
            uint256 rewarderId = 0;
            rewarderId < _rewarders.length;
            ++rewarderId
        ) {
            require(
                Address.isContract(address(_rewarders[rewarderId])),
                "set: rewarder must be contract"
            );
        }

        _massUpdatePools();

        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;

        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
        poolInfo[_pid].rewarders = _rewarders;

        emit Set(
            _pid,
            _allocPoint,
            _withdrawFeeBP,
            _harvestInterval,
            _rewarders
        );
    }

    // View function to see pending rewards on frontend.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        validatePoolByPid(_pid)
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory amounts
        )
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCamelPerShare = pool.accCamelPerShare;
        uint256 lpSupply = pool.totalLp;

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 total = 1000;
            uint256 lpPercent = total - xCAMELPercent;

            uint256 camelReward = (multiplier *
                camelPerSec *
                pool.allocPoint *
                lpPercent) /
                totalAllocPoint /
                total;

            accCamelPerShare += (
                ((camelReward * ACC_TOKEN_PRECISION) / lpSupply)
            );
        }

        uint256 pendingCamel= (((user.amount * accCamelPerShare) /
            ACC_TOKEN_PRECISION) - user.rewardDebt) + user.rewardLockedUp;

        addresses = new address[](pool.rewarders.length + 1);
        symbols = new string[](pool.rewarders.length + 1);
        amounts = new uint256[](pool.rewarders.length + 1);
        decimals = new uint256[](pool.rewarders.length + 1);

        addresses[0] = address(camel);
        symbols[0] = IBoringERC20(camel).safeSymbol();
        decimals[0] = IBoringERC20(camel).safeDecimals();
        amounts[0] = pendingCamel;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            addresses[rewarderId + 1] = address(
                pool.rewarders[rewarderId].rewardToken()
            );

            symbols[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeSymbol();

            decimals[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeDecimals();

            amounts[rewarderId + 1] = pool.rewarders[rewarderId].pendingTokens(
                _pid,
                _user
            );
        }
    }

    /// @notice View function to see pool rewards per sec
    function poolRewardsPerSec(uint256 _pid)
        external
        view
        validatePoolByPid(_pid)
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory rewardsPerSec
        )
    {
        PoolInfo storage pool = poolInfo[_pid];

        addresses = new address[](pool.rewarders.length + 1);
        symbols = new string[](pool.rewarders.length + 1);
        decimals = new uint256[](pool.rewarders.length + 1);
        rewardsPerSec = new uint256[](pool.rewarders.length + 1);

        addresses[0] = address(camel);
        symbols[0] = IBoringERC20(camel).safeSymbol();
        decimals[0] = IBoringERC20(camel).safeDecimals();

        uint256 total = 1000;
        uint256 lpPercent = total - xCAMELPercent;

        rewardsPerSec[0] =
            (pool.allocPoint * camelPerSec * lpPercent) /
            totalAllocPoint /
            total;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            addresses[rewarderId + 1] = address(
                pool.rewarders[rewarderId].rewardToken()
            );

            symbols[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeSymbol();

            decimals[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeDecimals();

            rewardsPerSec[rewarderId + 1] = pool
                .rewarders[rewarderId]
                .poolRewardsPerSec(_pid);
        }
    }

    // View function to see rewarders for a pool
    function poolRewarders(uint256 _pid)
        external
        view
        validatePoolByPid(_pid)
        returns (address[] memory rewarders)
    {
        PoolInfo storage pool = poolInfo[_pid];
        rewarders = new address[](pool.rewarders.length);
        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            rewarders[rewarderId] = address(pool.rewarders[rewarderId]);
        }
    }

    // View function to see if user can harvest Camel.
    function canHarvest(uint256 _pid, address _user)
        public
        view
        validatePoolByPid(_pid)
        returns (bool)
    {
        UserInfo storage user = userInfo[_pid][_user];
        return
            block.timestamp >= startTimestamp &&
            block.timestamp >= user.nextHarvestUntil;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() external nonReentrant {
        _massUpdatePools();
    }

    // Internal method for massUpdatePools
    function _massUpdatePools() internal {
        for (uint256 pid = 0; pid < poolInfo.length; ++pid) {
            _updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) external nonReentrant {
        _updatePool(_pid);
    }

    // Internal method for _updatePool
    function _updatePool(uint256 _pid) internal validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }

        uint256 lpSupply = pool.totalLp;

        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;

        uint256 camelReward = ((multiplier * camelPerSec) * pool.allocPoint) /
            totalAllocPoint;

        uint256 total = 1000;
        uint256 lpPercent = total - xCAMELPercent;

        if (xCAMELPercent > 0) {
            camel.mint(xCAMELAddress, (camelReward * xCAMELPercent) / total);
        }

        camel.mint(address(this), (camelReward * lpPercent) / total);

        pool.accCamelPerShare +=
            (camelReward * ACC_TOKEN_PRECISION * lpPercent) /
            pool.totalLp /
            total;

        pool.lastRewardTimestamp = block.timestamp;

        emit UpdatePool(
            _pid,
            pool.lastRewardTimestamp,
            lpSupply,
            pool.accCamelPerShare
        );
    }

    function depositWithPermit(
        uint256 pid,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public nonReentrant validatePoolByPid(pid) {
        PoolInfo storage pool = poolInfo[pid];
        ICamelFarmPair pair = ICamelFarmPair(address(pool.lpToken));
        pair.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(pid, amount);
    }

    // Deposit tokens for Camelallocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        _deposit(_pid, _amount);
    }

    // Deposit tokens for Camelallocation.
    function _deposit(uint256 _pid, uint256 _amount)
        internal
        validatePoolByPid(_pid)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        payOrLockupPendingCamel(_pid);

        if (_amount > 0) {
            uint256 beforeDeposit = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 afterDeposit = pool.lpToken.balanceOf(address(this));

            _amount = afterDeposit - beforeDeposit;


            user.amount += _amount;

            if (address(pool.lpToken) == address(camel)) {
                totalCamelInPools += _amount;
            }
        }
        user.rewardDebt =
            (user.amount * pool.accCamelPerShare) /
            ACC_TOKEN_PRECISION;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            pool.rewarders[rewarderId].onCamelReward(
                _pid,
                msg.sender,
                user.amount
            );
        }

        if (_amount > 0) {
            pool.totalLp += _amount;
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    //withdraw tokens
    function withdraw(uint256 _pid, uint256 _amount)
        public
        nonReentrant
        validatePoolByPid(_pid)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //this will make sure that user can only withdraw from his pool
        require(user.amount >= _amount, "withdraw: user amount not enough");

        //cannot withdraw more than pool's balance
        require(pool.totalLp >= _amount, "withdraw: pool total not enough");

        _updatePool(_pid);

        payOrLockupPendingCamel(_pid);

        if (_amount > 0) {
            user.amount -= _amount;
            if (address(pool.lpToken) == address(camel)) {
                totalCamelInPools -= _amount;
            }

            
            if (pool.withdrawFeeBP > 0) {
                uint256 depositFee = (_amount * pool.withdrawFeeBP) / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);

                _amount = _amount - depositFee;
            }

            pool.lpToken.safeTransfer(msg.sender, _amount);
        }

        user.rewardDebt =
            (user.amount * pool.accCamelPerShare) /
            ACC_TOKEN_PRECISION;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            pool.rewarders[rewarderId].onCamelReward(
                _pid,
                msg.sender,
                user.amount
            );
        }

        if (_amount > 0) {
            pool.totalLp -= _amount;
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;

        //Cannot withdraw more than pool's balance
        require(
            pool.totalLp >= amount,
            "emergency withdraw: pool total not enough"
        );

        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
        pool.totalLp -= amount;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            pool.rewarders[rewarderId].onCamelReward(_pid, msg.sender, 0);
        }

        if (address(pool.lpToken) == address(camel)) {
            totalCamelInPools -= amount;
        }

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Pay or lockup pending Camel.
    function payOrLockupPendingCamel(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0 && block.timestamp >= startTimestamp) {
            user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
        }

        if (user.nextHarvestUntil != 0 && pool.harvestInterval == 0) {
            user.nextHarvestUntil = 0;
        }

        uint256 pending = ((user.amount * pool.accCamelPerShare) /
            ACC_TOKEN_PRECISION) - user.rewardDebt;

        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 pendingRewards = pending + user.rewardLockedUp;

                // reset lockup
                totalLockedUpRewards -= user.rewardLockedUp;
                user.rewardLockedUp = 0;
                user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
                safeCamelTransfer(msg.sender, pendingRewards);
            }
        } else if (pending > 0) {
            totalLockedUpRewards += pending;
            user.rewardLockedUp += pending;
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    function safeCamelTransfer(address _to, uint256 _amount) internal {
        if (camel.balanceOf(address(this)) > totalCamelInPools) {
            uint256 camelBal = camel.balanceOf(address(this)) -
                totalCamelInPools;
            if (_amount >= camelBal) {
                camel.safeTransfer(_to, camelBal);
            } else if (_amount > 0) {
                camel.safeTransfer(_to, _amount);
            }
        }
    }

    function updateAllocPoint(uint256 _pid, uint256 _allocPoint)
        public
        onlyOwner
    {
        _massUpdatePools();

        emit AllocPointsUpdated(
            msg.sender,
            poolInfo[_pid].allocPoint,
            _allocPoint
        );

        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function updateEmissionRate(uint256 _camelPerSec) public onlyOwner {
        _massUpdatePools();

        emit EmissionRateUpdated(msg.sender, camelPerSec, _camelPerSec);

        camelPerSec = _camelPerSec;
    }

    function poolTotalLp(uint256 pid) external view returns (uint256) {
        return poolInfo[pid].totalLp;
    }

    // Function to harvest many pools in a single transaction
    function harvestMany(uint256[] calldata _pids) public nonReentrant {
        require(_pids.length <= 30, "harvest many: too many pool ids");
        for (uint256 index = 0; index < _pids.length; ++index) {
            _deposit(_pids[index], 0);
        }
    }

    // Update xCAMEL address
    function setxCAMELAddress(address _xCAMELAddress) public onlyOwner {
        require(_xCAMELAddress != address(0), "invalid new xCAMEL address");
        xCAMELAddress = _xCAMELAddress;
        emit SetxCAMELAddress(msg.sender, _xCAMELAddress);
    }

    function setxCAMELPercent(uint256 _newxCAMELPercent) public onlyOwner {
        require(_newxCAMELPercent <= 1000, "invalid percent value");
        emit SetxCAMELPercent(xCAMELPercent, _newxCAMELPercent);
        xCAMELPercent = _newxCAMELPercent;
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        require(_feeAddress != address(0), "wrong address");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function getCamelPerSec() public view returns (uint256) {
        return camelPerSec;
    }
}