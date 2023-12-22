//SPDX-License-Identifier: MIT
import "./IERC721.sol";
import "./EpochBasedLimiter.sol";

pragma solidity 0.8.17;

abstract contract ERC721BridgeRateLimiter is EpochBasedLimiter {

    // Addresses
    IERC721[5] public nfts;
    
    // Pending claims (user => tokenId => PendingClaim)
    struct PendingClaim {
        NftTier nftTier;
        uint claimTimestamp;
    }
    mapping(address => mapping(uint => PendingClaim)) public pendingClaims;
    mapping (address => uint[]) public pendingTokenIds;

    // Enums
    enum NftTier {
        BRONZE,
        SILVER,
        GOLD,
        PLATINUM,
        DIAMOND
    }

    // Events
    event Locked(address indexed from, NftTier indexed nftTier, uint indexed tokenId);
    event Unlocked(address indexed to, NftTier indexed nftTier, uint indexed tokenId);
    event PendingClaimUpdated(address indexed to, NftTier indexed nftTier, uint indexed tokenId, uint claimTimestamp);
    event PendingClaimExecuted(address indexed to, NftTier indexed nftTier, uint indexed tokenId);

    constructor(
        IERC721[5] memory _nfts,
        address _owner,
        uint _maxEpochLimit,
        uint _epochDuration,
        uint _epochLimit
    ) EpochBasedLimiter(
        _owner,
        _maxEpochLimit,
        _epochDuration,
        _epochLimit
    ) {
        for(uint i; i < _nfts.length; i++){
            require(address(_nfts[i]) != address(0), "ADDRESS_0");
        }

        nfts = _nfts;
    }

    // @dev Implemented by child contract depending if transfer to bridge or burn (transfer by default)
    function _lockNft(address from, NftTier nftTier, uint tokenId) internal virtual {
        nfts[uint(nftTier)].transferFrom(from, address(this), tokenId);
    }

    // @dev Implemented by child contract depending if transfer to user or mint (transfer by default)
    function _unlockNft(address to, NftTier nftTier, uint tokenId) internal virtual {
        nfts[uint(nftTier)].transferFrom(address(this), to, tokenId);
    }

    // @dev Initiating the bridging. Throttled by blacklist.
    function tryLockNft(address from, NftTier nftTier, uint tokenId) internal whenNotPaused {
        require(!blacklist[from], "BLACKLISTED");
        _lockNft(from, nftTier, tokenId);
        
        emit Locked(from, nftTier, tokenId);
    }

    // @dev Executing the second part of the bridging. Throttled by epoch limit and blacklist.
    function tryUnlockNft(address to, NftTier nftTier, uint tokenId) internal whenNotPaused {
        require(!blacklist[to], "BLACKLISTED");
        
        tryUpdateEpoch();

        uint newCurrentEpochCount = currentEpochCount + 1;

        // If mint amount is greater than epoch limit, add to pending claims and emit event
        if (newCurrentEpochCount > epochLimit) {
            addPendingClaim(to, nftTier, tokenId);
            return;
        }

        currentEpochCount = newCurrentEpochCount;
        _unlockNft(to, nftTier, tokenId);

        emit Unlocked(to, nftTier, tokenId);
    }

    // @dev Add pending claim when throttled by epoch limit
    function addPendingClaim(address to, NftTier nftTier, uint tokenId) internal {
        PendingClaim storage pendingClaim = pendingClaims[to][tokenId];
        pendingClaim.nftTier = nftTier;
        pendingClaim.claimTimestamp = block.timestamp + epochDuration;

        pendingTokenIds[to].push(tokenId);

        emit PendingClaimUpdated(to, nftTier, tokenId, pendingClaim.claimTimestamp);
    }

    // @notice Executes pending claim for receiver. Throttled by epoch limit and blacklist.
    function executePendingClaim(address receiver, NftTier nftTier, uint tokenId) external whenNotPaused {
        PendingClaim storage pendingClaim = pendingClaims[receiver][tokenId];
        
        require(pendingClaim.nftTier == nftTier, "WRONG_NFT_TIER");
        require(pendingClaim.claimTimestamp > 0, "NO_PENDING_CLAIM");
        require(pendingClaim.claimTimestamp <= block.timestamp, "TOO_EARLY");
        require(!blacklist[receiver], "RECEIVER_BLACKLISTED");

        tryUpdateEpoch();
        require(++currentEpochCount <= epochLimit, "EPOCH_LIMIT_REACHED");

        delete pendingClaims[receiver][tokenId];
        _unlockNft(receiver, nftTier, tokenId);
        
        emit PendingClaimExecuted(receiver, nftTier, tokenId);
    }

    // @dev Util for fetching list of pending token ids for a wallet
    function getPendingTokenIds(address wallet) external view returns (uint[] memory) {
        return pendingTokenIds[wallet];
    }
}

