//SPDX-License-Identifier: MIT
import "./Math.sol";

import "./IERC20MintableBurnable.sol";
import "./EpochBasedLimiter.sol";

pragma solidity 0.8.17;

abstract contract ERC20BridgeRateLimiter is EpochBasedLimiter {

    // Addresses
    IERC20MintableBurnable public token;

    // Pending claims
    struct PendingClaim {
        uint amount;
        uint claimTimestamp;
    }
    mapping(address => PendingClaim) public pendingClaims;

    // Events
    event Burned(address indexed from, uint amount);
    event Minted(address indexed to, uint amount);
    event PendingClaimUpdated(address indexed to, uint amount, uint claimTimestamp);
    event PendingClaimExecuted(address indexed to, uint amount);

    constructor(
        IERC20MintableBurnable _token,
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
        require(address(_token) != address(0), "ADDRESS_0");
        token = _token;
    }

    // @dev Initiating the bridging. Throttled by epoch limit and blacklist.
    function tryBurn(address from, uint amount) internal whenNotPaused {
        require(amount <= epochLimit, "AMOUNT_TOO_HIGH");
        require(!blacklist[from], "BLACKLISTED");
        token.burn(from, amount);
        
        emit Burned(from, amount);
    }

    // @dev Executing the second part of the bridging. Throttled by epoch limit and blacklist.
    function tryMint(address to, uint amount) internal whenNotPaused {
        require(amount <= MAX_EPOCH_LIMIT, "AMOUNT_TOO_HIGH");
        require(!blacklist[to], "BLACKLISTED");
        
        tryUpdateEpoch();

        uint mintAmount = Math.min(
            amount,
            epochLimit - Math.min(epochLimit, currentEpochCount)
        );

        // If epoch limit reached, add to pending claims and emit event
        if (mintAmount < amount) {
            addPendingClaim(to, amount - mintAmount);
        }

        currentEpochCount += mintAmount;
        token.mint(to, mintAmount);

        emit Minted(to, mintAmount);
    }

    // @dev Add pending claim when throttled by epoch limit
    function addPendingClaim(address to, uint amount) internal {
        PendingClaim storage pendingClaim = pendingClaims[to];
        pendingClaim.amount += amount;
        pendingClaim.claimTimestamp = block.timestamp + epochDuration;

        emit PendingClaimUpdated(to, pendingClaim.amount, pendingClaim.claimTimestamp);
    }

    // @notice Executes pending claim for receiver. Throttled by epoch limit and blacklist.
    function executePendingClaim(address receiver) external whenNotPaused {
        PendingClaim storage pendingClaim = pendingClaims[receiver];

        require(pendingClaim.amount > 0, "NO_PENDING_CLAIM");
        require(pendingClaim.claimTimestamp <= block.timestamp, "TOO_EARLY");
        require(!blacklist[receiver], "RECEIVER_BLACKLISTED");

        tryUpdateEpoch();

        uint claimAmount = Math.min(
            pendingClaim.amount,
            epochLimit - Math.min(epochLimit, currentEpochCount)
        );

        pendingClaim.amount -= claimAmount;

        if (pendingClaim.amount > 0) {
            pendingClaim.claimTimestamp = block.timestamp + epochDuration;

            emit PendingClaimUpdated(
                receiver,
                pendingClaim.amount,
                pendingClaim.claimTimestamp
            );
        }

        currentEpochCount += claimAmount;
        token.mint(receiver, claimAmount);

        emit PendingClaimExecuted(receiver, claimAmount);
    }
}

