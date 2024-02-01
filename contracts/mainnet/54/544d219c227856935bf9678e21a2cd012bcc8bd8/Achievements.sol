// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./Strings.sol";
import "./ERC1155.sol";

import "./Owned.sol";

/// @title Solarbots Achievements
/// @author Solarbots (https://solarbots.io)
/// @notice All achievements are soulbound,
/// i.e. can't be transferred by the token owner.
/// Only approved operators can mint, transfer, and burn
/// tokens. Token owners can only burn their own tokens.
contract Achievements is ERC1155, Owned {
    // ---------- CONSTANTS ----------

    /// @dev "Error(string)" signature: bytes32(bytes4(keccak256("Error(string)")))
    bytes32 private constant _ERROR_FUNCTION_SIGNATURE = 0x08c379a000000000000000000000000000000000000000000000000000000000;

    /// @dev bytes32(abi.encodePacked("INSUFFICIENT_BALANCE"))
    bytes32 private constant _INSUFFICIENT_BALANCE_MESSAGE = 0x494e53554646494349454e545f42414c414e4345000000000000000000000000;

    /// @dev "INSUFFICIENT_BALANCE" is 20 characters long
    uint256 private constant _INSUFFICIENT_BALANCE_LENGTH = 20;

    // ---------- STATE ----------

    /// @notice Metadata base URI
    string public baseURI;

    /// @notice Metadata URI suffix
    string public uriSuffix;

    // ---------- CONSTRUCTOR ----------

    /// @param owner Contract owner
    constructor(address owner) Owned(owner) {}

    // ---------- METADATA ----------

    /// @notice Get metadata URI
    /// @param id Token ID
    /// @return Metadata URI of token ID `id`
    function uri(uint256 id) public view override returns (string memory) {
        require(bytes(baseURI).length > 0, "NO_METADATA");
		return string(abi.encodePacked(baseURI, Strings.toString(id), uriSuffix));
    }

    /// @notice Set metadata base URI
    /// @param _baseURI New metadata base URI
    /// @dev Doesn't emit URI event, because `id` argument isn't used
    function setBaseURI(string calldata _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    /// @notice Set metadata URI suffix
    /// @param _uriSuffix New metadata URI suffix
    /// @dev Doesn't emit URI event, because `id` argument isn't used
    function setURISuffix(string calldata _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    // ---------- APPROVAL ----------

    /// @notice Grants or revokes permission to `operator` to transfer tokens
    /// @dev Only callable by contract owner
    /// @param operator Operator address
    /// @param approved Whether to grant or revoke permission
    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override onlyOwner {
        isApprovedForAll[address(0)][operator] = approved;

        emit ApprovalForAll(address(0), operator, approved);
    }

    // ---------- TRANSFER ----------

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public virtual override {
        require(isApprovedForAll[address(0)][msg.sender], "NOT_AUTHORIZED");

        // Use assembly to perform optimized balance updates
        // Same balance updates in unoptimized Solidity:
        //
        // balanceOf[from][id] -= amount;
        // balanceOf[to][id] += amount;
        //
        /// @solidity memory-safe-assembly
        assembly {
            // Calculate the storage slot of `balanceOf[from]`
            // by concatenating the `from` address and the
            // slot of `balanceOf` in the scratch space used
            // by hashing methods, i.e. the first two 32 bytes
            // of memory. The keccak256 hash of the concatenated
            // values is the storage slot we're looking for.
            mstore(0x00, from)
            mstore(0x20, balanceOf.slot)
            let balanceOfFromSlot := keccak256(0x00, 0x40)

            // Calculate storage slot of `balanceOf[to]`
            mstore(0x00, to)
            // 0x20 still contains `balanceOf.slot`
            let balanceOfToSlot := keccak256(0x00, 0x40)

            // Calculate storage slot of `balanceOf[from][id]`
            mstore(0x00, id)
            mstore(0x20, balanceOfFromSlot)
            let amountFromSlot := keccak256(0x00, 0x40)

            // Calculate storage slot of `balanceOf[to][id]`
            // 0x00 still contains current id
            mstore(0x20, balanceOfToSlot)
            let amountToSlot := keccak256(0x00, 0x40)

            // Load amount currently stored in `balanceOf[from][id]`
            let currentAmountFrom := sload(amountFromSlot)
            // Revert with message "INSUFFICIENT_BALANCE" if the
            // transfer amount is greater than the current amount
            // of `from` to prevent an integer underflow
            if gt(amount, currentAmountFrom) {
                let freeMemory := mload(0x40)
                // Store "Error(string)" signature
                mstore(freeMemory, _ERROR_FUNCTION_SIGNATURE)
                // Store data offset
                mstore(add(freeMemory, 0x04), 0x20)
                // Store length of revert string
                mstore(add(freeMemory, 0x24), _INSUFFICIENT_BALANCE_LENGTH)
                // Store revert string
                mstore(add(freeMemory, 0x44), _INSUFFICIENT_BALANCE_MESSAGE)
                revert(freeMemory, 0x64)
            }
            // Subtract transfer amount from current amount of `from`
            let newAmountFrom := sub(currentAmountFrom, amount)

            // Load amount currently stored in `balanceOf[to][id]`
            let currentAmountTo := sload(amountToSlot)
            // Add transfer amount to current amount of `to`
            // Realistically this will never overflow
            let newAmountTo := add(currentAmountTo, amount)

            // Store new amount of `from` in `balanceOf[from][id]`
            sstore(amountFromSlot, newAmountFrom)
            // Store new amount of `to` in `balanceOf[to][id]`
            sstore(amountToSlot, newAmountTo)
        }

        emit TransferSingle(msg.sender, from, to, id, amount);

        if (to.code.length != 0) {
            require(
                ERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, amount, data) ==
                    ERC1155TokenReceiver.onERC1155Received.selector,
                "UNSAFE_RECIPIENT"
            );
        } else require(to != address(0), "INVALID_RECIPIENT");
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public virtual override {
        require(isApprovedForAll[address(0)][msg.sender], "NOT_AUTHORIZED");
        require(ids.length == amounts.length, "LENGTH_MISMATCH");

        // Use assembly to perform optimized balance updates
        // Same balance updates in unoptimized Solidity:
        //
        // for (uint256 i = 0; i < ids.length; ++i) {
        //     uint256 id = ids[i];
        //     uint256 amount = amounts[i];
        //
        //     balanceOf[from][id] -= amount;
        //     balanceOf[to][id] += amount;
        // }
        /// @solidity memory-safe-assembly
        assembly {
            // Calculate the storage slot of `balanceOf[from]`
            // by concatenating the `from` address and the
            // slot of `balanceOf` in the scratch space used
            // by hashing methods, i.e. the first two 32 bytes
            // of memory. The keccak256 hash of the concatenated
            // values is the storage slot we're looking for.
            mstore(0x00, from)
            mstore(0x20, balanceOf.slot)
            let balanceOfFromSlot := keccak256(0x00, 0x40)

            // Calculate storage slot of `balanceOf[to]`
            mstore(0x00, to)
            // 0x20 still contains `balanceOf.slot`
            let balanceOfToSlot := keccak256(0x00, 0x40)

            // Calculate length of arrays `ids` and `amounts` in bytes
            let arrayLength := mul(ids.length, 0x20)

            // Loop over all values in `ids` and `amounts` by starting
            // with an index offset of 0 to access the first array element
            // and incrementing this index by 32 after each iteration to
            // access the next array element until the offset reaches the end
            // of the arrays, at which point all values the arrays contain
            // have been accessed
            for
                { let indexOffset := 0x00 }
                lt(indexOffset, arrayLength)
                { indexOffset := add(indexOffset, 0x20) }
            {
                // Load current array elements by adding offset of current
                // array index to start of each array's data area inside calldata
                let amount := calldataload(add(amounts.offset, indexOffset))

                // Calculate storage slot of `balanceOf[from][id]`
                // Load current id from calldata into the first 32 bytes of memory
                mstore(0x00, calldataload(add(ids.offset, indexOffset)))
                mstore(0x20, balanceOfFromSlot)
                let amountFromSlot := keccak256(0x00, 0x40)

                // Calculate storage slot of `balanceOf[to][id]`
                // 0x00 still contains current id
                mstore(0x20, balanceOfToSlot)
                let amountToSlot := keccak256(0x00, 0x40)

                // Load amount currently stored in `balanceOf[from][id]`
                let currentAmountFrom := sload(amountFromSlot)
                // Revert with message "INSUFFICIENT_BALANCE" if the
                // transfer amount is greater than the current amount
                // of `from` to prevent an integer underflow
                if gt(amount, currentAmountFrom) {
                    let freeMemory := mload(0x40)
                    // Store "Error(string)" signature: bytes32(bytes4(keccak256("Error(string)")))
                    mstore(freeMemory, _ERROR_FUNCTION_SIGNATURE)
                    // Store data offset
                    mstore(add(freeMemory, 0x04), 0x20)
                    // Store length of revert string
                    mstore(add(freeMemory, 0x24), _INSUFFICIENT_BALANCE_LENGTH)
                    // Store revert string
                    mstore(add(freeMemory, 0x44), _INSUFFICIENT_BALANCE_MESSAGE)
                    revert(freeMemory, 0x64)
                }
                // Subtract transfer amount from current amount of `from`
                let newAmountFrom := sub(currentAmountFrom, amount)

                // Load amount currently stored in `balanceOf[to][id]`
                let currentAmountTo := sload(amountToSlot)
                // Add transfer amount to current amount of `to`
                // Realistically this will never overflow
                let newAmountTo := add(currentAmountTo, amount)

                // Store new amount of `from` in `balanceOf[from][id]`
                sstore(amountFromSlot, newAmountFrom)
                // Store new amount of `to` in `balanceOf[to][id]`
                sstore(amountToSlot, newAmountTo)
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        if (to.code.length != 0) {
            require(
                ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) ==
                    ERC1155TokenReceiver.onERC1155BatchReceived.selector,
                "UNSAFE_RECIPIENT"
            );
        } else require(to != address(0), "INVALID_RECIPIENT");
    }

    // ---------- MINT ----------

    function mint(
        address to,
        uint256 id,
        uint256 amount
    ) public {
        require(isApprovedForAll[address(0)][msg.sender], "NOT_AUTHORIZED");

        // Realistically this will never overflow
        unchecked {
            balanceOf[to][id] += amount;
        }

        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }

    function mint(
        address[] calldata addresses,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) public {
        require(addresses.length == ids.length && ids.length == amounts.length, "LENGTH_MISMATCH");

        // Calculate array length in bytes
        uint256 arrayLength;
        unchecked {
            arrayLength = addresses.length * 0x20;
        }

        for (uint256 indexOffset = 0x00; indexOffset < arrayLength;) {
            address addr;
            uint256 id;
            uint256 amount;

            /// @solidity memory-safe-assembly
            assembly {
                // Load current array elements by adding offset of current
                // array index to start of each array's data area inside calldata
                addr := calldataload(add(addresses.offset, indexOffset))
                id := calldataload(add(ids.offset, indexOffset))
                amount := calldataload(add(amounts.offset, indexOffset))

                // Increment index offset by 32 for next iteration
                indexOffset := add(indexOffset, 0x20)
            }

            mint(addr, id, amount);
        }
    }

    function safeMint(
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public {
        mint(to, id, amount);

        if (to.code.length != 0) {
            require(
                ERC1155TokenReceiver(to).onERC1155Received(msg.sender, address(0), id, amount, data) ==
                    ERC1155TokenReceiver.onERC1155Received.selector,
                "UNSAFE_RECIPIENT"
            );
        } else require(to != address(0), "INVALID_RECIPIENT");
    }

    function batchMint(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) public {
        require(isApprovedForAll[address(0)][msg.sender], "NOT_AUTHORIZED");
        require(ids.length == amounts.length, "LENGTH_MISMATCH");

        // Use assembly to perform optimized balance updates
        // Same balance updates in unoptimized Solidity:
        //
        // for (uint256 i = 0; i < ids.length; ++i) {
        //     uint256 id = ids[i];
        //     uint256 amount = amounts[i];
        //
        //     balanceOf[to][id] += amount;
        // }
        /// @solidity memory-safe-assembly
        assembly {
            // Calculate the storage slot of `balanceOf[to]`
            // by concatenating the `to` address and the
            // slot of `balanceOf` in the scratch space used
            // by hashing methods, i.e. the first two 32 bytes
            // of memory. The keccak256 hash of the concatenated
            // values is the storage slot we're looking for.
            mstore(0x00, to)
            mstore(0x20, balanceOf.slot)
            let balanceOfToSlot := keccak256(0x00, 0x40)

            // Store storage slot of `balanceOf[to]` in the second
            // 32 bytes of scratch space to later calculate the storage
            // slot of `balanceOf[to][id]` inside the loop
            mstore(0x20, balanceOfToSlot)

            // Calculate length of arrays `ids` and `amounts` in bytes
            let arrayLength := mul(ids.length, 0x20)

            // Loop over all values in `ids` and `amounts` by starting
            // with an index offset of 0 to access the first array element
            // and incrementing this index by 32 after each iteration to
            // access the next array element until the offset reaches the end
            // of the arrays, at which point all values the arrays contain
            // have been accessed
            for
                { let indexOffset := 0x00 }
                lt(indexOffset, arrayLength)
                { indexOffset := add(indexOffset, 0x20) }
            {
                // Load current array elements by adding offset of current
                // array index to start of each array's data area inside calldata
                let id := calldataload(add(ids.offset, indexOffset))
                let amount := calldataload(add(amounts.offset, indexOffset))

                // Calculate storage slot of `balanceOf[to][id]`
                mstore(0x00, id)
                // 0x20 still contains `balanceOfToSlot`
                let amountToSlot := keccak256(0x00, 0x40)

                // Load amount currently stored in `balanceOf[to][id]`
                let currentAmountTo := sload(amountToSlot)

                // Add mint amount to current amount of `to`
                // Realistically this will never overflow
                let newAmountTo := add(currentAmountTo, amount)

                // Store new amount in `balanceOf[to][id]`
                sstore(amountToSlot, newAmountTo)
            }
        }

        emit TransferBatch(msg.sender, address(0), to, ids, amounts);
    }

    function batchMint(
        address[] calldata addresses,
        uint256[][] calldata ids,
        uint256[][] calldata amounts
    ) public {
        require(addresses.length == ids.length && ids.length == amounts.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < addresses.length;) {
            address addr;

            /// @solidity memory-safe-assembly
            assembly {
                // Load current array element by adding offset of current
                // array index to start of array's data area inside calldata
                let indexOffset := mul(i, 0x20)
                addr := calldataload(add(addresses.offset, indexOffset))
            }

            batchMint(addr, ids[i], amounts[i]);

            unchecked {
                i++;
            }
        }
    }

    function safeBatchMint(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public {
        batchMint(to, ids, amounts);

        if (to.code.length != 0) {
            require(
                ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, address(0), ids, amounts, data) ==
                    ERC1155TokenReceiver.onERC1155BatchReceived.selector,
                "UNSAFE_RECIPIENT"
            );
        } else require(to != address(0), "INVALID_RECIPIENT");
    }

    // ---------- BURN ----------

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) public virtual {
        require(msg.sender == from || isApprovedForAll[address(0)][msg.sender], "NOT_AUTHORIZED");

        // Use assembly to perform optimized balance update
        // Same balance update in unoptimized Solidity:
        //
        // balanceOf[from][id] -= amount;
        //
        /// @solidity memory-safe-assembly
        assembly {
            // Calculate the storage slot of `balanceOf[from]`
            // by concatenating the `from` address and the
            // slot of `balanceOf` in the scratch space used
            // by hashing methods, i.e. the first two 32 bytes
            // of memory. The keccak256 hash of the concatenated
            // values is the storage slot we're looking for.
            mstore(0x00, from)
            mstore(0x20, balanceOf.slot)
            let balanceOfFromSlot := keccak256(0x00, 0x40)

            // Calculate storage slot of `balanceOf[from][id]`
            mstore(0x00, id)
            mstore(0x20, balanceOfFromSlot)
            let amountFromSlot := keccak256(0x00, 0x40)

            // Load amount currently stored in `balanceOf[from][id]`
            let currentAmountFrom := sload(amountFromSlot)
            // Revert with message "INSUFFICIENT_BALANCE" if the burn
            // amount is greater than the current amount of `from` to
            // prevent an integer underflow
            if gt(amount, currentAmountFrom) {
                let freeMemory := mload(0x40)
                // Store "Error(string)" signature: bytes32(bytes4(keccak256("Error(string)")))
                mstore(freeMemory, _ERROR_FUNCTION_SIGNATURE)
                // Store data offset
                mstore(add(freeMemory, 0x04), 0x20)
                // Store length of revert string
                mstore(add(freeMemory, 0x24), _INSUFFICIENT_BALANCE_LENGTH)
                // Store revert string
                mstore(add(freeMemory, 0x44), _INSUFFICIENT_BALANCE_MESSAGE)
                revert(freeMemory, 0x64)
            }
            // Subtract burn amount from current amount of `from`
            let newAmountFrom := sub(currentAmountFrom, amount)

            // Store new amount of `from` in `balanceOf[from][id]`
            sstore(amountFromSlot, newAmountFrom)
        }

        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }

    function batchBurn(
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) public virtual {
        require(msg.sender == from || isApprovedForAll[address(0)][msg.sender], "NOT_AUTHORIZED");
        require(ids.length == amounts.length, "LENGTH_MISMATCH");

        // Use assembly to perform optimized balance updates
        // Same balance updates in unoptimized Solidity:
        //
        // for (uint256 i = 0; i < ids.length; ++i) {
        //     uint256 id = ids[i];
        //     uint256 amount = amounts[i];
        //
        //     balanceOf[from][id] -= amount;
        // }
        /// @solidity memory-safe-assembly
        assembly {
            // Calculate the storage slot of `balanceOf[from]`
            // by concatenating the `from` address and the
            // slot of `balanceOf` in the scratch space used
            // by hashing methods, i.e. the first two 32 bytes
            // of memory. The keccak256 hash of the concatenated
            // values is the storage slot we're looking for.
            mstore(0x00, from)
            mstore(0x20, balanceOf.slot)
            let balanceOfFromSlot := keccak256(0x00, 0x40)

            // Store storage slot of `balanceOf[from]` in the second
            // 32 bytes of scratch space to later calculate the storage
            // slot of `balanceOf[from][id]` inside the loop
            mstore(0x20, balanceOfFromSlot)

            // Calculate length of arrays `ids` and `amounts` in bytes
            let arrayLength := mul(ids.length, 0x20)

            // Loop over all values in `ids` and `amounts` by starting
            // with an index offset of 0 to access the first array element
            // and incrementing this index by 32 after each iteration to
            // access the next array element until the offset reaches the end
            // of the arrays, at which point all values the arrays contain
            // have been accessed
            for
                { let indexOffset := 0x00 }
                lt(indexOffset, arrayLength)
                { indexOffset := add(indexOffset, 0x20) }
            {
                // Load current array elements by adding offset of current
                // array index to start of each array's data area inside calldata
                let id := calldataload(add(ids.offset, indexOffset))
                let amount := calldataload(add(amounts.offset, indexOffset))

                // Calculate storage slot of `balanceOf[from][id]`
                mstore(0x00, id)
                // 0x20 still contains `balanceOfFromSlot`
                let amountFromSlot := keccak256(0x00, 0x40)

                // Load amount currently stored in `balanceOf[from][id]`
                let currentAmountFrom := sload(amountFromSlot)
                // Revert with message "INSUFFICIENT_BALANCE" if the burn
                // amount is greater than the current amount of `from` to
                // prevent an integer underflow
                if gt(amount, currentAmountFrom) {
                    let freeMemory := mload(0x40)
                    // Store "Error(string)" signature: bytes32(bytes4(keccak256("Error(string)")))
                    mstore(freeMemory, _ERROR_FUNCTION_SIGNATURE)
                    // Store data offset
                    mstore(add(freeMemory, 0x04), 0x20)
                    // Store length of revert string
                    mstore(add(freeMemory, 0x24), _INSUFFICIENT_BALANCE_LENGTH)
                    // Store revert string
                    mstore(add(freeMemory, 0x44), _INSUFFICIENT_BALANCE_MESSAGE)
                    revert(freeMemory, 0x64)
                }
                // Subtract burn amount from current amount of `from`
                let newAmountFrom := sub(currentAmountFrom, amount)

                // Store new amount of `from` in `balanceOf[from][id]`
                sstore(amountFromSlot, newAmountFrom)
            }
        }

        emit TransferBatch(msg.sender, from, address(0), ids, amounts);
    }
}

