// SPDX-License-Identifier: MIT

    pragma solidity ^0.8.15;

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




    /**
    * @dev String operations.
    */
    library Strings {
        bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

        /**
        * @dev Converts a `uint256` to its ASCII `string` decimal representation.
        */
        function toString(uint256 value) internal pure returns (string memory) {
            // Inspired by OraclizeAPI's implementation - MIT licence
            // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

            if (value == 0) {
                return "0";
            }
            uint256 temp = value;
            uint256 digits;
            while (temp != 0) {
                digits++;
                temp /= 10;
            }
            bytes memory buffer = new bytes(digits);
            while (value != 0) {
                digits -= 1;
                buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
                value /= 10;
            }
            return string(buffer);
        }

        /**
        * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
        */
        function toHexString(uint256 value) internal pure returns (string memory) {
            if (value == 0) {
                return "0x00";
            }
            uint256 temp = value;
            uint256 length = 0;
            while (temp != 0) {
                length++;
                temp >>= 8;
            }
            return toHexString(value, length);
        }

        /**
        * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
        */
        function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
            bytes memory buffer = new bytes(2 * length + 2);
            buffer[0] = "0";
            buffer[1] = "x";
            for (uint256 i = 2 * length + 1; i > 1; --i) {
                buffer[i] = _HEX_SYMBOLS[value & 0xf];
                value >>= 4;
            }
            require(value == 0, "Strings: hex length insufficient");
            return string(buffer);
        }
    }




    /*
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
            _setOwner(_msgSender());
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
            _setOwner(address(0));
        }

        /**
        * @dev Transfers ownership of the contract to a new account (`newOwner`).
        * Can only be called by the current owner.
        */
        function transferOwnership(address newOwner) public virtual onlyOwner {
            require(newOwner != address(0), "Ownable: new owner is the zero address");
            _setOwner(newOwner);
        }

        function _setOwner(address newOwner) private {
            address oldOwner = _owner;
            _owner = newOwner;
            emit OwnershipTransferred(oldOwner, newOwner);
        }
    }





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
        * by making the `nonReentrant` function external, and make it call a
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














    /**
    * @title ERC721 token receiver interface
    * @dev Interface for any contract that wants to support safeTransfers
    * from ERC721 asset contracts.
    */
    interface IERC721Receiver {
        /**
        * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
        * by `operator` from `from`, this function is called.
        *
        * It must return its Solidity selector to confirm the token transfer.
        * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
        *
        * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
        */
        function onERC721Received(
            address operator,
            address from,
            uint256 tokenId,
            bytes calldata data
        ) external returns (bytes4);
    }







    /**
    * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
    * @dev See https://eips.ethereum.org/EIPS/eip-721
    */
    interface IERC721Metadata is IERC721 {
        /**
        * @dev Returns the token collection name.
        */
        function name() external view returns (string memory);

        /**
        * @dev Returns the token collection symbol.
        */
        function symbol() external view returns (string memory);

        /**
        * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
        */
        function tokenURI(uint256 tokenId) external view returns (string memory);
    }





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
        */
        function isContract(address account) internal view returns (bool) {
            // This method relies on extcodesize, which returns 0 for contracts in
            // construction, since the code is only stored at the end of the
            // constructor execution.

            uint256 size;
            assembly {
                size := extcodesize(account)
            }
            return size > 0;
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
            return _verifyCallResult(success, returndata, errorMessage);
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
            return _verifyCallResult(success, returndata, errorMessage);
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
            return _verifyCallResult(success, returndata, errorMessage);
        }

        function _verifyCallResult(
            bool success,
            bytes memory returndata,
            string memory errorMessage
        ) private pure returns (bytes memory) {
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
    * @dev Implementation of the {IERC165} interface.
    *
    * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
    * for the additional interface id that will be supported. For example:
    *
    * ```solidity
    * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
    * }
    * ```
    *
    * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
    */
    abstract contract ERC165 is IERC165 {
        /**
        * @dev See {IERC165-supportsInterface}.
        */
        function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
            return interfaceId == type(IERC165).interfaceId;
        }
    }


    /**
    * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
    * the Metadata extension, but not including the Enumerable extension, which is available separately as
    * {ERC721Enumerable}.
    */
    contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
        using Address for address;
        using Strings for uint256;

        // Token name
        string private _name;

        // Token symbol
        string private _symbol;

        // Mapping from token ID to owner address
        mapping(uint256 => address) private _owners;

        // Mapping owner address to token count
        mapping(address => uint256) private _balances;

        // Mapping from token ID to approved address
        mapping(uint256 => address) private _tokenApprovals;

        // Mapping from owner to operator approvals
        mapping(address => mapping(address => bool)) private _operatorApprovals;

        /**
        * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
        */
        constructor(string memory name_, string memory symbol_) {
            _name = name_;
            _symbol = symbol_;
        }

        /**
        * @dev See {IERC165-supportsInterface}.
        */
        function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
            return
                interfaceId == type(IERC721).interfaceId ||
                interfaceId == type(IERC721Metadata).interfaceId ||
                super.supportsInterface(interfaceId);
        }

        /**
        * @dev See {IERC721-balanceOf}.
        */
        function balanceOf(address owner) public view virtual override returns (uint256) {
            require(owner != address(0), "ERC721: balance query for the zero address");
            return _balances[owner];
        }

        /**
        * @dev See {IERC721-ownerOf}.
        */
        function ownerOf(uint256 tokenId) public view virtual override returns (address) {
            address owner = _owners[tokenId];
            require(owner != address(0), "ERC721: owner query for nonexistent token");
            return owner;
        }

        /**
        * @dev See {IERC721Metadata-name}.
        */
        function name() public view virtual override returns (string memory) {
            return _name;
        }

        /**
        * @dev See {IERC721Metadata-symbol}.
        */
        function symbol() public view virtual override returns (string memory) {
            return _symbol;
        }

        /**
        * @dev See {IERC721Metadata-tokenURI}.
        */
        function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
            require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

            string memory baseURI = _baseURI();
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
        }

        /**
        * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
        * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
        * by default, can be overriden in child contracts.
        */
        function _baseURI() internal view virtual returns (string memory) {
            return "";
        }

        /**
        * @dev See {IERC721-approve}.
        */
        function approve(address to, uint256 tokenId) public virtual override {
            address owner = ERC721.ownerOf(tokenId);
            require(to != owner, "ERC721: approval to current owner");

            require(
                _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
                "ERC721: approve caller is not owner nor approved for all"
            );

            _approve(to, tokenId);
        }

        /**
        * @dev See {IERC721-getApproved}.
        */
        function getApproved(uint256 tokenId) public view virtual override returns (address) {
            require(_exists(tokenId), "ERC721: approved query for nonexistent token");

            return _tokenApprovals[tokenId];
        }

        /**
        * @dev See {IERC721-setApprovalForAll}.
        */
        function setApprovalForAll(address operator, bool approved) public virtual override {
            require(operator != _msgSender(), "ERC721: approve to caller");

            _operatorApprovals[_msgSender()][operator] = approved;
            emit ApprovalForAll(_msgSender(), operator, approved);
        }

        /**
        * @dev See {IERC721-isApprovedForAll}.
        */
        function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
            return _operatorApprovals[owner][operator];
        }

        /**
        * @dev See {IERC721-transferFrom}.
        */
        function transferFrom(
            address from,
            address to,
            uint256 tokenId
        ) public virtual override {
            //solhint-disable-next-line max-line-length
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

            _transfer(from, to, tokenId);
        }

        /**
        * @dev See {IERC721-safeTransferFrom}.
        */
        function safeTransferFrom(
            address from,
            address to,
            uint256 tokenId
        ) public virtual override {
            safeTransferFrom(from, to, tokenId, "");
        }

        /**
        * @dev See {IERC721-safeTransferFrom}.
        */
        function safeTransferFrom(
            address from,
            address to,
            uint256 tokenId,
            bytes memory _data
        ) public virtual override {
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
            _safeTransfer(from, to, tokenId, _data);
        }

        /**
        * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
        * are aware of the ERC721 protocol to prevent tokens from being forever locked.
        *
        * `_data` is additional data, it has no specified format and it is sent in call to `to`.
        *
        * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
        * implement alternative mechanisms to perform token transfer, such as signature-based.
        *
        * Requirements:
        *
        * - `from` cannot be the zero address.
        * - `to` cannot be the zero address.
        * - `tokenId` token must exist and be owned by `from`.
        * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
        *
        * Emits a {Transfer} event.
        */
        function _safeTransfer(
            address from,
            address to,
            uint256 tokenId,
            bytes memory _data
        ) internal virtual {
            _transfer(from, to, tokenId);
            require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
        }

        /**
        * @dev Returns whether `tokenId` exists.
        *
        * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
        *
        * Tokens start existing when they are minted (`_mint`),
        * and stop existing when they are burned (`_burn`).
        */
        function _exists(uint256 tokenId) internal view virtual returns (bool) {
            return _owners[tokenId] != address(0);
        }

        /**
        * @dev Returns whether `spender` is allowed to manage `tokenId`.
        *
        * Requirements:
        *
        * - `tokenId` must exist.
        */
        function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
            require(_exists(tokenId), "ERC721: operator query for nonexistent token");
            address owner = ERC721.ownerOf(tokenId);
            return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
        }

        /**
        * @dev Safely mints `tokenId` and transfers it to `to`.
        *
        * Requirements:
        *
        * - `tokenId` must not exist.
        * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
        *
        * Emits a {Transfer} event.
        */
        function _safeMint(address to, uint256 tokenId) internal virtual {
            _safeMint(to, tokenId, "");
        }

        /**
        * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
        * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
        */
        function _safeMint(
            address to,
            uint256 tokenId,
            bytes memory _data
        ) internal virtual {
            _mint(to, tokenId);
            require(
                _checkOnERC721Received(address(0), to, tokenId, _data),
                "ERC721: transfer to non ERC721Receiver implementer"
            );
        }

        /**
        * @dev Mints `tokenId` and transfers it to `to`.
        *
        * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
        *
        * Requirements:
        *
        * - `tokenId` must not exist.
        * - `to` cannot be the zero address.
        *
        * Emits a {Transfer} event.
        */
        function _mint(address to, uint256 tokenId) internal virtual {
            require(to != address(0), "ERC721: mint to the zero address");
            require(!_exists(tokenId), "ERC721: token already minted");

            _beforeTokenTransfer(address(0), to, tokenId);

            _balances[to] += 1;
            _owners[tokenId] = to;

            emit Transfer(address(0), to, tokenId);
        }

        /**
        * @dev Destroys `tokenId`.
        * The approval is cleared when the token is burned.
        *
        * Requirements:
        *
        * - `tokenId` must exist.
        *
        * Emits a {Transfer} event.
        */
        function _burn(uint256 tokenId) internal virtual {
            address owner = ERC721.ownerOf(tokenId);

            _beforeTokenTransfer(owner, address(0), tokenId);

            // Clear approvals
            _approve(address(0), tokenId);

            _balances[owner] -= 1;
            delete _owners[tokenId];

            emit Transfer(owner, address(0), tokenId);
        }

        /**
        * @dev Transfers `tokenId` from `from` to `to`.
        *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
        *
        * Requirements:
        *
        * - `to` cannot be the zero address.
        * - `tokenId` token must be owned by `from`.
        *
        * Emits a {Transfer} event.
        */
        function _transfer(
            address from,
            address to,
            uint256 tokenId
        ) internal virtual {
            require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
            require(to != address(0), "ERC721: transfer to the zero address");

            _beforeTokenTransfer(from, to, tokenId);

            // Clear approvals from the previous owner
            _approve(address(0), tokenId);

            _balances[from] -= 1;
            _balances[to] += 1;
            _owners[tokenId] = to;

            emit Transfer(from, to, tokenId);
        }

        /**
        * @dev Approve `to` to operate on `tokenId`
        *
        * Emits a {Approval} event.
        */
        function _approve(address to, uint256 tokenId) internal virtual {
            _tokenApprovals[tokenId] = to;
            emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
        }

        /**
        * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
        * The call is not executed if the target address is not a contract.
        *
        * @param from address representing the previous owner of the given token ID
        * @param to target address that will receive the tokens
        * @param tokenId uint256 ID of the token to be transferred
        * @param _data bytes optional data to send along with the call
        * @return bool whether the call correctly returned the expected magic value
        */
        function _checkOnERC721Received(
            address from,
            address to,
            uint256 tokenId,
            bytes memory _data
        ) private returns (bool) {
            if (to.isContract()) {
                try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                    return retval == IERC721Receiver(to).onERC721Received.selector;
                } catch (bytes memory reason) {
                    if (reason.length == 0) {
                        revert("ERC721: transfer to non ERC721Receiver implementer");
                    } else {
                        assembly {
                            revert(add(32, reason), mload(reason))
                        }
                    }
                }
            } else {
                return true;
            }
        }

        /**
        * @dev Hook that is called before any token transfer. This includes minting
        * and burning.
        *
        * Calling conditions:
        *
        * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
        * transferred to `to`.
        * - When `from` is zero, `tokenId` will be minted for `to`.
        * - When `to` is zero, ``from``'s `tokenId` will be burned.
        * - `from` and `to` are never both zero.
        *
        * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
        */
        function _beforeTokenTransfer(
            address from,
            address to,
            uint256 tokenId
        ) internal virtual {}
    }







    /**
    * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
    * @dev See https://eips.ethereum.org/EIPS/eip-721
    */
    interface IERC721Enumerable is IERC721 {
        /**
        * @dev Returns the total amount of tokens stored by the contract.
        */
        function totalSupply() external view returns (uint256);

        /**
        * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
        * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
        */
        function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

        /**
        * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
        * Use along with {totalSupply} to enumerate all tokens.
        */
        function tokenByIndex(uint256 index) external view returns (uint256);
    }


    /**
    * @dev This implements an optional extension of {ERC721} defined in the EIP that adds
    * enumerability of all the token ids in the contract as well as all token ids owned by each
    * account.
    */
    abstract contract ERC721Enumerable is ERC721, IERC721Enumerable {
        // Mapping from owner to list of owned token IDs
        mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

        // Mapping from token ID to index of the owner tokens list
        mapping(uint256 => uint256) private _ownedTokensIndex;

        // Array with all token ids, used for enumeration
        uint256[] private _allTokens;

        // Mapping from token id to position in the allTokens array
        mapping(uint256 => uint256) private _allTokensIndex;

        /**
        * @dev See {IERC165-supportsInterface}.
        */
        function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
            return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
        }

        /**
        * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
        */
        function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
            require(index < ERC721.balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
            return _ownedTokens[owner][index];
        }

        /**
        * @dev See {IERC721Enumerable-totalSupply}.
        */
        function totalSupply() public view virtual override returns (uint256) {
            return _allTokens.length;
        }

        /**
        * @dev See {IERC721Enumerable-tokenByIndex}.
        */
        function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
            require(index < ERC721Enumerable.totalSupply(), "ERC721Enumerable: global index out of bounds");
            return _allTokens[index];
        }

        /**
        * @dev Hook that is called before any token transfer. This includes minting
        * and burning.
        *
        * Calling conditions:
        *
        * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
        * transferred to `to`.
        * - When `from` is zero, `tokenId` will be minted for `to`.
        * - When `to` is zero, ``from``'s `tokenId` will be burned.
        * - `from` cannot be the zero address.
        * - `to` cannot be the zero address.
        *
        * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
        */
        function _beforeTokenTransfer(
            address from,
            address to,
            uint256 tokenId
        ) internal virtual override {
            super._beforeTokenTransfer(from, to, tokenId);

            if (from == address(0)) {
                _addTokenToAllTokensEnumeration(tokenId);
            } else if (from != to) {
                _removeTokenFromOwnerEnumeration(from, tokenId);
            }
            if (to == address(0)) {
                _removeTokenFromAllTokensEnumeration(tokenId);
            } else if (to != from) {
                _addTokenToOwnerEnumeration(to, tokenId);
            }
        }

        /**
        * @dev Private function to add a token to this extension's ownership-tracking data structures.
        * @param to address representing the new owner of the given token ID
        * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
        */
        function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
            uint256 length = ERC721.balanceOf(to);
            _ownedTokens[to][length] = tokenId;
            _ownedTokensIndex[tokenId] = length;
        }

        /**
        * @dev Private function to add a token to this extension's token tracking data structures.
        * @param tokenId uint256 ID of the token to be added to the tokens list
        */
        function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
            _allTokensIndex[tokenId] = _allTokens.length;
            _allTokens.push(tokenId);
        }

        /**
        * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
        * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
        * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
        * This has O(1) time complexity, but alters the order of the _ownedTokens array.
        * @param from address representing the previous owner of the given token ID
        * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
        */
        function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
            // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).

            uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
            uint256 tokenIndex = _ownedTokensIndex[tokenId];

            // When the token to delete is the last token, the swap operation is unnecessary
            if (tokenIndex != lastTokenIndex) {
                uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

                _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
                _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
            }

            // This also deletes the contents at the last position of the array
            delete _ownedTokensIndex[tokenId];
            delete _ownedTokens[from][lastTokenIndex];
        }

        /**
        * @dev Private function to remove a token from this extension's token tracking data structures.
        * This has O(1) time complexity, but alters the order of the _allTokens array.
        * @param tokenId uint256 ID of the token to be removed from the tokens list
        */
        function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
            // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).

            uint256 lastTokenIndex = _allTokens.length - 1;
            uint256 tokenIndex = _allTokensIndex[tokenId];

            // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
            // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
            // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
            uint256 lastTokenId = _allTokens[lastTokenIndex];

            _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

            // This also deletes the contents at the last position of the array
            delete _allTokensIndex[tokenId];
            _allTokens.pop();
        }
    }


    // Web3 in Travel Podcast NFT by Tripluca.eth
    // developed by @jacmos3. forked by @tripluca
    // contract Web3InTravelNFTTicket is ERC721Enumerable, ReentrancyGuard, Ownable {
        contract Web3InTravelPodcastNFT is ERC721Enumerable, ReentrancyGuard, Ownable {
        bool public paused;
        uint16 public constant MAX_ID = 500;
        uint256 public constant INITIAL_PRICE  = 5000000000000000 wei;  // 0.005 eth
        uint256 public constant END_PRICE = 7500000000000000 wei; // 0.0075 eth
        uint256 public constant INITIAL_SPONSOR_PRICE = 100000000000000000 wei; // 0.1 eth
        
        uint256 private constant EXP = 10**18;
        uint256 private sumIncrement = 0;
        uint256 private dateTime;
        uint256 public price;
        uint256 public sponsorshipPrice;
        uint256 public oldSponsorPayment;
        uint256 public sponsorPayment;
        address public oldSponsorAddress;
        address public sponsorAddress;
        address public treasurer;
        string constant private DET_LOGO = "Logo";
        string constant private DET_TITLE = "Title";
        string constant private DET_SUBTITLE = "Subtitle";
        string constant private DET_TICKET_NUMBER = "DONATION #";
        string constant private DET_CITY = "City";
        string constant private DET_ADDRESS_LOCATION = "Location";
        string constant private DET_DATE = "Date";
        string constant private DET_DATE_LONG = "Date_long";
        string constant private DET_TIME = "Time";
        string constant private DET_TIME_LONG = "Time_long";
        string constant private SPONSOR = "SPONSOR: ";
        string constant private DET_SPONSOR_QUOTE = "Sponsor";
        string constant private DET_SPONSOR_QUOTE_LONG = "Sponsor_long";
        string constant private DET_TYPE = "Type";
        string constant private DET_CREDITS = "credits";
        string constant private TYPE_STANDARD = "Standard";
        string constant private TYPE_AIRDROP = "Airdrop";
        string constant private ERR_SOLD_OUT = "Sold out";
        string constant private ERR_MINTING_PAUSED = "Minting paused";
        string constant private ERR_INSERT_EXACT = "Exact value required";
        string constant private ERR_TOO_MANY_CHARS = "Too many chars, or empty string";
        string constant private ERR_SENT_FAIL = "Failure";
        string constant private ERR_NOT_EXISTS = "Selected tokenId does not exist";
        string constant private ERR_INPUT_NOT_VALID = "Input not valid. Remove not valid chars";
        string constant private ERR_NO_HACKS_PLS = "Hack failed! Try again!";
        string constant private ERR_TIME_EXPIRED = "Time expired";
        mapping(string => string) private details;
        mapping(uint256 => uint256) public prices;
        mapping(uint256 => address) public mintedBy;
        mapping(uint256 => bool) public airdrop;
        event Refunded(address indexed oldSponsorAddress, uint256 oldSponsorPayment);
        event NewSponsorship(address indexed sender, uint256 indexed amount, string _quote);
        event Minting(address indexed sender, uint256 indexed tokenId, uint256 msgValue, bool indexed airdrop);
        event MintingByOwner(address indexed sender, uint256 indexed tokenId);
        event DetailChanged(string indexed detail, string oldValue, string newValue);
        event ExpirationChanged(uint256 dateTime, uint256 _dateTime);
        event Withdraw(address indexed owner, address indexed trasurer, uint256 amount);
        event NewTreasurer(address indexed oldTreasurer, address indexed newTreasurer);
        event Paused(bool paused);

       
        constructor() ERC721("Web3 In Travel Podcast Donation", "WEB3INTRAVELPODCAST") Ownable(){
            details[DET_TITLE] = "WEB3 IN TRAVEL PODCAST";
            details[DET_SUBTITLE] = "Sponsorship and Donation NFT";
            details[DET_CITY] = "";
            details[DET_ADDRESS_LOCATION] = "- Sponsor to print your company's name on all NFTs";
            details[DET_DATE_LONG] = "and be named in the next episode";
            details[DET_TIME_LONG] = "- Donate and get this NFT as a receipt";
            details[DET_DATE] = "";
            details[DET_TIME] = "";
            details[DET_SPONSOR_QUOTE] = "";
            details[DET_SPONSOR_QUOTE_LONG] = "";
          
            details[DET_CREDITS] = "Podcast.Web3InTravel.com by Luca De Giglio";
            details[DET_TYPE] = TYPE_STANDARD;
            sponsorshipPrice = INITIAL_SPONSOR_PRICE;
            price = INITIAL_PRICE;
            treasurer = 0xe2Fcb9715cF1532436dA296Dbd7fB2DBaDd5b228; // Tripluca.eth
            paused = false;
            dateTime = 1704067140; // Sun Dec 31 2023 23:59:00 UTC
        }

        function claimByOwner() external onlyOwner {
            require(!paused, ERR_MINTING_PAUSED);
            uint256 _tokenId = totalSupply() +1;
            require(_tokenId <= MAX_ID, ERR_SOLD_OUT);
            require(block.timestamp <= dateTime, ERR_TIME_EXPIRED);
            address _sender = _msgSender();
            mintedBy[_tokenId] = _sender;
            emit MintingByOwner(_sender, _tokenId);
            _safeMint(_sender, _tokenId);
        }

        function claimByPatrons(bool _airdrop) external payable nonReentrant {
            require(!paused, ERR_MINTING_PAUSED);
            uint256 _tokenId = totalSupply() +1;
            require(_tokenId <= MAX_ID, ERR_SOLD_OUT);
            require(block.timestamp <= dateTime, ERR_TIME_EXPIRED);
            address _sender = _msgSender();
            require(tx.origin == _sender, ERR_NO_HACKS_PLS);
            uint256 _msgValue = msg.value;
            require(_airdrop ? _msgValue == (price + price / 5) : _msgValue == price, ERR_INSERT_EXACT);
            prices[_tokenId] = _msgValue;
            mintedBy[_tokenId] = _sender;
            airdrop[_tokenId] = _airdrop;
            sumIncrement += ((END_PRICE - INITIAL_PRICE) - sumIncrement)/10;
            price = INITIAL_PRICE + (sumIncrement / EXP)*EXP;
            price = INITIAL_PRICE + (sumIncrement);
            emit Minting(_sender, _tokenId, _msgValue, _airdrop);
            _safeMint(_sender, _tokenId);
        }

        function sponsorship(string memory _quote) external payable nonReentrant {
            require(!paused, ERR_MINTING_PAUSED);
            require(block.timestamp <= dateTime, ERR_TIME_EXPIRED);
            address _sender = _msgSender();
            require(tx.origin == _sender, ERR_NO_HACKS_PLS);
            require(msg.value == sponsorshipPrice, ERR_INSERT_EXACT);
            uint256 len = bytes(_quote).length;
            require(len > 0 && len <= 32, ERR_TOO_MANY_CHARS);
            require(sanitize(_quote), ERR_INPUT_NOT_VALID);
            details[DET_SPONSOR_QUOTE] = _quote;
            details[DET_SPONSOR_QUOTE_LONG] = string(abi.encodePacked(SPONSOR, _quote));
            oldSponsorAddress = sponsorAddress;
            oldSponsorPayment = sponsorPayment;
            sponsorAddress = _sender;
            sponsorPayment = sponsorshipPrice;
            sponsorshipPrice = (sponsorshipPrice * 12) / 10;
            // if (oldSponsorPayment > 0){
            //     (bool sent,) = payable(oldSponsorAddress).call{value:oldSponsorPayment}("");
            //     require(sent, ERR_SENT_FAIL);
            //     emit Refunded(oldSponsorAddress, oldSponsorPayment);
            // }
            emit NewSponsorship(_sender, sponsorPayment, _quote);
        }

        function tokenURI(uint256 _tokenId) override public view returns (string memory) {
            require(_tokenId <= totalSupply(), ERR_NOT_EXISTS);
           // string memory _details_type = airdrop[_tokenId] ? TYPE_AIRDROP : TYPE_STANDARD;
            string memory _details_ticket_number = string(abi.encodePacked(DET_TICKET_NUMBER,toString(_tokenId)));
            string[5] memory parts;
            parts[0] = string(abi.encodePacked('<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.a { fill:white; font-family: serif; font-size: 20px; } .a1 { fill:white; font-family: serif; font-size: 16px; } .b { fill:white; font-family: serif; font-size: 14px; } .c { fill:white; font-family: serif; font-size: 14px; }</style> <rect width="100%" height="100%" fill="#649231" />'));
            parts[1] = string(abi.encodePacked('<text class="a" x="175" y="40"  text-anchor="middle" >',details[DET_TITLE],'</text><text class="a1" x="175" y="60"  text-anchor="middle" >',details[DET_SUBTITLE],'</text><text x="175" y="100" text-anchor="middle" class="a1">',_details_ticket_number,'</text>'));
            parts[2] = string(abi.encodePacked('<text x="10" y="120" class="b">',details[DET_CITY],'</text><text x="10" y="140" class="b">',details[DET_ADDRESS_LOCATION],'</text><text x="10" y="160" class="b">',details[DET_DATE_LONG],'</text><text x="10" y="180" class="b">',details[DET_TIME_LONG],'</text>'));

            parts[3] = string(abi.encodePacked('<text x="10" y="220" class="b">Donated: 0.00',toString(prices[_tokenId] / 100000000000000 ),' ETH</text><text x="10" y="240" class="b">By: 0x',toAsciiString(mintedBy[_tokenId]),'</text><text x="10" y="250" class="b"></text>'));

            parts[4] = string(abi.encodePacked('<text x="175" y="280" class="b" text-anchor="middle" >',details[DET_SPONSOR_QUOTE_LONG],'</text><text x="175" y="330" text-anchor="middle" class="c">',details[DET_CREDITS],'</text>',details[DET_LOGO],'</svg>'));

            string memory compact = string(abi.encodePacked(parts[0],parts[1],parts[2],parts[3],parts[4]));
            string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Podcast donation #', toString(_tokenId), '", "description": "NFT Sponsor and Donation NFT for the Web3 in Travel Podcast. Donate to the Web3 in Travel Podcast and get an NFT as proof. Sponsor and your company name will be published on all NFTs and mentioned in the Podcast https://podcast.web3intravel.com", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(compact)), '","attributes":[',metadata(_tokenId),']}'))));

            return string(abi.encodePacked('data:application/json;base64,', json));
        }


        function metadata(uint256 _tokenId) internal view returns (string memory){
            string memory _details_type = airdrop[_tokenId] ? TYPE_AIRDROP : TYPE_STANDARD;
            string[3] memory _parts;
            _parts[0] = string(abi.encodePacked(
                '{"trait_type":"id","value":"',toString(_tokenId),'"},'
                ,'{"trait_type":"',DET_TITLE,'","value":"',details[DET_TITLE],'"},'
                ,'{"trait_type":"',DET_SUBTITLE,'","value":"',details[DET_SUBTITLE],'"},'
                ,'{"trait_type":"',DET_CITY,'","value":"',details[DET_CITY],'"},'
                ));

            _parts[1] = string(abi.encodePacked(
                '{"trait_type":"',DET_ADDRESS_LOCATION,'","value":"',details[DET_ADDRESS_LOCATION],'"},'
                ,'{"trait_type":"',DET_DATE,'","value":"',details[DET_DATE],'"},'
                ,'{"trait_type":"',DET_TIME,'","value":"',details[DET_TIME],'"},'
                ,'{"trait_type":"',DET_TYPE,'","value":"',_details_type,'"},'
                ));

            _parts[2] = string(abi.encodePacked(
                '{"trait_type":"Minted by","value":"',toAsciiString(mintedBy[_tokenId]),'"},'
                ,'{"trait_type":"',DET_SPONSOR_QUOTE,'","value":"',details[DET_SPONSOR_QUOTE],'"},'
                ,'{"trait_type":"Price","value":"',toString(prices[_tokenId]),'"},'
                ,'{"trait_type":"',DET_CREDITS,'","value":"',details[DET_CREDITS],'"}'
            ));

            return string(abi.encodePacked(_parts[0],_parts[1], _parts[2]));
    }


        function withdraw() external onlyOwner {
            uint256 amount = address(this).balance;
            payable(treasurer).transfer(amount);
            emit Withdraw(msg.sender, treasurer, amount);
        }

        function setTreasurer(address _newAddress) external onlyOwner{
            emit NewTreasurer(treasurer, _newAddress);
            treasurer = _newAddress;
        }

        function setSponsorQuote(string memory _quote) external onlyOwner{
        emit DetailChanged(DET_SPONSOR_QUOTE, details[DET_SPONSOR_QUOTE], _quote);
        emit DetailChanged(DET_SPONSOR_QUOTE_LONG, details[DET_SPONSOR_QUOTE_LONG], _quote);
        details[DET_SPONSOR_QUOTE] = _quote;
        details[DET_SPONSOR_QUOTE_LONG] = string(abi.encodePacked(SPONSOR,_quote));
        }

        function pauseUnpause() external onlyOwner{
            paused = !paused;
            emit Paused(paused);
        }


        function setDateTime(string memory _newDate, string memory _newDateLong, string memory _newTime, string memory _newTimeLong, uint256 _dateTime) external onlyOwner{
            if (bytes(_newDate).length > 0) {
            emit DetailChanged(DET_DATE, details[DET_DATE], _newDate);
            details[DET_DATE] = _newDate;
            }
            if (bytes(_newDateLong).length > 0) {
            emit DetailChanged(DET_DATE_LONG, details[DET_DATE_LONG], _newDateLong);
            details[DET_DATE_LONG] = _newDateLong;
            }
            if (bytes(_newTime).length > 0) {
            emit DetailChanged(DET_TIME, details[DET_TIME], _newTime);
            details[DET_TIME] = _newTime;
            }
            if (bytes(_newTimeLong).length > 0) {
            emit DetailChanged(DET_TIME_LONG, details[DET_TIME_LONG], _newTimeLong);
            details[DET_TIME_LONG] = _newTimeLong;
            }
            if (_dateTime > 0){
            emit ExpirationChanged(dateTime, _dateTime);
            dateTime = _dateTime;
            }
        }

        function setAddressLocation(string memory _newAddressLocation) external onlyOwner{
            emit DetailChanged(DET_ADDRESS_LOCATION, details[DET_ADDRESS_LOCATION], _newAddressLocation);
            details[DET_ADDRESS_LOCATION] = _newAddressLocation;
        }

        function setCity(string memory _newCity) external onlyOwner{
            emit DetailChanged(DET_CITY, details[DET_CITY], _newCity);
            details[DET_CITY] = _newCity;
        }

        function setLogo(string memory _newLogo) external onlyOwner{
            emit DetailChanged(DET_LOGO, details[DET_LOGO], _newLogo);
            details[DET_LOGO] = _newLogo;
        }

        function setTitle(string memory _newTitle) external onlyOwner{
            emit DetailChanged(DET_TITLE, details[DET_TITLE], _newTitle);
            details[DET_TITLE] = _newTitle;
        }

        function setSubtitle(string memory _newSubtitle) external onlyOwner{
            emit DetailChanged(DET_SUBTITLE, details[DET_SUBTITLE], _newSubtitle);
            details[DET_SUBTITLE] = _newSubtitle;
        }

        function sanitize(string memory input) internal pure returns(bool){
            uint8 allowedChars = 0;
            bytes memory byteString = bytes(input);
            bytes memory allowed = bytes("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ .,:;()[]{}+-*$!?");
            bool exit = false;
            for(uint8 i=0; i < byteString.length; i++){
            exit = false;
            for(uint8 j=0; j < allowed.length && !exit; j++){
                if(byteString[i] == allowed[j]){
                    allowedChars++;
                    exit = true;
                }
            }
            }
            return allowedChars >= byteString.length;
        }

        function detailCheck(string memory _detail) external view returns (string memory){
        return details[_detail];
        }

        function toAsciiString(address x) internal pure returns (string memory) {
            bytes memory s = new bytes(40);
            for (uint i = 0; i < 20; i++) {
                bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
                bytes1 hi = bytes1(uint8(b) / 16);
                bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
                s[2*i] = char(hi);
                s[2*i+1] = char(lo);
            }
            return string(s);
        }

        function char(bytes1 b) internal pure returns (bytes1 c) {
            if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
            else return bytes1(uint8(b) + 0x57);
        }

        function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

            if (value == 0) {
                return "0";
            }
            uint256 temp = value;
            uint256 digits;
            while (temp != 0) {
                digits++;
                temp /= 10;
            }
            bytes memory buffer = new bytes(digits);
            while (value != 0) {
                digits -= 1;
                buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
                value /= 10;
            }
            return string(buffer);
        }
    }


    /// [MIT License]
    /// @title Base64
    /// @notice Provides a function for encoding some bytes in base64
    /// @author Brecht Devos <brecht@loopring.org>
    library Base64 {

        bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        /// @notice Encodes some bytes to the base64 representation
        function encode(bytes memory data) internal pure returns (string memory) {
            uint256 len = data.length;
            if (len == 0) return "";

            // multiply by 4/3 rounded up
            uint256 encodedLen = 4 * ((len + 2) / 3);

            // Add some extra buffer at the end
            bytes memory result = new bytes(encodedLen + 32);

            bytes memory table = TABLE;

            assembly {
                let tablePtr := add(table, 1)
                let resultPtr := add(result, 32)

                for {
                    let i := 0
                } lt(i, len) {

                } {
                    i := add(i, 3)
                    let input := and(mload(add(data, i)), 0xffffff)

                    let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                    out := shl(8, out)
                    out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                    out := shl(8, out)
                    out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                    out := shl(8, out)
                    out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                    out := shl(224, out)

                    mstore(resultPtr, out)

                    resultPtr := add(resultPtr, 4)
                }

                switch mod(len, 3)
                case 1 {
                    mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
                }
                case 2 {
                    mstore(sub(resultPtr, 1), shl(248, 0x3d))
                }

                mstore(result, encodedLen)
            }

            return string(result);
        }
    }