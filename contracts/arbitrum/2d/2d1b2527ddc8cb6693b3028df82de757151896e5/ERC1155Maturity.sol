// SPDX-License-Identifier: AGPL-3.0-only
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC1155/ERC1155.sol)
// Solmate (tokens/ERC1155.sol)
// Derivable Contracts (ERC1155Maturity)

pragma solidity 0.8.20;

import "./IERC1155Receiver.sol";
import "./IERC1155MetadataURI.sol";

import "./IERC1155Maturity.sol";
import "./TimeBalance.sol";

/// @notice Minimalist and gas efficient standard ERC1155 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC1155.sol)
/// @author Derivable (https://github.com/derivable-labs/erc1155-maturity)
contract ERC1155Maturity is IERC1155Maturity, IERC1155MetadataURI {
    using TimeBalance for uint;

    /*//////////////////////////////////////////////////////////////
                             ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(uint256 => uint256)) internal s_timeBalances;
    mapping(address => mapping(address => bool)) internal s_approvals;

    mapping(uint256 => uint256) internal s_totalSupply;

    string private _uri;

    /**
     * @dev See {_setURI}.
     */
    constructor(string memory uri_) {
        _setURI(uri_);
    }

    /*//////////////////////////////////////////////////////////////
                             METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    function uri(uint256) public view virtual override returns (string memory) {
        return _uri;
    }

    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }

    /*//////////////////////////////////////////////////////////////
                             SUPPLY LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalSupply(uint256 id) public view override virtual returns (uint256) {
        return s_totalSupply[id];
    }

    /*//////////////////////////////////////////////////////////////
                              ERC1155 LOGIC
    //////////////////////////////////////////////////////////////*/

    function setApprovalForAll(address operator, bool approved) public virtual override {
        s_approvals[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public virtual {
        require(to != address(0), "ZERO_RECIPIENT");
        require(msg.sender == from || isApprovedForAll(from, msg.sender), "NOT_AUTHORIZED");
        _safeTransferFrom(from, to, id, amount, data);
    }

    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        uint256 fromBalance = s_timeBalances[from][id];
        uint timelockAmount;
        (s_timeBalances[from][id], timelockAmount) = fromBalance.split(amount);
        s_timeBalances[to][id] = s_timeBalances[to][id].merge(timelockAmount);

        emit TransferSingle(msg.sender, from, to, id, amount);

        _doSafeTransferAcceptanceCheck( msg.sender, from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public virtual {
        require(to != address(0), "ZERO_RECIPIENT");
        uint256 idsLength = ids.length; // Saves MLOADs.
        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        require(msg.sender == from || isApprovedForAll(from, msg.sender), "NOT_AUTHORIZED");

        // Storing these outside the loop saves ~15 gas per iteration.
        uint256 id;

        for (uint256 i = 0; i < idsLength; ) {
            id = ids[i];

            uint timelockAmount;
            (s_timeBalances[from][id], timelockAmount) = s_timeBalances[from][id].split(amounts[i]);
            s_timeBalances[to][id] = s_timeBalances[to][id].merge(timelockAmount);

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        public
        view
        virtual
        returns (uint256[] memory balances)
    {
        require(owners.length == ids.length, "LENGTH_MISMATCH");

        balances = new uint256[](owners.length);

        // Unchecked because the only math done is incrementing
        // the array index counter which cannot possibly overflow.
        unchecked {
            for (uint256 i = 0; i < owners.length; ++i) {
                balances[i] = balanceOf(owners[i], ids[i]);
            }
        }
    }

    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        return s_timeBalances[account][id].getBalance();
    }

    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return s_approvals[account][operator];
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xd9b67a26 || // ERC165 Interface ID for ERC1155
            interfaceId == 0x0e89341c; // ERC165 Interface ID for ERC1155MetadataURI
    }

    /*//////////////////////////////////////////////////////////////
                              MATURITY LOGIC
    //////////////////////////////////////////////////////////////*/
    function maturityOf(address account, uint256 id) public view virtual override returns (uint256) {
        return s_timeBalances[account][id].getTime();
    }

    /**
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function maturityOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    ) public view virtual override returns (uint256[] memory) {
        require(accounts.length == ids.length, "LENGTH_MISMATCH");

        uint256[] memory batchLocktimes = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchLocktimes[i] = maturityOf(accounts[i], ids[i]);
        }

        return batchLocktimes;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        uint256 time,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ZERO_RECIPIENT");
        uint timelockAmount = TimeBalance.pack(amount, time);
        s_timeBalances[to][id] = s_timeBalances[to][id].merge(timelockAmount);
        s_totalSupply[id] += amount;

        emit TransferSingle(msg.sender, address(0), to, id, amount);

        _doSafeTransferAcceptanceCheck(msg.sender, address(0), to, id, amount, data);
    }

    function _batchMint(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        uint256 time,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ZERO_RECIPIENT");
        uint256 idsLength = ids.length; // Saves MLOADs.

        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        // Storing these outside the loop saves ~15 gas per iteration.
        uint256 id;
        uint256 amount;

        for (uint256 i = 0; i < idsLength;) {
            id = ids[i];
            amount = amounts[i];

            uint timelockAmount = TimeBalance.pack(amount, time);
            s_timeBalances[to][id] = s_timeBalances[to][id].merge(timelockAmount);
            s_totalSupply[id] += amount;

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, address(0), to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, address(0), to, ids, amounts, data);
    }

    function _batchBurn(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual {
        uint256 idsLength = ids.length; // Saves MLOADs.

        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        // Storing these outside the loop saves ~15 gas per iteration.
        uint256 id;
        uint256 amount;

        for (uint256 i = 0; i < idsLength; ) {
            id = ids[i];
            amount = amounts[i];

            (s_timeBalances[from][id], ) = s_timeBalances[from][id].split(amount);
            s_totalSupply[id] -= amount;

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, address(0), ids, amounts);
    }

    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal virtual {
        (s_timeBalances[from][id],) = s_timeBalances[from][id].split(amount);
        s_totalSupply[id] -= amount;

        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert("RECEIVER_REJECTED");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("NON_RECEIVER");
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert("RECEIVER_REJECTED");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("NON_RECEIVER");
            }
        }
    }
}

