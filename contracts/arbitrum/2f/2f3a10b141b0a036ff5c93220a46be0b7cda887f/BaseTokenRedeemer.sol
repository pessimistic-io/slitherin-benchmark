// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Errors.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";

/**
 * @title TokenRedeemer
 * @author SyntheX <prasad@chainscore.finance>
 * @notice This contract is used to unlock SYX tokens for users
 * @notice Users can request to unlock their SYX tokens after a lock period
 * @notice Tokens are released linearly over a period of time (unlock period)
 */
contract BaseTokenRedeemer is Initializable {
    /// @notice SafeERC20 library is used for ERC20 operations
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Emitted when user requests to unlock their SYX tokens
    event UnlockRequested(address indexed user, bytes32 requestId, uint amount);
    /// @notice Emitted when user claims their unlocked SYX tokens
    event Unlocked(address indexed user, bytes32 requestId, uint amount);
    /// @notice Emitted when admin sets the lock period
    event SetLockPeriod(uint _lockPeriod);

    /// @notice Unlock data struct
    struct UnlockData {
        uint amount;
        uint claimed;
        uint requestTime;
    }

    /// @notice TOKEN is the address of token be unlocked
    IERC20Upgradeable public TOKEN;
    /// @notice Reserved for unlock is the amount of SYX that is reserved for unlock
    uint public reservedForUnlock;
    /// @notice Lock period is the time (in sec) that user must wait before they can claim their unlocked SYX
    uint public lockPeriod;
    /// @notice Unlock period is the time (in sec) over which tokens are unlocked
    uint public unlockPeriod;
    /// @notice PercUnlockAtRelease is the percentage of tokens that are unlocked at release. In Basis Points
    uint public percUnlockAtRelease;
    uint public constant BASIS_POINTS = 10000;
    uint public constant SCALER = 1e18;
    /// @notice Request ID to Unlock struct mapping
    /// @notice Request ID is a hash of user address and request index
    mapping(bytes32 => UnlockData) public unlockRequests;
    /// @notice User address to request count mapping
    mapping(address => uint) public unlockRequestCount;

    /// @notice gap to allow future variables to be added
    uint256[50] private __gap;

    /**
     * @notice Constructor
     * @param _TOKEN Address of SYX
     */
    function __BaseTokenRedeemer_init(
        address _TOKEN,
        uint _lockPeriod,
        uint _unlockPeriod,
        uint _percUnlockAtRelease
    ) internal onlyInitializing {
        __BaseTokenRedeemer_init_unchained(
            _TOKEN,
            _lockPeriod,
            _unlockPeriod,
            _percUnlockAtRelease
        );
    }

    function __BaseTokenRedeemer_init_unchained(
        address _TOKEN,
        uint _lockPeriod,
        uint _unlockPeriod,
        uint _percUnlockAtRelease
    ) internal onlyInitializing {
        // validate _TOKEN address
        require(_TOKEN != address(0), Errors.INVALID_ADDRESS);
        // check if contract
        require(
            AddressUpgradeable.isContract(_TOKEN),
            Errors.ADDRESS_IS_NOT_CONTRACT
        );
        TOKEN = IERC20Upgradeable(_TOKEN);

        // validate lock/unlock period
        require(_unlockPeriod > 0, Errors.INVALID_ARGUMENT);
        require(
            _percUnlockAtRelease <= BASIS_POINTS,
            Errors.INVALID_ARGUMENT
        );
        lockPeriod = _lockPeriod;
        unlockPeriod = _unlockPeriod;
        percUnlockAtRelease = _percUnlockAtRelease;
    }

    function _startUnlock(address user, uint _amount) internal virtual {
        // check if user has enough SYX to unlock
        require(remainingQuota() >= _amount, Errors.NOT_ENOUGH_SYX_TO_UNLOCK);

        // create unlock request
        bytes32 requestId = keccak256(
            abi.encodePacked(user, unlockRequestCount[user])
        );

        UnlockData storage _unlockRequest = unlockRequests[requestId];
        require(_unlockRequest.amount == 0, Errors.REQUEST_ALREADY_EXISTS);
        _unlockRequest.amount = _amount;
        _unlockRequest.requestTime = block.timestamp;
        _unlockRequest.claimed = 0;

        // increment request count
        unlockRequestCount[user]++;

        // reserve SYX for unlock
        reservedForUnlock += _amount;

        emit UnlockRequested(user, requestId, _amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Claim                                   */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Claim unlocked SYX tokens
     * @param _requestId Request ID of unlock request
     */
    function _unlockInternal(
        address _account,
        bytes32 _requestId
    ) internal virtual {
        // Get amount to unlock
        uint amountToUnlock = unlocked(_requestId);

        // If total amount to unlock is 0, return
        if (amountToUnlock == 0) {
            return;
        }

        // Check if contract has enough SYX to unlock
        if (TOKEN.balanceOf(address(this)) < amountToUnlock) {
            amountToUnlock = TOKEN.balanceOf(address(this));
        }
        TOKEN.safeTransfer(_account, amountToUnlock);

        // Increment claimed amount
        unlockRequests[_requestId].claimed += amountToUnlock;

        // release reserved SYX
        reservedForUnlock -= amountToUnlock;

        emit Unlocked(_account, _requestId, amountToUnlock);
    }

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Gets remaining quota of SYX that can be set to be unlocked
     */
    function remainingQuota() public view virtual returns (uint) {
        return TOKEN.balanceOf(address(this)) - reservedForUnlock;
    }

    /**
     * @notice Returns the amount of tokens that can be claimed by user
     * @dev Calculates the amount based on request data and current time
     * @param _requestId Request ID
     */
    function unlocked(bytes32 _requestId) public view virtual returns (uint) {
        // Check if unlock request exists
        UnlockData memory unlockRequest = unlockRequests[_requestId];
        require(unlockRequest.amount > 0, Errors.REQUEST_DOES_NOT_EXIST);
        // Check if unlock period has passed
        require(
            block.timestamp >= unlockRequest.requestTime + lockPeriod,
            Errors.UNLOCK_NOT_STARTED
        );

        // Calculate amount to unlock
        // Time since unlock date will give percentage of total to unlock, excluding percUnlockAtRelease
        uint timeSinceUnlock = block.timestamp -
            (unlockRequest.requestTime + lockPeriod);
        uint percentUnlock = (timeSinceUnlock * (SCALER)) / (unlockPeriod);

        // If unlock period has passed, unlock 100% of tokens
        if (percentUnlock > SCALER) {
            percentUnlock = SCALER;
        }

        percentUnlock = percentUnlock * (BASIS_POINTS); // convert to basis points

        // Calculate amount to unlock
        // Amount to unlock = totalAmount * (percentUnlock * (1 - percUnlockAtRelease) + percUnlockAtRelease) - alreadyClaimed
        uint amountToUnlock = ((unlockRequest.amount *
            (percentUnlock +
                (percUnlockAtRelease * SCALER) -
                (percentUnlock * percUnlockAtRelease) /
                (BASIS_POINTS))) /
            (SCALER) /
            (BASIS_POINTS)) - (unlockRequest.claimed);

        return amountToUnlock;
    }

    /**
     * @notice Get request ID
     */
    function getRequestId(
        address _user,
        uint _unlockIndex
    ) external pure virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _unlockIndex));
    }
}

