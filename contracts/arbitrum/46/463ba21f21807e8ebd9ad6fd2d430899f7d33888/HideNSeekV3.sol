// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}



interface IStakeManager {
    function stakePABOnService(
        uint256 tokenId,
        address service,
        address owner
    ) external;

    function isStaked(uint256 tokenId, address service)
        external
        view
        returns (bool);

    function unstakePeekABoo(uint256 tokenId) external;

    function getServices() external view returns (address[] memory);

    function isService(address service) external view returns (bool);

    function initializeEnergy(uint256 tokenId) external;

    function claimEnergy(uint256 tokenId) external;

    function useEnergy(uint256 tokenId, uint256 amount) external;

    function ownerOf(uint256 tokenId) external returns (address);

    function tokensOf(address owner) external returns (uint256[] memory);
}



interface IHideNSeekV2 {
    struct GhostMapSession {
        bool active;
        uint256 tokenId;
        uint256 sessionId;
        uint256 difficulty;
        uint256 cost;
        uint256 balance;
        bytes32 commitment;
        address owner;
        address busterPlayer;
        uint256 numberOfBusters;
        uint256[3] busterTokenIds;
        int256[2][3] busterPositions;
        uint256 lockedTime;
        uint256 playedTime;
        bool won;
    }

    struct Session {
        uint256 tokenId;
        uint256 sessionId;
        address owner;
        address lockedBy;
    }

    function stakePeekABoo(uint256[] calldata tokenIds) external;

    function unstakePeekABoo(uint256[] calldata tokenIds) external;

    function claimGhostMaps(
        uint256 tokenId,
        uint256[] calldata sessionIds,
        int256[2][] calldata ghostPositions,
        uint256[] calldata nonces
    ) external;

    function playGameSession(uint256[] calldata bi, int256[2][] calldata bp)
        external;

    function getGhostMapSessionStats(uint256 tokenId, uint256 sessionId)
        external
        view
        returns (GhostMapSession memory);

    function getLockedSession() external returns (Session memory);

    function getTokenIdActiveSessions(uint256 tokenId)
        external
        view
        returns (uint256[] memory);

    function matchHistory(address owner)
        external
        view
        returns (GhostMapSession[] memory);

    function numberOfClaimableSessions(address owner)
        external
        view
        returns (uint256);

    function claimBusterSession(uint256 tokenId, uint256 sessionId) external;

    function createGhostMaps(uint256 tokenId, bytes32[] calldata commitments)
        external;

    function rescueSession(uint256 tokenId, uint256 sessionId) external;
}








contract HideNSeekBaseV2 {
    // reference to the peekaboo smart contract
    IPeekABoo public peekaboo;
    IBOO public boo;
    IStakeManager public sm;
    ILevel public level;
    address ACS;

    mapping(uint256 => mapping(uint256 => IHideNSeekV2.GhostMapSession))
        public TIDtoGMS;
    mapping(uint256 => uint256) public TIDtoNextSessionNumber;
    mapping(uint256 => uint256[]) public TIDtoActiveSessions;
    mapping(address => uint256[2][]) public ownerMatchHistory;
    mapping(address => IHideNSeekV2.Session[]) public claimableSessions;
    mapping(address => IHideNSeekV2.Session) lockedSessions;
    IHideNSeekV2.Session[] activeSessions;

    uint256[3] public GHOST_COSTS;
    uint256[3] public BUSTER_COSTS;
    uint256[2] public BUSTER_BONUS;

    event StakedPeekABoo(address from, uint256 tokenId);
    event UnstakedPeekABoo(address from, uint256 tokenId);
    event ClaimedGhostMap(uint256 tokenId, uint256 sessionId);
    event PlayedGame(address from, uint256 tokenId, uint256 sessionId);
    event GhostMapCreated(
        address indexed ghostPlayer,
        uint256 indexed tokenId,
        uint256 session
    );
    event GameComplete(
        address winner,
        address loser,
        uint256 indexed tokenId,
        uint256 indexed session,
        uint256 difficulty,
        uint256 winnerAmount,
        uint256 loserAmount
    );

    uint256[3] public ghostReceive;
}



// OpenZeppelin Contracts v4.4.1 (token/ERC721/IERC721.sol)





/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721Upgradeable is IERC165Upgradeable {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}


interface IPeekABoo is IERC721Upgradeable {
    struct PeekABooTraits {
        bool isGhost;
        uint256 background;
        uint256 back;
        uint256 bodyColor;
        uint256 hat;
        uint256 face;
        uint256 clothesOrHelmet;
        uint256 hands;
        uint64 ability;
        uint64 revealShape;
        uint64 tier;
        uint64 level;
    }

    struct GhostMap {
        uint256[10][10] grid;
        int256 gridSize;
        uint256 difficulty;
        bool initialized;
    }

    function devMint(address to, uint256[] memory types) external;

    function mint(uint256[] calldata types, bytes32[] memory proof) external;

    function publicMint(uint256[] calldata types) external payable;

    function getTokenTraits(uint256 tokenId)
        external
        view
        returns (PeekABooTraits memory);

    function setTokenTraits(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) external;

    function setMultipleTokenTraits(
        uint256 tokenId,
        uint256[] calldata traitTypes,
        uint256[] calldata traitIds
    ) external;

    function getGhostMapGridFromTokenId(uint256 tokenId)
        external
        view
        returns (GhostMap memory);

    function mintPhase2(
        uint256 tokenId,
        uint256[] memory types,
        uint256 amount,
        uint256 booAmount
    ) external;

    function incrementLevel(uint256 tokenId) external;

    function incrementTier(uint256 tokenId) external;

    function getPhase1Minted() external view returns (uint256 result);

    function getPhase2Minted() external view returns (uint256 result);

    function withdraw() external;
}






interface ILevel {
    function updateExp(
        uint256 tokenId,
        bool won,
        uint256 difficulty
    ) external;

    function expAmount(uint256 tokenId) external view returns (uint256);

    function isUnlocked(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) external returns (bool);

    function getUnlockedTraits(uint256 tokenId, uint256 traitType)
        external
        returns (uint256);
}




// OpenZeppelin Contracts (last updated v4.5.0) (proxy/utils/Initializable.sol)




// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)



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


/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To initialize the implementation contract, you can either invoke the
 * initializer manually, or you can include a constructor to automatically mark it as initialized when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() initializer {}
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        // If the contract is initializing we ignore whether _initialized is set in order to support multiple
        // inheritance patterns, but we only do this in the context of a constructor, because in other contexts the
        // contract may have been reentered.
        require(_initializing ? _isConstructor() : !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} modifier, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}


// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)




// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)




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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}



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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}












// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)



/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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
}


interface IBOO is IERC20Upgradeable {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function cap() external view returns (uint256);

    function setAllocationAddress(address fundingAddress, uint256 allocation) external;

    function removeAllocationAddress(address fundingAddress) external;
}


abstract contract HideNSeekGameLogicV3 is OwnableUpgradeable, HideNSeekBaseV2 {
    function playGame(
        uint256[] calldata busterIds,
        int256[2][] calldata busterPos,
        uint256 tokenId,
        uint256 sessionId
    ) internal {
        TIDtoGMS[tokenId][sessionId].busterPlayer = _msgSender();
        TIDtoGMS[tokenId][sessionId].numberOfBusters = busterIds.length;
        for (uint256 i = 0; i < busterIds.length; i++) {
            TIDtoGMS[tokenId][sessionId].busterTokenIds[i] = busterIds[i];
            TIDtoGMS[tokenId][sessionId].busterPositions[i] = busterPos[i];
        }
    }

    // Returns true if ghost wins, false if ghost loses
    function verifyGame(
        IHideNSeekV2.GhostMapSession memory gms,
        int256[2] calldata ghostPosition
    ) internal returns (bool) {
        IPeekABoo peekabooRef = peekaboo;

        for (uint256 i = 0; i < gms.numberOfBusters; i++) {
            // Ghost reveal logic
            if (
                doesRadiusReveal(
                    gms.busterPositions[i],
                    peekabooRef
                        .getTokenTraits(gms.busterTokenIds[i])
                        .revealShape,
                    gms.busterTokenIds[i],
                    ghostPosition
                ) ||
                (
                    gms.busterTokenIds.length == 1
                        ? doesAbilityReveal(
                            gms.busterPositions[i],
                            gms.busterTokenIds[i],
                            ghostPosition
                        )
                        : (
                            gms.busterTokenIds.length == 2
                                ? doesAbilityReveal(
                                    gms.busterPositions[i],
                                    gms.busterTokenIds[i],
                                    ghostPosition,
                                    gms.busterPositions[(i == 0) ? 1 : 0]
                                )
                                : doesAbilityReveal(
                                    gms.busterPositions[i],
                                    gms.busterTokenIds[i],
                                    ghostPosition,
                                    gms.busterPositions[(i == 0) ? 2 : 0],
                                    gms.busterPositions[(i == 1) ? 2 : 1]
                                )
                        )
                )
            ) {
                //Boo Generator Cashing
                // if (peekabooRef.getTokenTraits(gms.busterTokenIds[i]).ability == 6) {
                //     booRef.mint(gms.busterPlayer, 10 ether);
                // }

                return true;
            }
        }
        return false;
    }

    function doesRadiusReveal(
        int256[2] memory busterPosition,
        uint256 revealShape,
        uint256 busterId,
        int256[2] memory ghostPosition
    ) internal view returns (bool) {
        // NormalRevealShape
        if (revealShape == 0) {
            for (int256 i = -1; i <= 1; i++) {
                for (int256 j = -1; j <= 1; j++) {
                    if (
                        (ghostPosition[0] == busterPosition[0] + i &&
                            ghostPosition[1] == busterPosition[1] + j)
                    ) return true;
                }
            }
        }
        // PlusRevealShape
        else if (revealShape == 1) {
            for (int256 i = -2; i <= 2; i++) {
                if (
                    (ghostPosition[0] == busterPosition[0] &&
                        ghostPosition[1] == busterPosition[1] + i) ||
                    (ghostPosition[0] == busterPosition[0] + i &&
                        ghostPosition[1] == busterPosition[1])
                ) return true;
            }
        }
        // XRevealShape
        else if (revealShape == 2) {
            for (int256 i = -2; i <= 2; i++) {
                if (
                    ghostPosition[0] == busterPosition[0] + i &&
                    ghostPosition[1] == busterPosition[1] + i
                ) {
                    return true;
                }
            }
        }

        return false;
    }

    function doesAbilityReveal(
        int256[2] memory bp,
        uint256 busterId,
        int256[2] memory gp,
        int256[2] memory otherBuster1,
        int256[2] memory otherBuster2
    ) internal view returns (bool) {
        IPeekABoo peekabooRef = peekaboo;
        //LightBuster
        if (peekabooRef.getTokenTraits(busterId).ability == 1) {
            if (gp[0] == bp[0]) return true;
        }
        //HomeBound
        else if (peekabooRef.getTokenTraits(busterId).ability == 2) {
            if (
                ((bp[0] == otherBuster1[0]) && (bp[0] == gp[0])) || // Buster 1 on same row
                ((bp[0] == otherBuster2[0]) && (bp[0] == gp[0])) || // Buster 2 on same row
                ((bp[1] == otherBuster1[1]) && (bp[1] == gp[1])) || // Buster 1 on same column
                ((bp[1] == otherBuster2[1]) && (bp[1] == gp[1]))
            ) // Buster 2 on same column
            {
                return true;
            }
        }
        //GreenGoo
        else if (peekabooRef.getTokenTraits(busterId).ability == 3) {
            if (gp[1] == bp[1]) {
                return true;
            }
        }
        //StandUnited
        else if (peekabooRef.getTokenTraits(busterId).ability == 4) {
            if (
                isBusterAdjacent(bp, otherBuster1) ||
                isBusterAdjacent(bp, otherBuster2)
            ) {
                for (int256 i = -2; i <= 2; i++) {
                    for (int256 j = -2; i <= 2; i++) {
                        if ((gp[0] == bp[0] + i && gp[1] == bp[1] + j))
                            return true;
                    }
                }
            }
        }
        //HolyCross
        else if (peekabooRef.getTokenTraits(busterId).ability == 5) {
            if (gp[0] == bp[0] || gp[1] == bp[1]) {
                return true;
            }
        }

        return false;
    }

    function doesAbilityReveal(
        int256[2] memory busterPosition,
        uint256 busterId,
        int256[2] memory ghostPosition,
        int256[2] memory otherBuster1
    ) internal view returns (bool) {
        IPeekABoo peekabooRef = peekaboo;
        //LightBuster
        if (peekabooRef.getTokenTraits(busterId).ability == 1) {
            if (ghostPosition[0] == busterPosition[0]) return true;
        }
        //HomeBound
        else if (peekabooRef.getTokenTraits(busterId).ability == 2) {
            if (
                ((busterPosition[0] == otherBuster1[0]) &&
                    (busterPosition[0] == ghostPosition[0])) || // Buster 1 on same row
                ((busterPosition[1] == otherBuster1[1]) &&
                    (busterPosition[1] == ghostPosition[1]))
            ) // Buster 1 on same column
            {
                return true;
            }
        }
        //GreenGoo
        else if (peekabooRef.getTokenTraits(busterId).ability == 3) {
            if (ghostPosition[1] == busterPosition[1]) {
                return true;
            }
        }
        //StandUnited
        else if (peekabooRef.getTokenTraits(busterId).ability == 4) {
            if (isBusterAdjacent(busterPosition, otherBuster1)) {
                for (int256 i = -2; i <= 2; i++) {
                    for (int256 j = -2; i <= 2; i++) {
                        if (
                            (ghostPosition[0] == busterPosition[0] + i &&
                                ghostPosition[1] == busterPosition[1] + j)
                        ) return true;
                    }
                }
            }
        }
        //HolyCross
        else if (peekabooRef.getTokenTraits(busterId).ability == 5) {
            if (
                ghostPosition[0] == busterPosition[0] ||
                ghostPosition[1] == busterPosition[1]
            ) {
                return true;
            }
        }

        return false;
    }

    function doesAbilityReveal(
        int256[2] memory busterPosition,
        uint256 busterId,
        int256[2] memory ghostPosition
    ) internal view returns (bool) {
        IPeekABoo peekabooRef = peekaboo;
        //LightBuster
        if (peekabooRef.getTokenTraits(busterId).ability == 1) {
            if (ghostPosition[0] == busterPosition[0]) return true;
        }
        //GreenGoo
        else if (peekabooRef.getTokenTraits(busterId).ability == 3) {
            if (ghostPosition[1] == busterPosition[1]) {
                return true;
            }
        }
        //HolyCross
        else if (peekabooRef.getTokenTraits(busterId).ability == 5) {
            if (
                ghostPosition[0] == busterPosition[0] ||
                ghostPosition[1] == busterPosition[1]
            ) {
                return true;
            }
        }

        return false;
    }

    function isBusterAdjacent(int256[2] memory pos1, int256[2] memory pos2)
        internal
        pure
        returns (bool)
    {
        int256 difference = pos1[0] + pos1[1] - (pos2[0] + pos2[1]);
        return difference <= 1 && difference >= -1;
    }

    function verifyCommitment(
        uint256 tokenId,
        uint256 sessionId,
        int256[2] calldata ghostPosition,
        uint256 nonce
    ) internal view returns (bool) {
        return
            bytes32(
                keccak256(
                    abi.encodePacked(
                        tokenId,
                        ghostPosition[0],
                        ghostPosition[1],
                        nonce
                    )
                )
            ) == TIDtoGMS[tokenId][sessionId].commitment;
    }

    function hasEnoughBooToFund(
        uint256[] calldata booFundingAmount,
        address sender
    ) internal view returns (bool) {
        uint256 totalBooFundingAmount;
        for (uint256 i = 0; i < booFundingAmount.length; i++) {
            totalBooFundingAmount += booFundingAmount[i];
        }
        return boo.balanceOf(sender) >= totalBooFundingAmount;
    }

    function isNotInBound(uint256 tokenId, int256[2] calldata position)
        internal
        view
        returns (bool)
    {
        IPeekABoo.GhostMap memory ghostMap = peekaboo
            .getGhostMapGridFromTokenId(tokenId);
        if (
            ghostMap.grid[uint256(position[1])][uint256(position[0])] == 1 ||
            position[0] < 0 ||
            position[0] > ghostMap.gridSize - 1 ||
            position[1] < 0 ||
            position[1] > ghostMap.gridSize - 1
        ) {
            return true;
        }
        return false;
    }

    function claimGhostMap(
        uint256 tokenId,
        uint256 sessionId,
        int256[2] calldata ghostPosition,
        uint256 nonce
    ) internal {
        IBOO booRef = boo;
        IHideNSeekV2.GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];
        uint256 difficulty = gms.difficulty;
        require(gms.active, "Session no longer active");
        require(
            gms.numberOfBusters > 0 && gms.busterPlayer != address(0),
            "No one has played yet"
        );
        bool overTime = block.timestamp - 1 days >= gms.lockedTime;
        bool notInbound = isNotInBound(tokenId, ghostPosition);

        if (overTime) {
            updateExp(gms, true, false);
            booRef.transfer(gms.owner, gms.balance);
            emit GameComplete(
                gms.owner,
                gms.busterPlayer,
                tokenId,
                sessionId,
                difficulty,
                gms.balance,
                0
            );
            TIDtoGMS[tokenId][sessionId].won = true;
        }

        if (!overTime) {
            require(
                verifyCommitment(tokenId, sessionId, ghostPosition, nonce),
                "Commitment incorrect, please do not cheat"
            );
            if (notInbound) {
                updateExp(gms, false, true);
                booRef.transfer(gms.busterPlayer, gms.balance);
                emit GameComplete(
                    gms.busterPlayer,
                    gms.owner,
                    tokenId,
                    sessionId,
                    difficulty,
                    gms.balance,
                    0
                );
            }
        }

        uint256 busterReceive;
        if (!overTime && !notInbound) {
            if (verifyGame(gms, ghostPosition)) {
                busterReceive =
                    gms.balance -
                    ghostReceive[gms.numberOfBusters - 1];
                booRef.transfer(gms.busterPlayer, busterReceive);
                booRef.transfer(
                    gms.owner,
                    ghostReceive[gms.numberOfBusters - 1]
                );
                if (gms.numberOfBusters == 1) {
                    booRef.mint(gms.busterPlayer, BUSTER_BONUS[1]);
                } else if (gms.numberOfBusters == 2) {
                    booRef.mint(gms.busterPlayer, BUSTER_BONUS[0]);
                }

                updateExp(gms, false, true);
                emit GameComplete(
                    gms.busterPlayer,
                    gms.owner,
                    tokenId,
                    sessionId,
                    difficulty,
                    busterReceive,
                    ghostReceive[gms.numberOfBusters - 1]
                );
            } else {
                booRef.transfer(gms.owner, gms.balance);

                updateExp(gms, true, false);
                emit GameComplete(
                    gms.owner,
                    gms.busterPlayer,
                    tokenId,
                    sessionId,
                    difficulty,
                    gms.balance,
                    0
                );
                TIDtoGMS[tokenId][sessionId].won = true;
            }
        }
        clearMap(tokenId, sessionId, gms.owner, gms.busterPlayer);
    }

    function pseudoRandom(address sender) internal returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        sender,
                        tx.gasprice,
                        block.timestamp,
                        activeSessions.length,
                        sender
                    )
                )
            );
    }

    function removeActiveGhostMap(uint256 tokenId, uint256 sessionId) internal {
        for (uint256 i = 0; i < activeSessions.length; i++) {
            if (
                activeSessions[i].tokenId == tokenId &&
                activeSessions[i].sessionId == sessionId
            ) {
                activeSessions[i] = activeSessions[activeSessions.length - 1];
                activeSessions.pop();
                break;
            }
        }
        for (uint256 i = 0; i < TIDtoActiveSessions[tokenId].length; i++) {
            if (TIDtoActiveSessions[tokenId][i] == sessionId) {
                TIDtoActiveSessions[tokenId][i] = TIDtoActiveSessions[tokenId][
                    TIDtoActiveSessions[tokenId].length - 1
                ];
                TIDtoActiveSessions[tokenId].pop();
                return;
            }
        }
    }

    function removeClaimableSession(
        address owner,
        uint256 tokenId,
        uint256 sessionId
    ) internal {
        uint256 _len = claimableSessions[owner].length;
        for (uint256 i = 0; i < _len; i++) {
            if (
                claimableSessions[owner][i].tokenId == tokenId &&
                claimableSessions[owner][i].sessionId == sessionId
            ) {
                claimableSessions[owner][i] = claimableSessions[owner][
                    _len - 1
                ];
                claimableSessions[owner].pop();
                return;
            }
        }
    }

    function notSamePosition(int256[2] calldata pos1, int256[2] calldata pos2)
        internal
        pure
        returns (bool)
    {
        return !(pos1[0] == pos2[0] && pos1[1] == pos2[1]);
    }

    function clearMap(
        uint256 tokenId,
        uint256 sessionId,
        address gp,
        address bp
    ) internal {
        TIDtoGMS[tokenId][sessionId].balance = 0;
        TIDtoGMS[tokenId][sessionId].active = false;
        ownerMatchHistory[gp].push([tokenId, sessionId]);
        ownerMatchHistory[bp].push([tokenId, sessionId]);

        removeClaimableSession(gp, tokenId, sessionId);
        removeClaimableSession(bp, tokenId, sessionId);
    }

    function createCommitment(
        uint256 tId,
        int256[2] calldata gp,
        uint256 nonce
    ) public pure returns (bytes32) {
        return bytes32(keccak256(abi.encodePacked(tId, gp[0], gp[1], nonce)));
    }

    function playRequirements(
        uint256[] calldata bi,
        int256[2][] calldata bp,
        uint256 tokenId
    ) internal {
        IStakeManager smRef = sm;
        IPeekABoo peekabooRef = peekaboo;

        require(bi.length == bp.length, "Incorrect lengths");
        require(
            bi.length <= 3 && bi.length > 0,
            "Can only play with up to 3 busters"
        );

        require(
            smRef.ownerOf(bi[0]) == _msgSender(),
            "Not staked or not your buster"
        );
        require(
            !peekabooRef.getTokenTraits(bi[0]).isGhost,
            "You can't play with a ghost"
        );
        require(!isNotInBound(tokenId, bp[0]), "buster1 not inbound");

        if (bi.length == 2) {
            require(
                smRef.ownerOf(bi[1]) == _msgSender(),
                "Not staked or not your buster"
            );
            require(
                !peekabooRef.getTokenTraits(bi[1]).isGhost,
                "You can't play with a ghost"
            );
            require(
                notSamePosition(bp[0], bp[1]),
                "buster1 pos cannot be same as buster2"
            );
            require(!isNotInBound(tokenId, bp[1]), "buster2 not inbound");
        } else if (bi.length == 3) {
            require(
                smRef.ownerOf(bi[1]) == _msgSender() &&
                    smRef.ownerOf(bi[2]) == _msgSender(),
                "Not staked or not your buster"
            );
            require(
                !peekabooRef.getTokenTraits(bi[1]).isGhost &&
                    !peekabooRef.getTokenTraits(bi[2]).isGhost,
                "You can't play with a ghost"
            );

            require(
                notSamePosition(bp[0], bp[1]) &&
                    notSamePosition(bp[0], bp[2]) &&
                    notSamePosition(bp[1], bp[2]),
                "buster pos cannot be same"
            );
            require(!isNotInBound(tokenId, bp[1]), "buster2 not inbound");
            require(!isNotInBound(tokenId, bp[2]), "buster3 not inbound");
        }
    }

    function updateExp(
        IHideNSeekV2.GhostMapSession memory gms,
        bool ghostStatus,
        bool busterStatus
    ) internal {
        level.updateExp(gms.tokenId, ghostStatus, gms.difficulty);
        for (uint256 i = 0; i < gms.numberOfBusters; i++) {
            level.updateExp(
                gms.busterTokenIds[i],
                busterStatus,
                gms.difficulty
            );
        }
    }

    function setPeekABoo(address _peekaboo) external onlyOwner {
        peekaboo = IPeekABoo(_peekaboo);
    }

    function setBOO(address _boo) external onlyOwner {
        boo = IBOO(_boo);
    }

    function setStakeManager(address _sm) external onlyOwner {
        sm = IStakeManager(_sm);
    }

    function setLevel(address _level) external onlyOwner {
        level = ILevel(_level);
    }

    function setGhostReceive(uint256[3] memory _ghostReceive) external {
        ghostReceive = _ghostReceive;
    }

    function setAutoClaimServer(address autoClaimAddress) external onlyOwner {
        ACS = autoClaimAddress;
    }

    function setGhostCost(uint256[3] memory _GHOST_COST) external onlyOwner {
        GHOST_COSTS = _GHOST_COST;
    }

    function setBusterCost(uint256[3] memory _BUSTER_COST) external onlyOwner {
        BUSTER_COSTS = _BUSTER_COST;
    }

    function setBonus(uint256[2] memory _BONUS) external onlyOwner {
        BUSTER_BONUS = _BONUS;
    }

    function adminTransfer(address to, uint256 amount) external onlyOwner {
        boo.transfer(to, amount);
    }
}






contract HideNSeekV3 is Initializable, IHideNSeekV2, HideNSeekGameLogicV3 {
    function initialize() public initializer {
        __Ownable_init();
        GHOST_COSTS = [20 ether, 30 ether, 40 ether];
        BUSTER_COSTS = [10 ether, 20 ether, 30 ether];
        BUSTER_BONUS = [5 ether, 10 ether];
        ghostReceive = [0 ether, 5 ether, 10 ether];
    }

    modifier onlyStakedOwner(uint256 tId) {
        require(
            sm.isStaked(tId, address(this)) && sm.ownerOf(tId) == _msgSender(),
            "not staked or not owner"
        );
        _;
    }

    function stakePeekABoo(uint256[] calldata tokenIds) external {
        IStakeManager smRef = sm;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            smRef.stakePABOnService(tokenIds[i], address(this), _msgSender());
        }
    }

    function unstakePeekABoo(uint256[] calldata tokenIds) external {
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;
        uint256 asId = 0;
        uint256 len = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                smRef.ownerOf(tokenIds[i]) == _msgSender(),
                "Not your token."
            );
            smRef.unstakePeekABoo(tokenIds[i]);
            if (peekabooRef.getTokenTraits(tokenIds[i]).isGhost) {
                len = TIDtoActiveSessions[tokenIds[i]].length;
                for (uint256 j = 0; j < len; j++) {
                    asId = TIDtoActiveSessions[tokenIds[i]][j];
                    removeActiveGhostMap(tokenIds[i], asId);
                    boo.transfer(
                        TIDtoGMS[tokenIds[i]][asId].owner,
                        TIDtoGMS[tokenIds[i]][asId].balance
                    );
                    TIDtoGMS[tokenIds[i]][asId].balance = 0;
                    TIDtoGMS[tokenIds[i]][asId].active = false;
                }
            }
        }
    }

    function createGhostMaps(uint256 tId, bytes32[] calldata cmm)
        external
        onlyStakedOwner(tId)
    {
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;

        require(peekabooRef.getTokenTraits(tId).isGhost, "Not a ghost");
        require(
            peekabooRef.getGhostMapGridFromTokenId(tId).initialized,
            "Ghostmap is not initialized"
        );

        smRef.claimEnergy(tId);
        smRef.useEnergy(tId, cmm.length);

        uint256 difficulty = peekabooRef
            .getGhostMapGridFromTokenId(tId)
            .difficulty;
        uint256 cost = GHOST_COSTS[difficulty];
        uint256 sId;
        for (uint256 i = 0; i < cmm.length; i++) {
            sId = TIDtoNextSessionNumber[tId];
            TIDtoGMS[tId][sId].active = true;
            TIDtoGMS[tId][sId].tokenId = tId;
            TIDtoGMS[tId][sId].sessionId = sId;
            TIDtoGMS[tId][sId].difficulty = difficulty;
            TIDtoGMS[tId][sId].cost = cost;
            TIDtoGMS[tId][sId].balance = cost;
            TIDtoGMS[tId][sId].commitment = cmm[i];
            TIDtoGMS[tId][sId].owner = _msgSender();
            TIDtoNextSessionNumber[tId] = sId + 1;
            TIDtoActiveSessions[tId].push(sId);
            activeSessions.push(Session(tId, sId, _msgSender(), address(0x0)));
            emit GhostMapCreated(msg.sender, tId, sId);
        }
        boo.transferFrom(msg.sender, address(this), cost * cmm.length);
    }

    function claimGhostMaps(
        uint256 tId,
        uint256[] calldata sId,
        int256[2][] calldata gps,
        uint256[] calldata nonces
    ) external onlyStakedOwner(tId) {
        require(
            sId.length == nonces.length && sId.length == gps.length,
            "Incorrect lengths"
        );
        if (_msgSender() != ACS)
            for (uint256 i = 0; i < sId.length; i++) {
                claimGhostMap(tId, sId[i], gps[i], nonces[i]);
            }
    }

    function rescueSession(uint256 tokenId, uint256 sessionId)
        external
        onlyOwner
    {
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];

        boo.transfer(gms.owner, gms.cost);
        boo.transfer(gms.busterPlayer, gms.balance - gms.cost);
        clearMap(tokenId, sessionId, gms.owner, gms.busterPlayer);
    }

    function claimBusterSession(uint256 tokenId, uint256 sessionId) external {
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];
        require(gms.active, "Session no longer active");
        require(gms.busterPlayer == _msgSender(), "must be the buster player");
        require(
            block.timestamp - 1 days >= gms.playedTime,
            "ghost player has time"
        );

        updateExp(gms, false, true);
        boo.transfer(gms.busterPlayer, gms.balance);
        clearMap(tokenId, sessionId, gms.owner, gms.busterPlayer);
    }

    function generateLockedSession() external {
        require(
            lockedSessions[_msgSender()].lockedBy == address(0x0),
            "Already locked a session"
        );
        uint256 index = pseudoRandom(_msgSender()) % activeSessions.length;
        uint256 count = 0;
        while (activeSessions[index].owner == _msgSender()) {
            require(count < 5, "Preventing infinite loop");
            index =
                (pseudoRandom(_msgSender()) + index) %
                activeSessions.length;
            count++;
        }
        activeSessions[index].lockedBy = _msgSender();
        Session memory session = activeSessions[index];
        GhostMapSession memory gms = TIDtoGMS[session.tokenId][
            session.sessionId
        ];

        boo.transferFrom(
            _msgSender(),
            address(this),
            BUSTER_COSTS[gms.difficulty]
        );
        TIDtoGMS[session.tokenId][session.sessionId].balance += BUSTER_COSTS[
            gms.difficulty
        ];
        lockedSessions[_msgSender()] = session;
        TIDtoGMS[session.tokenId][session.sessionId].lockedTime = block
            .timestamp;
        removeActiveGhostMap(session.tokenId, session.sessionId);
    }

    function playGameSession(uint256[] calldata bi, int256[2][] calldata bp)
        external
    {
        IStakeManager smRef = sm;
        require(
            lockedSessions[_msgSender()].lockedBy != address(0x0),
            "You have not locked in a session yet"
        );
        uint256 tokenId = lockedSessions[_msgSender()].tokenId;
        uint256 sessionId = lockedSessions[_msgSender()].sessionId;
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];

        for (uint256 i = 0; i < bi.length; i++) {
            smRef.claimEnergy(bi[i]);
            smRef.useEnergy(bi[i], 1);
        }

        playRequirements(bi, bp, tokenId);
        playGame(bi, bp, tokenId, sessionId);
        TIDtoGMS[tokenId][sessionId].playedTime = block.timestamp;
        emit PlayedGame(_msgSender(), tokenId, sessionId);
        claimableSessions[gms.owner].push(lockedSessions[_msgSender()]);
        claimableSessions[_msgSender()].push(lockedSessions[_msgSender()]);
        delete lockedSessions[_msgSender()];
    }

    //Admin Access
    function getLockedSession() external view returns (Session memory) {
        return lockedSessions[_msgSender()];
    }

    // Public READ Game Method
    function getGhostMapSessionStats(uint256 tokenId, uint256 sessionId)
        external
        view
        returns (GhostMapSession memory)
    {
        return TIDtoGMS[tokenId][sessionId];
    }

    function getTokenIdActiveSessions(uint256 tokenId)
        external
        view
        returns (uint256[] memory)
    {
        return TIDtoActiveSessions[tokenId];
    }

    function matchHistory(address owner)
        external
        view
        returns (GhostMapSession[] memory)
    {
        uint256[2][] memory mh = ownerMatchHistory[owner];
        GhostMapSession[] memory hnsHistory = new GhostMapSession[](mh.length);

        for (uint256 i = 0; i < mh.length; i++) {
            hnsHistory[i] = TIDtoGMS[mh[i][0]][mh[i][1]];
        }
        return hnsHistory;
    }

    function numberOfClaimableSessions(address owner)
        external
        view
        returns (uint256)
    {
        return claimableSessions[owner].length;
    }
}