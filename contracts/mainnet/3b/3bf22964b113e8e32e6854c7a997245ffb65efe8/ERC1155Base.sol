// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC1155} from "./IERC1155.sol";
import {IERC1155Receiver} from "./IERC1155Receiver.sol";
import {IERC1155Base} from "./IERC1155Base.sol";
import {ERC1155BaseInternal, ERC1155BaseStorage} from "./ERC1155BaseInternal.sol";

/**
 * @title Base ERC1155 contract
 * @dev derived from https://github.com/OpenZeppelin/openzeppelin-contracts/ (MIT license)
 */
abstract contract ERC1155Base is IERC1155Base, ERC1155BaseInternal {
    /**
     * @inheritdoc IERC1155
     */
    function balanceOf(address account, uint256 id)
        public
        view
        virtual
        returns (uint256)
    {
        return _balanceOf(account, id);
    }

    /**
     * @inheritdoc IERC1155
     */
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        returns (uint256[] memory)
    {
        require(
            accounts.length == ids.length,
            "ERC1155: accounts and ids length mismatch"
        );

        mapping(uint256 => mapping(address => uint256))
            storage balances = ERC1155BaseStorage.layout().balances;

        uint256[] memory batchBalances = new uint256[](accounts.length);

        unchecked {
            for (uint256 i; i < accounts.length; i++) {
                require(
                    accounts[i] != address(0),
                    "ERC1155: batch balance query for the zero address"
                );
                batchBalances[i] = balances[ids[i]][accounts[i]];
            }
        }

        return batchBalances;
    }

    /**
     * @inheritdoc IERC1155
     */
    function isApprovedForAll(address account, address operator)
        public
        view
        virtual
        returns (bool)
    {
        return ERC1155BaseStorage.layout().operatorApprovals[account][operator];
    }

    /**
     * @inheritdoc IERC1155
     */
    function setApprovalForAll(address operator, bool status) public virtual {
        require(
            msg.sender != operator,
            "ERC1155: setting approval status for self"
        );
        ERC1155BaseStorage.layout().operatorApprovals[msg.sender][
            operator
        ] = status;
        emit ApprovalForAll(msg.sender, operator, status);
    }

    /**
     * @inheritdoc IERC1155
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual {
        require(
            from == msg.sender || isApprovedForAll(from, msg.sender),
            "ERC1155: caller is not owner nor approved"
        );
        _safeTransfer(msg.sender, from, to, id, amount, data);
    }

    /**
     * @inheritdoc IERC1155
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual {
        require(
            from == msg.sender || isApprovedForAll(from, msg.sender),
            "ERC1155: caller is not owner nor approved"
        );
        _safeTransferBatch(msg.sender, from, to, ids, amounts, data);
    }

    /**
     * @notice sets the initial price for the token id
     * @param tokenIds token id
     * @param prices initial gwei price for the token
     */
    function setTokensPrice(
        uint256[] memory tokenIds,
        uint256[] memory prices,
        bool isUpdate
    ) internal {
        uint256 length = tokenIds.length;
        require(length == prices.length, "TokenIds and Prices mismatch");
        for (uint256 i = 0; i < length; ) {
            uint256 oldPrice = ERC1155BaseStorage
                .layout()
                .tokenInfo[tokenIds[i]]
                .tokenPrice;
            require(prices[i] > 0, "Price can't be less than 0");
            ERC1155BaseStorage
                .layout()
                .tokenInfo[tokenIds[i]]
                .tokenPrice = prices[i];
            if (isUpdate) {
                emit UpdatedTokenPrice(tokenIds[i], oldPrice, prices[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice gets the price for a token
     * @param tokenId token id
     * @return uint256 as token price in wei
     */
    function tokenPrice(uint256 tokenId) public view virtual returns (uint256) {
        return ERC1155BaseStorage.layout().tokenInfo[tokenId].tokenPrice;
    }

    /**
     * @notice gets the creator address owner of a token
     * @param tokenId token id
     * @return address as creator address owner
     */
    function creatorTokenOwner(uint256 tokenId)
        public
        view
        virtual
        returns (address)
    {
        return ERC1155BaseStorage.layout().tokenInfo[tokenId].creatorAccount;
    }

    /**
     * @notice gets the creator's token ids
     * @param creatorAddress token id
     * @return uint256 array with token ids
     */
    function creatorTokens(address creatorAddress)
        public
        view
        virtual
        returns (uint256[] memory)
    {
        return ERC1155BaseStorage.layout().creatorTokens[creatorAddress];
    }

    /**
     * @notice sets the creator address owner of a token
     * @param tokenId token id
     * @param creatorAccount address account of the creator owner
     */
    function setCreatorTokenOwner(uint256 tokenId, address creatorAccount)
        internal
        virtual
    {
        ERC1155BaseStorage
            .layout()
            .tokenInfo[tokenId]
            .creatorAccount = creatorAccount;
        ERC1155BaseStorage.layout().creatorTokens[creatorAccount].push(tokenId);
    }

    /**
     * @notice gets the percentage assign to a token id
     * @param tokenId token id
     * @return uint8 percentage for token id
     */
    function tokenPercentage(uint256 tokenId)
        public
        view
        virtual
        returns (uint8)
    {
        return ERC1155BaseStorage.layout().tokenInfo[tokenId].percentage;
    }

    /**
     * @notice sets the token percentages
     * @param tokenIds token id
     * @param percentages percentage to calculate the cut for that token id
     */
    function setTokensPercentage(
        uint256[] memory tokenIds,
        uint8[] memory percentages,
        bool isUpdate
    ) internal virtual {
        uint256 length = tokenIds.length;
        require(
            length == percentages.length,
            "Token ids and percentages lenght mismatch"
        );
        for (uint256 i = 0; i < length; ) {
            uint8 oldPercentage = ERC1155BaseStorage
                .layout()
                .tokenInfo[tokenIds[i]]
                .percentage;
            require(
                percentages[i] >= 0 && percentages[i] <= 100,
                "Percentage must be between 0 and 100"
            );
            ERC1155BaseStorage
                .layout()
                .tokenInfo[tokenIds[i]]
                .percentage = percentages[i];

            if (isUpdate) {
                emit UpdatedTokenPercentage(
                    tokenIds[i],
                    oldPercentage,
                    percentages[i]
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    function calculateCreatorCut(uint256 tokenId, uint256 total)
        internal
        virtual
        returns (uint256)
    {
        uint8 percentage = tokenPercentage(tokenId);
        return (total * percentage) / 100;
    }

    /**
     * @notice gets the max mintable supply for a token
     * @param tokenId token id
     * @return uint256 as a token id
     */
    function maxSupply(uint256 tokenId) public view virtual returns (uint256) {
        return ERC1155BaseStorage.layout().tokenInfo[tokenId].maxSupply;
    }

    /**
     * @notice sets the max supply for a token
     * @param tokenId token id
     * @param maxTokenSupply max supply for the token id
     */
    function setTokenMaxSupply(uint256 tokenId, uint256 maxTokenSupply)
        internal
    {
        require(maxTokenSupply > 0, "Max supply must be more than 0.");
        ERC1155BaseStorage
            .layout()
            .tokenInfo[tokenId]
            .maxSupply = maxTokenSupply;
    }
}

