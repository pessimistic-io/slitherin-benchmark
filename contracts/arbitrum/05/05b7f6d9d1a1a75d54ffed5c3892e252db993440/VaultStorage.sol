// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAuction.sol";

import "./IPricer.sol";

import "./IQueue.sol";

/**
 * @title Knox Vault Diamond Storage Library
 */

library VaultStorage {
    struct InitProxy {
        bool isCall;
        int128 delta64x64;
        int128 reserveRate64x64;
        int128 performanceFee64x64;
        string name;
        string symbol;
        address keeper;
        address feeRecipient;
        address pricer;
        address pool;
    }

    struct InitImpl {
        address auction;
        address queue;
        address pricer;
    }

    struct Option {
        // option expiration timestamp
        uint64 expiry;
        // option strike price
        int128 strike64x64;
        // option long token id
        uint256 longTokenId;
        // option short token id
        uint256 shortTokenId;
    }

    struct Layout {
        // base asset decimals
        uint8 baseDecimals;
        // underlying asset decimals
        uint8 underlyingDecimals;
        // option type, true if option is a call
        bool isCall;
        // auction processing flag, true if auction has been processed
        bool auctionProcessed;
        // vault option delta
        int128 delta64x64;
        // mapping of options to epoch id (epoch id -> option)
        mapping(uint64 => Option) options;
        // epoch id
        uint64 epoch;
        // auction start offset in seconds (startOffset = startTime - expiry)
        uint256 startOffset;
        // auction end offset in seconds (endOffset = endTime - expiry)
        uint256 endOffset;
        // auction start timestamp
        uint256 startTime;
        // total asset amount withdrawn during an epoch
        uint256 totalWithdrawals;
        // total asset amount not including premiums collected from the auction
        uint256 lastTotalAssets;
        // total premium collected during the auction
        uint256 totalPremium;
        // performance fee collected during epoch initialization
        uint256 fee;
        // percentage of asset to be held as reserves
        int128 reserveRate64x64;
        // percentage of fees taken from net income
        int128 performanceFee64x64;
        // fee recipient address
        address feeRecipient;
        // keeper bot address
        address keeper;
        // Auction contract interface
        IAuction Auction;
        // Queue contract interface
        IQueue Queue;
        // Pricer contract interface
        IPricer Pricer;
    }

    bytes32 internal constant LAYOUT_SLOT =
        keccak256("knox.contracts.storage.Vault");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = LAYOUT_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @notice returns the current epoch
     * @return current epoch id
     */
    function _getEpoch() internal view returns (uint64) {
        return layout().epoch;
    }

    /**
     * @notice returns the option by epoch id
     * @return option parameters
     */
    function _getOption(uint64 epoch) internal view returns (Option memory) {
        return layout().options[epoch];
    }
}

