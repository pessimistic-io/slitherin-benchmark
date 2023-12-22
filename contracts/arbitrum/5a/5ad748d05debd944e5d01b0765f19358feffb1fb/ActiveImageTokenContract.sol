// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC1155Burnable.sol";
import "./IERC1155Receiver.sol";

//import "hardhat/console.sol";

contract ActiveImageTokenContract is ERC1155, Ownable, Pausable, ERC1155Burnable {
    constructor() ERC1155("https://registry.activeimage.io/images/{id}") {}
 
    // Implementation of the Split ID bits standard
    // https://eips.ethereum.org/EIPS/eip-1155#split-id-bits

    // Store the type in the upper 128 bits
    uint256 public constant TYPE_MASK = uint256(type(uint128).max) << 128;

    // Store the non-fungible index in the lower 128
    uint256 public constant NF_INDEX_MASK = type(uint128).max;

    function getIndex(uint256 _id) public pure returns(uint256) {
        return _id & NF_INDEX_MASK;
    }
    function getBaseType(uint256 _id) public pure returns(uint256) {
        return _id & TYPE_MASK;
    }

    mapping(uint256 => address) public tokenOwners;

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        onlyOwner
    {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyOwner
    {
        _mintBatch(to, ids, amounts, data);
    }

    function setApprovalForAll(address owner, address operator, bool approved) public onlyOwner {
        _setApprovalForAll(owner, operator, approved);
    }

    /**
     * override

     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` (or `baseType`, id tokenOwners[`id`] does not exist) of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.

     * if the index == 0, it is the fungible pool of edition prints that haven't been assigned in memory yet
     * if the index == 1, it is the original
     * if the index > 1, it is an edition print

     * index > 1 && tokenOwners[id] == 0 (we are going to identify a token for the first time)
     * index == 0 || (we are transferring an amount of fungible tokens)
     * index == 1 || (we are transferring the original)
     * index > 1 && tokenOwners[id] > 0 (we are transferring a previously transferred edition print) 
     */

    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal override virtual {
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        uint256 baseType = getBaseType(id);
        uint256 index = getIndex(id);

        require(index == 0 || amount <= 1, "Cannot transfer more than one of a unique token");
        uint256 source = tokenOwners[id] == address(0) ? baseType : id;
        uint256 fromBalance = _balances[source][from];

        require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");

        _beforeTokenTransfer(operator, from, to, _asSingletonArray(id), _asSingletonArray(amount), data);

        unchecked {
            _balances[source][from] = fromBalance - amount;
        }
        _balances[id][to] += amount;

        emit TransferSingle(operator, from, to, id, amount);

        _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            if (getIndex(ids[i]) > 0) {
                tokenOwners[ids[i]] = to;
            }
        }
    }
}

