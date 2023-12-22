// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

pragma solidity ^0.8.0;

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
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
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
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
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

pragma solidity ^0.8.0;

interface IVotingEscrow {

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    function token() external view returns (address);
    function team() external view returns (address);
    function epoch() external view returns (uint);
    function point_history(uint loc) external view returns (Point memory);
    function user_point_history(
        uint tokenId, 
        uint loc
    ) external view returns (Point memory);

    function user_point_epoch(uint tokenId) external view returns (uint);

    function ownerOf(uint) external view returns (address);
    function isApprovedOrOwner(address, uint) external view returns (bool);
    function transferFrom(address, address, uint) external;
    function safeTransferFrom(address, address, uint) external;

    function voting(uint tokenId) external;
    function abstain(uint tokenId) external;
    function attach(uint tokenId) external;
    function detach(uint tokenId) external;

    function checkpoint() external;
    function deposit_for(uint tokenId, uint value) external;
    function create_lock_for(uint, uint, address) external returns (uint);

    function balanceOfNFT(uint) external view returns (uint);
    function totalSupply() external view returns (uint);

    // added for MigrationBurn
    function locked(uint) external view returns (LockedBalance memory);
    function balanceOf(address) external view returns (uint);
    function tokenOfOwnerByIndex(address, uint) external view returns (uint);
    function attachments(uint) external view returns (uint);
    function voted(uint256) external view returns (bool);
}

pragma solidity ^0.8.0;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types

library SafeCast {
    /**
     * @dev Returns the downcasted uint160 from uint256, reverting on
     * overflow (when the input is greater than largest uint160).
     *
     * Counterpart to Solidity's `uint160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "SafeCast: value doesn't fit in 160 bits");
        return uint160(value);
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v3.1._
     */
    function toInt128(int256 value) internal pure returns (int128 downcasted) {
        downcasted = int128(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 128 bits");
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     *
     * _Available since v3.0._
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(value <= uint256(type(int256).max), "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }

    /**
     * @dev Returns the downcasted int56 from int256, reverting on
     * overflow (when the input is less than smallest int56 or
     * greater than largest int56).
     *
     * Counterpart to Solidity's `int56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toInt56(int256 value) internal pure returns (int56 downcasted) {
        downcasted = int56(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 56 bits");
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     *
     * _Available since v3.0._
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v2.5._
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value <= type(uint8).max, "SafeCast: value doesn't fit in 8 bits");
        return uint8(value);
    }

    /**
     * @dev Returns the downcasted int24 from int256, reverting on
     * overflow (when the input is less than smallest int24 or
     * greater than largest int24).
     *
     * Counterpart to Solidity's `int24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toInt24(int256 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 24 bits");
    }

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v2.5._
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }
}

pragma solidity ^0.8.0;

/**
 * @notice Migration burn logic
 */

contract MigrationBurn {
    /// @notice Dead address(multi-sig address) to send burned tokens to
    address public constant deadAddress = 0x3Bb9372989c81d56db64e8aaD38401E677b91244;
    address public constant strtoken = 0x5DB7b150c5F38c5F5db11dCBDB885028fcC51D68;
    address public constant venftaddy = 0x450330Df68E1ed6e0683373D684064bDa9115fEe;

    address public owner;

    /// @dev For simple reentrancy check
    uint256 internal _unlocked;
    /// @notice No tokens can be burned after this date
    uint256 public deadline;
    /// @notice List of all valid burnable ERC20 token addresses
    address[] public validBurnableTokenAddresses; 
    /// @dev Mapping to keep track whether a specific token is burnable
    mapping(address => bool) public tokenIsBurnable;
    /// @dev tokensBurnedByAccount[tokenAddress][accountAddress]
    mapping(address => mapping(address => uint256)) public tokensBurnedByAccount;
    /// @notice Total tokens burned by token address
    mapping(address => uint256) public tokensBurnedByToken;
    /// @dev tokenId index in array of user burned veNFTs
    mapping(address => mapping(uint256 => uint256)) public veNftBurnedIndexById;
    /// @dev array of veNFT tokenIds a user has burned
    mapping(address => uint256[]) public veNftBurnedIdByIndex;
    /// @dev total STR equivalent burned via veNFT of a user
    mapping(address => uint256) public veNftBurnedAmountByAccount;
    /// @dev total STR equivalent burned via veNFTs
    uint256 public veNftBurnedAmountTotal;

    IVotingEscrow public veNft;

    /**************************************************
     *                    Structs
     **************************************************/
    struct Token {
        address id; // Token address
        string name; // Token name
        string symbol; // Token symbol
        uint256 decimals; // Token decimals
        uint256 balance; // Token balance
        uint256 burned; // Tokens burned
        bool approved; // Did user approve tokens to be burned
    }

    struct VeNft {
        uint256 id; // NFT ID
        uint256 balance; // Balance for user
        uint256 end; // Lock end time
        uint256 burned; // True if burned
        bool attached; // True if NFT attached to a gauge
        bool voted; // True if NFT needs to reset votes
        bool lockedForTwoMonths; // True if locked for ~2 months
        bool approved; // True if approved for burn
    }

    /**************************************************
     *                   Modifiers
     **************************************************/

    /// @dev Simple reentrancy check
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /// @dev Only allow burning for predefined period
    modifier onlyBurnPeriod() {
        require(block.timestamp < deadline, "Burn period over");
        _;
    }

    /// @dev Only allow sending to dead address after predefined period and a week to issue refunds
    modifier onlyAfterBurnPeriod() {
        require(block.timestamp > deadline + 1 weeks, "Burn period not over");
        _;
    }

    /**************************************************
     *                   Initialization
     **************************************************/

    constructor() {
        _unlocked = 1;

        //  May 31, 2023, 23:59:00 GMT
        deadline = 1685573940;

        // Set burn token addresses
        validBurnableTokenAddresses.push(strtoken);
        owner = msg.sender;

        // Set burn token mapping
        for (uint256 i = 0; i < validBurnableTokenAddresses.length; i++) {
            tokenIsBurnable[validBurnableTokenAddresses[i]] = true;
        }

        veNft = IVotingEscrow(venftaddy); // Set veNFT interface
    }

    /**
     * @notice Transfers ownership
     * @param newOwner new owner, or address(0) to renounce ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @notice Extends deadline
     * @param _newDeadline new deadline
     * @dev _newDealine must be longer than existing deadline
     */
    function extendDeadline(uint256 _newDeadline) external onlyOwner {
        require(
            _newDeadline > deadline,
            "New dealdine must be longer than existing deadline"
        );
        deadline = _newDeadline;
    }

    /**************************************************
     *                  ERC20 burn logic
     **************************************************/

    /**
     * @notice Primary burn method for ERC20 tokens
     * @param tokenAddress Address of the token to burn
     * @dev Only allow burning entire user balance. YOLO
     * @dev Method can only be called during burn period
     */
    function burn(address tokenAddress) external lock onlyBurnPeriod {
        require(tokenIsBurnable[tokenAddress], "Invalid burn token"); // Only allow burning on valid burn tokens
        uint256 amountToBurn = IERC20MetadataUpgradeable(tokenAddress).balanceOf(msg.sender); // Fetch user token balance
        IERC20MetadataUpgradeable(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amountToBurn
        ); // Transfer burn tokens from msg.sender to burn contract
        tokensBurnedByAccount[tokenAddress][msg.sender] += amountToBurn; // Record burned token and amount
        tokensBurnedByToken[tokenAddress] += amountToBurn; // Increment global token amount burned for this token
    }

    /**************************************************
     *                  veNFT burn logic
     **************************************************/

    /**
     * @notice Burn veNFT
     * @param tokenId Token ID to burn
     * @dev Method can only be called during burn period
     */
    function burnVeNft(uint256 tokenId) external lock onlyBurnPeriod {
        IVotingEscrow.LockedBalance memory _locked = veNft.locked(tokenId); // Retrieve NFT lock data

        // Require the veNFT to locked for 2 months with a grace period of 2 weeks
        require(
            _locked.end > block.timestamp + 8 weeks - 2 weeks,
            "Please lock your veNFT for 2 months"
        );

        veNft.safeTransferFrom(msg.sender, address(this), tokenId); // Transfer veNFT

        // Increment locked amount per user
        veNftBurnedAmountByAccount[msg.sender] += SafeCast.toUint256(
            _locked.amount
        );
        // Increment total STR burned via veNFTs
        veNftBurnedAmountTotal += SafeCast.toUint256(_locked.amount);
        // record index of tokenId at the end of array of user burned NFT
        veNftBurnedIndexById[msg.sender][tokenId] = veNftBurnedIdByIndex[msg.sender].length;
        // Add NFT to list of burned NFTs
        veNftBurnedIdByIndex[msg.sender].push(tokenId);
    }

    /**************************************************
     *                 Refund methods
     **************************************************/

    /**
     * @notice Owner callable function to issue refunds
     * @param accountAddress User address to be refunded
     * @param tokenAddress Token address to be refunded
     */
    function refund(address accountAddress, address tokenAddress)
        external
        lock
        onlyOwner
    {
        // Fetch amount of tokens to return
        uint256 amountToReturn = tokensBurnedByAccount[tokenAddress][
            accountAddress
        ];
        tokensBurnedByAccount[tokenAddress][accountAddress] = 0; // Set user token balance to zero
        IERC20MetadataUpgradeable(tokenAddress).transfer(accountAddress, amountToReturn); // Return tokens to user
        tokensBurnedByToken[tokenAddress] -= amountToReturn; // Decrement global token amount burned for this token
    }

    /**
     * @notice Owner callable function to issue refunds
     * @param accountAddress User address to be refunded
     * @param tokenId veNFT tokenId to be refunded
     */
    function refundVeNft(address accountAddress, uint256 tokenId)
        external
        lock
        onlyOwner
    {
        uint256 index = veNftBurnedIndexById[accountAddress][tokenId]; // Get index of tokenId in user array
        assert(veNftBurnedIdByIndex[accountAddress][index] == tokenId); // Sanity check, see if requested IDs are the same
        delete veNftBurnedIndexById[accountAddress][tokenId]; // Delete index for tokenId

        // Fetch last NFT ID in array
        uint256 lastId = veNftBurnedIdByIndex[accountAddress][
            veNftBurnedIdByIndex[accountAddress].length - 1
        ];

        veNftBurnedIdByIndex[accountAddress][index] = lastId; // Update token Id by index
        veNftBurnedIndexById[accountAddress][lastId] = index; // Update index by token ID
        veNftBurnedIdByIndex[accountAddress].pop(); // Remove last token ID
        veNft.safeTransferFrom(address(this), accountAddress, tokenId); // Transfer veNFT
        IVotingEscrow.LockedBalance memory _locked = veNft.locked(tokenId); // Fetch locked balance of NFT
        // Decrement locked amount per user
        veNftBurnedAmountByAccount[accountAddress] -= SafeCast.toUint256(
            _locked.amount
        );
        // Decrement total STR burned via veNFTs
        veNftBurnedAmountTotal -= SafeCast.toUint256(_locked.amount);
    }

    /**************************************************
     *           Send to Dead Address methods
     **************************************************/
    /**
     * @notice Publically callable function to send ERC20s burned to dead address after burn period ends
     */
    function sendTokensToDead() external onlyAfterBurnPeriod onlyOwner {
        // Iterate through all valid burnable tokens
        for (
            uint256 burnableTokenIdx = 0;
            burnableTokenIdx < validBurnableTokenAddresses.length;
            burnableTokenIdx++
        ) {
            IERC20MetadataUpgradeable _token = IERC20MetadataUpgradeable(
                validBurnableTokenAddresses[burnableTokenIdx]
            ); // Fetch ERC20 interface for the current token
            uint256 balance = _token.balanceOf(address(this)); // Fetch burned token balance
            _token.transfer(deadAddress, balance); // Transfer tokens to dead address
        }
    }

    /**
     * @notice Publically callable function to send veNFTs burned to dead address after burn period ends
     * @param maxRuns max amount of veNFTs to send (due to gas limit)
     */
    function sendVeNftsToDead(uint256 maxRuns)
        external
        onlyAfterBurnPeriod
        onlyOwner
    {
        uint256 burnedVeNfts = veNft.balanceOf(address(this));

        // replace maxRuns with owned amount if applicable
        if (maxRuns < burnedVeNfts) {
            maxRuns = burnedVeNfts;
        }

        // Iterate through burned veNFTs up to maxRuns
        for (uint256 tokenIdx; tokenIdx < maxRuns; tokenIdx++) {
            // Fetch first item since last item would've been removed from the array
            uint256 tokenId = veNft.tokenOfOwnerByIndex(address(this), 0);

            veNft.safeTransferFrom(address(this), deadAddress, tokenId); // Transfer veNFT to dead address
        }
    }

    /**************************************************
     *                  View methods
     **************************************************/

    /**
     * @notice Return a list of all user NFTs and metadata about each NFT
     */
    function veNftByAccount(address accountAddress)
        external
        view
        returns (VeNft[] memory)
    {
        uint256 veNftsOwned = veNft.balanceOf(accountAddress); // Fetch owned number of veNFTs
        uint256 burnedVeNfts = veNftBurnedIdByIndex[accountAddress].length; // Fetch burned number of veNFTs

        VeNft[] memory _veNfts = new VeNft[](veNftsOwned + burnedVeNfts); // Define return array

        // Loop through owned NFTs and log info
        for (uint256 tokenIdx; tokenIdx < veNftsOwned; tokenIdx++) {
            // Fetch veNFT tokenId
            uint256 tokenId = veNft.tokenOfOwnerByIndex(
                accountAddress,
                tokenIdx
            );
            IVotingEscrow.LockedBalance memory locked = veNft.locked(tokenId); // Fetch veNFT lock data
            uint256 lockedAmount = SafeCast.toUint256(locked.amount); // Cast locked amount to uint256

            // Populate struct fields
            _veNfts[tokenIdx] = VeNft({
                id: tokenId,
                balance: lockedAmount, // veNFT locked amount int128->uint256
                end: locked.end, // veNFT unlock time
                burned: 0, // Assumed not burned since it's still in user's address
                attached: veNft.attachments(tokenId) > 0, // Whether veNFT is attached to gauges
                voted: veNft.voted(tokenId), // True if NFT needs to reset votes
                lockedForTwoMonths: locked.end >
                    block.timestamp + 8 weeks - 2 weeks, // Locked for 2 months or not, with 2 weeks grace period
                approved: veNft.isApprovedOrOwner(address(this), tokenId) ==
                    true // veNft approved for burn or not
            });
        }

        // Loop through burned NFTs and log info
        for (uint256 tokenIdx; tokenIdx < burnedVeNfts; tokenIdx++) {
            // Fetch veNFT tokenId
            uint256 tokenId = veNftBurnedIdByIndex[accountAddress][tokenIdx];
            IVotingEscrow.LockedBalance memory locked = veNft.locked(tokenId); // Fetch veNFT lock data
            uint256 lockedAmount = SafeCast.toUint256(locked.amount); // Cast locked amount to uint256

            // Populate struct fields
            _veNfts[tokenIdx + veNftsOwned] = VeNft({
                id: tokenId,
                balance: 0, // Assume zero since user no longer owns the NFT
                end: locked.end, // veNFT unlock time
                burned: lockedAmount, // Assumed burned since it's in burn address
                attached: false, // Assume false since it's already burned
                voted: false, // Assume false since it's already burned
                lockedForTwoMonths: true, // Assume true since it's already burned
                approved: true // Assume true since it's already burned
            });
        }
        return _veNfts;
    }

    /**
     * @notice Fetch burnable and burned tokens per account
     * @param accountAddress Address of the account for which to view
     * @return tokens Returns an array of burnable and burned tokens
     */
    function burnableTokens(address accountAddress)
        external
        view
        returns (Token[] memory tokens)
    {
        Token[] memory _tokens = new Token[](
            validBurnableTokenAddresses.length
        ); // Create an array of tokens

        // Iterate through all valid burnable tokens
        for (
            uint256 burnableTokenIdx = 0;
            burnableTokenIdx < validBurnableTokenAddresses.length;
            burnableTokenIdx++
        ) {
            address tokenAddress = validBurnableTokenAddresses[
                burnableTokenIdx
            ]; // Fetch token address
            IERC20MetadataUpgradeable _token = IERC20MetadataUpgradeable(tokenAddress); // Fetch ERC20 interface for the current token
            uint256 _userBalance = _token.balanceOf(accountAddress); // Fetch token balance

            // Fetch burned balance
            uint256 _burnedBalance = tokensBurnedByAccount[tokenAddress][
                accountAddress
            ];

            // Fetch allowance state
            bool _tokenTransferAllowed = _token.allowance(
                accountAddress,
                address(this)
            ) > _userBalance;

            // Fetch token metadata
            Token memory token = Token({
                id: tokenAddress,
                name: _token.name(),
                symbol: _token.symbol(),
                decimals: _token.decimals(),
                balance: _userBalance,
                burned: _burnedBalance,
                approved: _tokenTransferAllowed
            });
            _tokens[burnableTokenIdx] = token; // Save burnable token data in array
        }
        tokens = _tokens; // Return burnable tokens
    }

    /**
     * @notice view method for overall burning statistics
     * @return veNFTBurned amount of STR burned via veNFTs
     * @return erc20Burned statistics of burnable ERC20 tokens
     */
    function burnStatistics()
        external
        view
        returns (uint256 veNFTBurned, Token[] memory erc20Burned)
    {
        Token[] memory _tokens = new Token[](
            validBurnableTokenAddresses.length
        );

        for (
            uint256 burnTokenIdx;
            burnTokenIdx < validBurnableTokenAddresses.length;
            burnTokenIdx++
        ) {
            IERC20MetadataUpgradeable _token = IERC20MetadataUpgradeable(validBurnableTokenAddresses[burnTokenIdx]);
            _tokens[burnTokenIdx] = Token({
                id: validBurnableTokenAddresses[burnTokenIdx],
                name: _token.name(),
                symbol: _token.symbol(),
                decimals: _token.decimals(),
                balance: _token.balanceOf(address(this)),
                burned: _token.balanceOf(address(this)),
                approved: true
            });
        }

        return (veNftBurnedAmountTotal, _tokens);
    }

    /***** ERC721 *****/
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        require(msg.sender == address(veNft)); // Only accept veNfts
        require(_unlocked == 2, "No direct transfers");
        return this.onERC721Received.selector;
    }
}
