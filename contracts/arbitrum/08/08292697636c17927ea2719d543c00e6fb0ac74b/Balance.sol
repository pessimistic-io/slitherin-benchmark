// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IBalance.sol";
import "./IBalanceStorage.sol";

abstract contract Balance is IBalance, INftStorage, IBalanceStorage {
    using StateTypeLib for StateType;
    using IdTypeLib for IdType;
    /**
     * @dev The specified nft state is not supported by the code.
     */
    error UnsupportedState(StateType nftState);
    /**
     * @dev User doesn't have required amount of NFTs of the specified kind on the balance.
     */
    error NotEnoughEmptyNfts(address user);
    error NotEnoughMysteryNfts(address user, uint32 expected, uint32 butGot);
    error NotEnoughRareNfts(address user, uint rarity, uint32 expected, uint32 butGot);

    function _insertNft(address owner, IdType id, NFTDef storage nft) internal override {
        // getting user structs
        NFTCounter storage userBalances = _balances(owner);

        // getting head
        IdType headId = _getHeadId(nft.state, userBalances);

        // inserting a new element to global list
        if (headId != EMPTY_ID) {
            NFTDef storage nftHead = _nft(headId);
            nftHead.left = id;
        }

        nft.left = EMPTY_ID;
        nft.right = headId;

        // setting new head in user struct
        _setHead(id, nft, userBalances);

        // increase counter
        _increaseUserRarityCounter(userBalances, nft);
    }

    function _removeNft(address owner, NFTDef storage nft) internal override {
        // getting user structs
        NFTCounter storage userBalances = _balances(owner);

        // reduce and check counter
        _decreaseUserRarityCounter(owner, userBalances, nft);

        // getting left and right nft ids
        IdType leftId = nft.left;
        IdType rightId = nft.right;

        // linking the right and left elements
        if (leftId != EMPTY_ID) {
            NFTDef storage nftLeft = _nft(leftId);
            nftLeft.right = rightId;
        }
        else {
            // update head if removed NFT hasn't left NFT
            _setHead(rightId, nft, userBalances);
        }

        if (rightId != EMPTY_ID) {
            NFTDef storage nftRight = _nft(rightId);
            nftRight.left = leftId;
        }
    }

    function _getHeadId(address owner, StateType nftState) internal override view returns (IdType) {
        NFTCounter storage userBalances = _balances(owner);
        IdType id = _getHeadId(nftState, userBalances);

        if (id.isEmpty()) {
            _throwError(owner, userBalances, nftState, 1);
        }

        return id;
    }


    /**
     * @notice This method only PRIVATE, because it doesn't check anything.
     */
    function _getHeadId(StateType nftState, NFTCounter storage counters) private view returns (IdType) {
        if (nftState.isMystery()) {
            return counters.mysteryHead;
        }
        else if (nftState.isEmpty()) {
            return counters.emptyHead;
        }
        else if (nftState.isRare()) {
            return counters.rarityIdToHead[nftState.toRarity()];
        }
        else {
            revert UnsupportedState(nftState);
        }
    }

    function _getTotalNftCount(address owner) internal override view returns (uint) {
        NFTCounter storage balances = _balances(owner);
        uint total = balances.emptyCount + balances.mysteryCount;

        for(uint i = 0; i < balances.rarityIdToCount.length; ++i) {
            total += balances.rarityIdToCount[i];
        }

        return total;
    }

    function _setHead(IdType id, NFTDef storage nft, NFTCounter storage counters) private {
        StateType nftState = nft.state;
        if (nftState.isMystery()) {
            counters.mysteryHead = id;
        }
        else if (nftState.isEmpty()) {
            counters.emptyHead = id;
        }
        else if (nftState.isRare()) {
            counters.rarityIdToHead[nftState.toRarity()] = id;
        }
        else {
            revert UnsupportedState(nftState);
        }
    }

    function _increaseUserRarityCounter(NFTCounter storage counters, NFTDef storage nft) private {
        StateType nftState = nft.state;
        if (nftState.isMystery()) {
            counters.mysteryCount++;
        }
        else if (nftState.isEmpty()) {
            counters.emptyCount++;
        }
        else if (nftState.isRare()) {
            counters.rarityIdToCount[nftState.toRarity()]++;
        }
        else {
            revert UnsupportedState(nftState);
        }
    }

    function _decreaseUserRarityCounter(address owner, NFTCounter storage userCounters, NFTDef storage nft) private {
        _decreaseUserRarityCounter(owner, userCounters, nft.state, 1);
    }


    function _decreaseUserRarityCounter(address owner, NFTCounter storage counters, StateType nftState, uint32 count) private {
        if (nftState.isMystery()) {
            if (counters.mysteryCount < count) {
                revert NotEnoughMysteryNfts(owner, count, counters.mysteryCount);
            }
            unchecked {
                counters.mysteryCount -= count;
            }
        }
        else if (nftState.isEmpty()) {
            if (counters.emptyCount < count) {
                revert NotEnoughEmptyNfts(owner);
            }
            unchecked {
                counters.emptyCount -= count;
            }
        }
        else if (nftState.isRare()) {
            uint rarity = nftState.toRarity();
            if (counters.rarityIdToCount[rarity] < count) {
                revert NotEnoughRareNfts(owner, rarity, count, counters.rarityIdToCount[rarity]);
            }
            unchecked {
                counters.rarityIdToCount[rarity] -= count;
            }
        }
        else {
            revert UnsupportedState(nftState);
        }
    }

    function _throwError(address owner, NFTCounter storage counters, StateType nftState, uint32 count) private view {
        if (nftState.isMystery()) {
            revert NotEnoughMysteryNfts(owner, count, counters.mysteryCount);
        }
        else if (nftState.isEmpty()) {
            revert NotEnoughEmptyNfts(owner);
        }
        else if (nftState.isRare()) {
            revert NotEnoughRareNfts(owner, nftState.toRarity(), count, counters.rarityIdToCount[nftState.toRarity()]);
        }
        else {
            revert UnsupportedState(nftState);
        }
    }
}

