//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "../lib/CheapMintNFTBytesLib.sol";
import "./interfaces/ICheapSwapAddress.sol";
import "./interfaces/ICheapMintNFT.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract CheapMintNFT is ICheapMintNFT {
    using CheapMintNFTBytesLib for bytes;

    mapping(address => address) public mintNFTOwner;

    constructor() {}

    /* ================ TRANSACTION FUNCTIONS ================ */

    function mint(bytes calldata mintNFTData) external {
        uint8 perMint = mintNFTData.toUint8(0);
        uint8 total = mintNFTData.toUint8(1);
        address target = mintNFTData.toAddress(2);
        address owner = msg.sender;
        if (msg.sender != tx.origin) {
            ICheapSwapAddress cheapSwapAddress = ICheapSwapAddress(msg.sender);
            owner = cheapSwapAddress.owner();
        }
        for (uint8 i = 0; i < total; i++) {
            MintNFT mintNFT = new MintNFT();
            mintNFT.mint(perMint, target, owner, mintNFTData.slice(22, mintNFTData.length - 22));
            mintNFTOwner[address(mintNFT)] = owner;
            emit MintNFTCreated(owner, address(mintNFT));
        }
    }

    function getNFTFromContractList(
        address target,
        address[] calldata contractList,
        uint256[] calldata tokenId
    ) external {
        IERC721 nft = IERC721(target);
        for (uint256 i = 0; i < contractList.length; ++i) {
            require(mintNFTOwner[contractList[i]] == msg.sender, "CheapMintNFT: not owner");
            nft.transferFrom(contractList[i], msg.sender, tokenId[i]);
        }
    }

    function getNFTFromTokenIdList(
        address target,
        address contractAddress,
        uint256[] calldata tokenId
    ) external {
        IERC721 nft = IERC721(target);
        for (uint256 i = 0; i < tokenId.length; ++i) {
            require(mintNFTOwner[contractAddress] == msg.sender, "CheapMintNFT: not owner");
            nft.transferFrom(contractAddress, msg.sender, tokenId[i]);
        }
    }
}

contract MintNFT is IERC721Receiver {
    address owner;

    constructor() {}

    function mint(
        uint8 perMint,
        address target,
        address _owner,
        bytes memory mintData
    ) external {
        owner = _owner;
        IERC721 nft = IERC721(target);
        for (uint8 i = 0; i < perMint; ++i) {
            (bool success, ) = target.call(mintData);
            require(success, "cheapMintNFT: mint NFT error");
        }
        nft.setApprovalForAll(msg.sender, true);
        selfdestruct(payable(msg.sender));
    }

    /* ================ TRANSACTION FUNCTIONS ================ */

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        IERC721(msg.sender).safeTransferFrom(address(this), owner, tokenId);
        return this.onERC721Received.selector;
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <[email protected]>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */
pragma solidity >=0.5.0;

library CheapMintNFTBytesLib {
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_start + _length >= _start, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, "toAddress_overflow");
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_start + 1 >= _start, "toUint8_overflow");
        require(_bytes.length >= _start + 1, "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ICheapSwapAddress {
    /* ==================== EVENTS =================== */

    event ApproveCall(address indexed sender, bool callApprove);

    event SetTargetData(uint256 indexed value, bytes targetData);

    event PauseCall(bool cancelCall);

    /* ==================== VIEW FUNCTIONS =================== */

    function owner() external view returns (address);

    /* ================ TRANSACTION FUNCTIONS ================ */

    function doReceive() external payable;

    function call(address target, bytes calldata data) external payable;

    /* ===================== ADMIN FUNCTIONS ==================== */

    function approveCall(address sender) external;

    function pauseCall() external;

    function setTargetData(uint256 value, bytes calldata targetData) external;

    function setTargetDataList(uint256[] calldata valueList, bytes[] calldata targetDataList) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ICheapMintNFT {
    /* ================ EVENTS ================ */

    event MintNFTCreated(address indexed owner, address mintNFTContract);

    /* ================ TRANSACTION FUNCTIONS ================ */

    function mint(bytes calldata mintNFTData) external;

    function getNFTFromContractList(
        address target,
        address[] calldata contractList,
        uint256[] calldata tokenId
    ) external;

    function getNFTFromTokenIdList(
        address target,
        address contractAddress,
        uint256[] calldata tokenId
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

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

// SPDX-License-Identifier: MIT

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