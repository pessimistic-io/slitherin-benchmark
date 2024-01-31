// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {EnumerableSet} from "./EnumerableSet.sol";
import {ERC1155BaseInternal} from "./ERC1155BaseInternal.sol";
import {IERC1155Enumerable} from "./IERC1155Enumerable.sol";
import {Counters} from "./Counters.sol";
import {ERC1155EnumerableInternal, ERC1155EnumerableStorage} from "./ERC1155EnumerableInternal.sol";

/**
 * @title ERC1155 implementation including enumerable and aggregate functions
 */
abstract contract ERC1155Enumerable is
    IERC1155Enumerable,
    ERC1155EnumerableInternal
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using Counters for Counters.Counter;

    Counters.Counter public _tokenIds;

    /**
     * @inheritdoc IERC1155Enumerable
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply(id);
    }

    /**
     * @inheritdoc IERC1155Enumerable
     */
    function totalHolders(uint256 id) public view virtual returns (uint256) {
        return _totalHolders(id);
    }

    /**
     * @inheritdoc IERC1155Enumerable
     */
    function accountsByToken(uint256 id)
        public
        view
        virtual
        returns (address[] memory)
    {
        return _accountsByToken(id);
    }

    /**
     * @inheritdoc IERC1155Enumerable
     */
    function tokensByAccount(address account)
        public
        view
        virtual
        returns (uint256[] memory)
    {
        return _tokensByAccount(account);
    }

    /**
     * @notice generate a new token id everytime is called
     * @return uint256 as a token id
     */
    function getNewTokenId() internal returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        return newTokenId;
    }
}

