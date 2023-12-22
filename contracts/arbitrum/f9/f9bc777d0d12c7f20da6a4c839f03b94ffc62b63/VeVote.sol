// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts/utils/introspection/IERC165.sol@v4.9.2
// License-Identifier: MIT
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
interface IERC165 {
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

// File @openzeppelin/contracts/token/ERC721/IERC721.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
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
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
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
    function transferFrom(address from, address to, uint256 tokenId) external;

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
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

// File contracts/interfaces/IVeTTNFT721Upgraded.sol
// License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * @title VeTT ERC721代币新增方法
 */
interface IVeTTNFT721Upgraded is IERC721 {
    /**
     * @notice 设置代币信息，仅Owner可调用
     * @param name 代币名称
     * @param symbol 代币符号
     */
    function setTokenInfo(
        string calldata name,
        string calldata symbol
    ) external;

    function lockVeAmount(
        uint256 tokenId,
        uint256 lockId,
        uint256 amount
    ) external;

    function unlockVeAmount(
        uint256 tokenId,
        uint256 lockId,
        uint256 amount
    ) external;

    /**
     * @notice 批量获取可用VeAmount
     * @param tokenIds 代币ID数组
     * @return 可用VeAmount数组
     */
    function getAvailableVeAmounts(
        uint256[] calldata tokenIds
    ) external view returns (uint256[] memory);

    /**
     * @notice 批量获取已锁定VeAmount
     * @param tokenIds 代币ID数组
     * @return 已锁定VeAmount数组
     */
    function getLockedVeAmounts(
        uint256[] calldata tokenIds
    ) external view returns (uint256[] memory);

    /**
     * @notice 批量获取代币中VeAmount总量
     * @param tokenIds 代币ID数组
     * @return VeAmount总量数组
     */
    function getTotalVeAmounts(
        uint256[] calldata tokenIds
    ) external view returns (uint256[] memory);

    /**
     * @notice VeAmount锁定权限地址设置事件
     * @param addr 地址
     * @param state VeAmount锁定权限
     */
    event LockerSet(address indexed addr, bool indexed state);

    /**
     * @notice VeAmount锁定事件
     * @param locker 执行锁定的合约地址，目前应为DAOVote或VeVote之一
     * @param tokenId 代币ID
     * @param lockId 相关的锁定操作ID，目前设为对应locker合约中的VoteId
     * @param amount 锁定数量
     * @param locked 当前Ve总锁定数量
     * @param available 当前Ve剩余可用数量
     */
    event VeAmountLocked(
        address indexed locker,
        uint256 indexed tokenId,
        uint256 indexed lockId,
        uint256 amount,
        uint256 locked,
        uint256 available
    );

    /**
     * @notice VeAmount解锁事件
     * @param locker 执行锁定的合约地址，目前应为DAOVote或VeVote之一
     * @param tokenId 代币ID
     * @param lockId 相关的锁定操作ID，目前设为对应locker合约中的VoteId
     * @param amount 解锁数量
     * @param locked 当前Ve总锁定数量
     * @param available 当前Ve剩余可用数量
     */
    event VeAmountUnlocked(
        address indexed locker,
        uint256 indexed tokenId,
        uint256 indexed lockId,
        uint256 amount,
        uint256 locked,
        uint256 available
    );
}

// File contracts/interfaces/IVeVote.sol
// License-Identifier: MIT

pragma solidity =0.8.18;

/**
 * @title 提案投票接口
 */
interface IVeVote {
    struct Proposal {
        uint256 proposalId;
        address creator;
        bytes32 proposalHash;
        uint256 startTime;
        uint256 endTime;
        uint256 createTime;
        uint8 adminReview;
    }

    struct Vote {
        uint256 voteId;
        address voter;
        uint256[] tokenIds;
        uint256[] veAmounts;
        uint256 proposalId;
        uint8 voteType;
        uint8 choice;
        uint256 voteAmount;
        bool released;
        uint256 voteTime;
    }

    /**
     * @notice 创建提案
     * @param proposalId 提案ID
     * @param proposalHash 提案Hash
     * @param startTime 投票开始时间
     * @param endTime 投票结束时间
     */
    function createProposal(
        uint256 proposalId,
        bytes32 proposalHash,
        uint256 startTime,
        uint256 endTime
    ) external;

    /**
     * @notice 管理员创建提案，仅operator地址可以调用
     * @param creator 提案创建人
     * @param proposalId 提案ID
     * @param proposalHash 提案Hash
     * @param startTime 投票开始时间
     * @param endTime 投票结束时间
     */
    function adminCreateProposal(
        address creator,
        uint256 proposalId,
        bytes32 proposalHash,
        uint256 startTime,
        uint256 endTime
    ) external;

    /**
     * @notice 管理员审核提案，仅operator地址可以调用
     * @param proposalId 提案ID
     * @param state 审核状态: 0=默认; 1=通过; 2=拒绝
     */
    function adminReview(uint256 proposalId, uint8 state) external;

    /**
     * @notice 提案审核投票，仅委员会成员可调用
     * @param tokenIds VeTT ERC721代币ID数组
     * @param veAmounts 花费代币veAmount数组
     * @param proposalId 提案ID
     * @param choice 审核意见: 1=通过; 2=拒绝
     */
    function reviewVote(
        uint256[] calldata tokenIds,
        uint256[] calldata veAmounts,
        uint256 proposalId,
        uint8 choice
    ) external;

    /**
     * @notice 提案投票
     * @param tokenIds VeTT ERC721代币ID数组
     * @param veAmounts 花费代币veAmount数组
     * @param proposalId 提案ID
     * @param choice 选择: 1=赞成; 2=反对; 3=弃权
     */
    function vote(
        uint256[] calldata tokenIds,
        uint256[] calldata veAmounts,
        uint256 proposalId,
        uint8 choice
    ) external;

    /**
     * @notice 批量赎回投票VeTT
     * @param voteIds 赎回VeTT的投票ID数组
     */
    function releaseVotes(uint256[] calldata voteIds) external;

    /**
     * @notice 提案创建事件
     * @param creator 提案创建人
     * @param proposalId 提案ID
     * @param startTime 投票开始时间
     * @param endTime 投票结束时间
     */
    event ProposalCreated(
        address indexed creator,
        uint256 proposalId,
        uint256 startTime,
        uint256 endTime
    );

    /**
     * @notice 提案审核投票事件
     * @param voteId 投票ID
     * @param voter 投票人
     * @param proposalId 提案ID
     * @param choice 审核意见: 1=通过; 2=拒绝
     * @param veAmount 票数
     */
    event ReviewVoted(
        uint256 voteId,
        address indexed voter,
        uint256 indexed proposalId,
        uint8 indexed choice,
        uint256 veAmount
    );

    /**
     * @notice 提案投票事件
     * @param voteId 投票ID
     * @param voter 投票人
     * @param proposalId 提案ID
     * @param choice 选择: 1=赞成; 2=反对; 3=弃权
     * @param veAmount 票数
     */
    event VeVoted(
        uint256 voteId,
        address indexed voter,
        uint256 indexed proposalId,
        uint8 indexed choice,
        uint256 veAmount
    );

    /**
     * @notice 赎回事件
     * @param voteId 投票ID
     */
    event VeVoteReleased(uint256 voteId);

    /**
     * @notice 管理员审核提案事件
     * @param proposalId 提案ID
     * @param state 审核状态: 0=默认; 1=通过; 2=拒绝
     */
    event AdminReviewed(uint256 indexed proposalId, uint8 indexed state);
}

// File contracts/interfaces/IDAOVote.sol
// License-Identifier: MIT

pragma solidity =0.8.18;

/**
 * @title 委员会选举接口
 */
interface IDAOVote {
    struct Vote {
        uint256 voteId;
        address voter;
        uint256[] tokenIds;
        uint256[] veAmounts;
        address candidate;
        uint256 round;
        uint256 voteAmount;
        bool released;
        uint256 voteTime;
    }
    
    /**
     * @notice 选举投票
     * @param tokenIds VeTT ERC721代币ID数组
     * @param veAmounts 花费代币veAmount数组
     * @param candidate 候选人地址
     */
    function vote(
        uint256[] calldata tokenIds,
        uint256[] calldata veAmounts,
        address candidate
    ) external;

    /**
     * @notice 批量赎回投票VeTT
     * @param voteIds 赎回VeTT的投票ID数组
     */
    function releaseVotes(uint256[] calldata voteIds) external;

    function isDAOMember(address addr) external view returns (bool);

    /**
     * @notice 投票事件
     * @param voteId 投票ID
     * @param voter 投票人
     * @param candidate 候选人
     * @param round 委员会轮次
     * @param veAmount 票数
     */
    event DAOVoted(
        uint256 voteId,
        address indexed voter,
        address indexed candidate,
        uint256 indexed round,
        uint256 veAmount
    );

    /**
     * @notice 赎回事件
     * @param voteId 投票ID
     */
    event DAOVoteReleased(uint256 voteId);

    /**
     * @notice 委员会换届设置事件
     * @param round 委员会届数
     * @param members 委员会成员数组
     */
    event DAOSet(uint256 indexed round, address[] members);

    /**
     * @notice 可投票状态设置事件
     * @param state 可投票状态
     */
    event CanVoteSet(bool indexed state);
}

// File @openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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
     *
     * Furthermore, `isContract` will also return true if the target contract within
     * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
     * which only has an effect at the end of a transaction.
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
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.0/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
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
        (bool success, bytes memory returndata) = target.delegatecall(data);
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

// File @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

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
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// File @openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/extensions/IERC20Permit.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20PermitUpgradeable {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// File @openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;



/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, oldAllowance + value));
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, oldAllowance - value));
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Compatible with tokens that require the approval to be set to
     * 0 before setting it to a non-zero value.
     */
    function forceApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(token.approve.selector, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Use a ERC-2612 signature to set the `owner` approval toward `spender` on `token`.
     * Revert on invalid signature.
     */
    function safePermit(
        IERC20PermitUpgradeable token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20Upgradeable token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return
            success && (returndata.length == 0 || abi.decode(returndata, (bool))) && AddressUpgradeable.isContract(address(token));
    }
}

// File contracts/storages/VeVoteStorage.sol
// License-Identifier: MIT

pragma solidity 0.8.18;



abstract contract VeVoteStorage is IVeVote {
    IVeTTNFT721Upgraded public veTT;
    IERC20Upgradeable public tt;
    IDAOVote public daoVote;

    uint256 public reviewPeriod;
    uint256 public proposalCost;
    address public wallet;

    mapping(uint256 => Proposal) public proposals;
    uint256[] public proposalIds;
    mapping(uint256 => Vote) public votes;
    uint256 public voteCount;
    mapping(uint256 => mapping(uint8 => uint256)) public reviewVotedAmounts;
    mapping(uint256 => mapping(uint8 => uint256)) public votedAmounts;
    mapping(address => uint256[]) public voterVoted;
    mapping(address => mapping(uint256 => mapping(uint8 => uint256)))
        public voterReviewVotedAmounts;
    mapping(address => mapping(uint256 => mapping(uint8 => uint256)))
        public voterVotedAmounts;
}

// File @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.2;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
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
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that functions marked with `initializer` can be nested in the context of a
     * constructor.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: setting the version to 255 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

// File @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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

// File @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable.sol)

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
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
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

// File contracts/utils/WithOperator.sol
// License-Identifier: MIT

pragma solidity 0.8.18;

abstract contract WithOperator is OwnableUpgradeable {
    address[] private _operators;

    event OperatorSet(address[] previousOperators, address[] newOperators);

    function operator(uint256 index) public view virtual returns (address) {
        return _operators[index];
    }

    function operators() public view virtual returns (address[] memory) {
        return _operators;
    }

    function operatorCount() public view virtual returns (uint256) {
        return _operators.length;
    }

    modifier onlyOperator() {
        for (uint256 i = 0; i < _operators.length; i++) {
            if (_operators[i] == _msgSender()) {
                _;
                return;
            }
        }

        revert("WithOperator: caller is not the operator");
    }

    modifier onlyOwnerOrOperator() {
        if (owner() == _msgSender()) {
            _;
            return;
        }

        for (uint256 i = 0; i < _operators.length; i++) {
            if (_operators[i] == _msgSender()) {
                _;
                return;
            }
        }

        revert("WithOperator: caller is not the owner nor the operator");
    }

    function setOperator(
        address[] memory newOperators
    ) public virtual onlyOwner {
        _setOperator(newOperators);
    }

    function _setOperator(address[] memory newOperators) internal virtual {
        address[] memory oldOperators = _operators;
        _operators = newOperators;

        emit OperatorSet(oldOperators, newOperators);
    }
}

// File contracts/utils/ERC2771ContextUpgradeable.sol
// License-Identifier: MIT

pragma solidity ^0.8.9;


/**
 * @dev Context variant with ERC2771 support.
 */
abstract contract ERC2771ContextUpgradeable is
    Initializable,
    ContextUpgradeable
{
    address private _trustedForwarder;

    function _setTrustedForwarder(address trustedForwarder) internal {
        _trustedForwarder = trustedForwarder;
    }

    function isTrustedForwarder(
        address forwarder
    ) public view virtual returns (bool) {
        return forwarder == _trustedForwarder;
    }

    modifier onlyTrustedForwarder() {
        require(
            _msgSender() == _trustedForwarder,
            "ERC2771Context: caller is not the TrustedForwarder"
        );
        _;
    }

    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData()
        internal
        view
        virtual
        override
        returns (bytes calldata)
    {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

// File @openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

pragma solidity ^0.8.0;


/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// File @openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol@v4.9.2
// License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

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
abstract contract ReentrancyGuardUpgradeable is Initializable {
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

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
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
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// File contracts/VeVote.sol
// License-Identifier: MIT

pragma solidity 0.8.18;





contract VeVote is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VeVoteStorage,
    WithOperator,
    ERC2771ContextUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    modifier onlyDAOMember() {
        require(
            daoVote.isDAOMember(_msgSender()),
            "VeVote: caller is not DAO member"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        revert();
    }

    fallback() external {
        revert();
    }

    function initialize(
        address veTT_,
        address tt_,
        address daoVote_,
        uint256 reviewPeriod_,
        uint256 proposalCost_,
        address wallet_,
        address[] calldata operators_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        veTT = IVeTTNFT721Upgraded(veTT_);
        tt = IERC20Upgradeable(tt_);
        daoVote = IDAOVote(daoVote_);
        reviewPeriod = reviewPeriod_;
        proposalCost = proposalCost_;
        wallet = wallet_;

        _setOperator(operators_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setTrustedForwarder(address trustedForwarder) external onlyOwner {
        _setTrustedForwarder(trustedForwarder);
    }

    function setVeTT(address veTT_) external onlyOwner {
        veTT = IVeTTNFT721Upgraded(veTT_);
    }

    function setTT(address tt_) external onlyOwner {
        tt = IERC20Upgradeable(tt_);
    }

    function setDAOVote(address daoVote_) external onlyOwner {
        daoVote = IDAOVote(daoVote_);
    }

    function setReviewPeriod(uint256 reviewPeriod_) external onlyOwner {
        reviewPeriod = reviewPeriod_;
    }

    function setProposalCost(uint256 proposalCost_) external onlyOwner {
        proposalCost = proposalCost_;
    }

    function setWallet(address wallet_) external onlyOwner {
        wallet = wallet_;
    }

    function createProposal(
        uint256 proposalId,
        bytes32 proposalHash,
        uint256 startTime,
        uint256 endTime
    ) external nonReentrant whenNotPaused {
        require(
            proposals[proposalId].proposalId == 0,
            "VeVote: proposal id already in use"
        );
        require(
            startTime < endTime && startTime > block.timestamp,
            "VeVote: invalid proposal params"
        );

        address creator = _msgSender();
        tt.safeTransferFrom(creator, wallet, proposalCost);

        proposalIds.push(proposalId);
        proposals[proposalId].proposalId = proposalId;
        proposals[proposalId].creator = creator;
        proposals[proposalId].proposalHash = proposalHash;
        proposals[proposalId].startTime = startTime;
        proposals[proposalId].endTime = endTime;
        proposals[proposalId].createTime = block.timestamp;

        emit ProposalCreated(creator, proposalId, startTime, endTime);
    }

    function adminCreateProposal(
        address creator,
        uint256 proposalId,
        bytes32 proposalHash,
        uint256 startTime,
        uint256 endTime
    ) external whenNotPaused onlyOwnerOrOperator {
        require(
            proposals[proposalId].proposalId == 0,
            "VeVote: proposal id already in use"
        );
        require(
            startTime < endTime && startTime > block.timestamp,
            "VeVote: invalid proposal params"
        );

        proposalIds.push(proposalId);
        proposals[proposalId].proposalId = proposalId;
        proposals[proposalId].creator = creator;
        proposals[proposalId].proposalHash = proposalHash;
        proposals[proposalId].startTime = startTime;
        proposals[proposalId].endTime = endTime;
        proposals[proposalId].createTime = block.timestamp;
        proposals[proposalId].adminReview = 1;

        emit ProposalCreated(creator, proposalId, startTime, endTime);
        emit AdminReviewed(proposalId, 1);
    }

    function adminReview(
        uint256 proposalId,
        uint8 state
    ) external whenNotPaused onlyOwnerOrOperator {
        require(
            proposals[proposalId].proposalId == proposalId,
            "VeVote: invalid proposal"
        );

        proposals[proposalId].adminReview = state;

        emit AdminReviewed(proposalId, state);
    }

    function reviewVote(
        uint256[] calldata tokenIds,
        uint256[] calldata veAmounts,
        uint256 proposalId,
        uint8 choice
    ) external nonReentrant whenNotPaused onlyDAOMember {
        require(
            proposals[proposalId].proposalId == proposalId,
            "VeVote: invalid proposal"
        );
        require(
            proposals[proposalId].createTime + reviewPeriod >= block.timestamp,
            "VeVote: not in review period"
        );
        require(tokenIds.length == veAmounts.length, "VeVote: invalid params");

        voteCount++;
        address voter = _msgSender();

        uint256 voteAmount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                voter == veTT.ownerOf(tokenIds[i]),
                "VeVote: voter is not token owner"
            );
            veTT.lockVeAmount(tokenIds[i], voteCount, veAmounts[i]);
            voteAmount += veAmounts[i];
        }

        votes[voteCount].voteId = voteCount;
        votes[voteCount].voter = voter;
        votes[voteCount].tokenIds = tokenIds;
        votes[voteCount].veAmounts = veAmounts;
        votes[voteCount].proposalId = proposalId;
        votes[voteCount].voteType = 1;
        votes[voteCount].choice = choice;
        votes[voteCount].voteAmount = voteAmount;
        votes[voteCount].voteTime = block.timestamp;

        voterVoted[voter].push(voteCount);
        voterReviewVotedAmounts[voter][proposalId][choice] += voteAmount;
        reviewVotedAmounts[proposalId][choice] += voteAmount;

        emit ReviewVoted(voteCount, voter, proposalId, choice, voteAmount);
    }

    function vote(
        uint256[] calldata tokenIds,
        uint256[] calldata veAmounts,
        uint256 proposalId,
        uint8 choice
    ) external nonReentrant whenNotPaused {
        require(
            proposals[proposalId].proposalId == proposalId,
            "VeVote: invalid proposal"
        );
        require(
            proposals[proposalId].createTime + reviewPeriod < block.timestamp,
            "VeVote: still in review period"
        );
        require(
            proposals[proposalId].startTime <= block.timestamp,
            "VeVote: proposal vote not started"
        );
        require(
            proposals[proposalId].endTime >= block.timestamp,
            "VeVote: proposal vote ended"
        );
        require(
            proposals[proposalId].adminReview != 2,
            "VeVote: proposal rejected by admin review"
        );
        if (proposals[proposalId].adminReview != 1) {
            require(
                reviewVotedAmounts[proposalId][1] >
                    reviewVotedAmounts[proposalId][2],
                "VeVote: proposal review rejected"
            );
        }
        require(tokenIds.length == veAmounts.length, "VeVote: invalid params");

        voteCount++;
        address voter = _msgSender();

        uint256 voteAmount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                voter == veTT.ownerOf(tokenIds[i]),
                "VeVote: voter is not token owner"
            );
            veTT.lockVeAmount(tokenIds[i], voteCount, veAmounts[i]);
            voteAmount += veAmounts[i];
        }

        votes[voteCount].voteId = voteCount;
        votes[voteCount].voter = voter;
        votes[voteCount].tokenIds = tokenIds;
        votes[voteCount].veAmounts = veAmounts;
        votes[voteCount].proposalId = proposalId;
        votes[voteCount].voteType = 2;
        votes[voteCount].choice = choice;
        votes[voteCount].voteAmount = voteAmount;
        votes[voteCount].voteTime = block.timestamp;

        voterVoted[voter].push(voteCount);
        voterVotedAmounts[voter][proposalId][choice] += voteAmount;
        votedAmounts[proposalId][choice] += voteAmount;

        emit VeVoted(voteCount, voter, proposalId, choice, voteAmount);
    }

    function releaseVotes(
        uint256[] calldata voteIds
    ) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < voteIds.length; i++) {
            require(
                votes[voteIds[i]].voteId == voteIds[i],
                "VeVote: invalid vote id"
            );
            if (votes[voteIds[i]].voteType == 1) {
                require(
                    proposals[votes[voteIds[i]].proposalId].createTime +
                        reviewPeriod <
                        block.timestamp,
                    "VeVote: cannot release vote yet"
                );
            } else {
                require(
                    proposals[votes[voteIds[i]].proposalId].endTime <
                        block.timestamp,
                    "VeVote: cannot release vote yet"
                );
            }
            require(
                !votes[voteIds[i]].released,
                "VeVote: vote already released"
            );

            votes[voteIds[i]].released = true;
            for (uint256 j = 0; j < votes[voteIds[i]].tokenIds.length; j++) {
                veTT.unlockVeAmount(
                    votes[voteIds[i]].tokenIds[j],
                    voteIds[i],
                    votes[voteIds[i]].veAmounts[j]
                );
            }

            emit VeVoteReleased(voteIds[i]);
        }
    }

    function voterVotedCount(address voter) external view returns (uint256) {
        return voterVoted[voter].length;
    }

    function proposalCount() external view returns (uint256) {
        return proposalIds.length;
    }

    function getVoterVoted(
        address voter
    ) external view returns (uint256[] memory) {
        return voterVoted[voter];
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }
}