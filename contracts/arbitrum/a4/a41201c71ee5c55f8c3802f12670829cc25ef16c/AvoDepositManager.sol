// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { Initializable } from "./lib_Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";

import { IAvoFactory } from "./IAvoFactory.sol";

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title    AvoDepositManager v3.0.0
/// @notice   Handles deposits in a deposit token (e.g. USDC).
/// Note: user balances are tracked off-chain through events by the Avocado infrastructure.
///
/// Upgradeable through AvoDepositManagerProxy
interface AvoDepositManager_V3 {

}

abstract contract AvoDepositManagerConstants {
    /// @notice address of the deposit token (USDC)
    IERC20 public immutable depositToken;

    /// @notice address of the AvoFactory (proxy)
    IAvoFactory public immutable avoFactory;

    constructor(IERC20 depositToken_, IAvoFactory avoFactory_) {
        depositToken = depositToken_;
        avoFactory = avoFactory_;
    }
}

abstract contract AvoDepositManagerStructs {
    /// @notice struct to represent a withdrawal request in storage mapping
    struct WithdrawRequest {
        address to;
        uint256 amount;
    }
}

abstract contract AvoDepositManagerVariables is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    AvoDepositManagerStructs,
    AvoDepositManagerConstants
{
    // @dev variables here start at storage slot 151, before is:
    // - Initializable with storage slot 0:
    // uint8 private _initialized;
    // bool private _initializing;
    // - PausableUpgradeable with slots 1 to 100:
    // uint256[50] private __gap; (from ContextUpgradeable, slot 1 until slot 50)
    // bool private _paused; (at slot 51)
    // uint256[49] private __gap; (slot 52 until slot 100)
    // - OwnableUpgradeable with slots 100 to 150:
    // address private _owner; (at slot 101)
    // uint256[49] private __gap; (slot 102 until slot 150)

    // ---------------- slot 151 -----------------

    /// @notice address to which funds can be withdrawn to. Configurable by owner.
    address public withdrawAddress;

    /// @notice minimum amount which must stay in contract and can not be withdrawn. Configurable by owner.
    uint96 public withdrawLimit;

    // ---------------- slot 152 -----------------

    /// @notice static withdraw fee charged when a withdrawRequest is processed. Configurable by owner.
    uint96 public withdrawFee;

    /// @notice minimum withdraw amount that a user must request to withdraw. Configurable by owner.
    uint96 public minWithdrawAmount;

    // 8 bytes empty

    // ---------------- slot 153 -----------------

    /// @notice allowed auths list (1 = allowed) that can confirm withdraw requests. Configurable by owner.
    mapping(address => uint256) public auths;

    // ---------------- slot 154 -----------------

    /// @notice withdraw requests. unique id -> WithdrawRequest (amount and receiver)
    mapping(bytes32 => WithdrawRequest) public withdrawRequests;
}

abstract contract AvoDepositManagerEvents {
    /// @notice emitted when a deposit occurs through `depositOnBehalf()`
    event Deposit(address indexed sender, address indexed avoSafe, uint256 indexed amount);

    /// @notice emitted when a user requests a withdrawal
    event WithdrawRequested(bytes32 indexed id, address indexed avoSafe, uint256 indexed amount);

    /// @notice emitted when a withdraw request is executed
    event WithdrawProcessed(bytes32 indexed id, address indexed user, uint256 indexed amount, uint256 fee);

    /// @notice emitted when a withdraw request is removed
    event WithdrawRemoved(bytes32 indexed id);

    /// @notice emitted when someone requests a source withdrawal
    event SourceWithdrawRequested(bytes32 indexed id, address indexed user, uint256 indexed amount);

    // ------------------------ Settings events ------------------------
    /// @notice emitted when the withdrawLimit is modified by owner
    event SetWithdrawLimit(uint96 indexed withdrawLimit);
    /// @notice emitted when the withdrawFee is modified by owner
    event SetWithdrawFee(uint96 indexed withdrawFee);
    /// @notice emitted when the minWithdrawAmount is modified by owner
    event SetMinWithdrawAmount(uint96 indexed minWithdrawAmount);
    /// @notice emitted when the withdrawAddress is modified by owner
    event SetWithdrawAddress(address indexed withdrawAddress);
    /// @notice emitted when the auths are modified by owner
    event SetAuth(address indexed auth, bool indexed allowed);
}

abstract contract AvoDepositManagerErrors {
    /// @notice thrown when `msg.sender` is not authorized to access requested functionality
    error AvoDepositManager__Unauthorized();

    /// @notice thrown when invalid params for a method are submitted, e.g. zero address as input param
    error AvoDepositManager__InvalidParams();

    /// @notice thrown when a withdraw request already exists
    error AvoDepositManager__RequestAlreadyExist();

    /// @notice thrown when a withdraw request does not exist
    error AvoDepositManager__RequestNotExist();

    /// @notice thrown when a withdraw request does not at least request `minWithdrawAmount`
    error AvoDepositManager__MinWithdraw();

    /// @notice thrown when a withdraw request amount does not cover the withdraw fee at processing time
    error AvoDepositManager__FeeNotCovered();
}

abstract contract AvoDepositManagerCore is
    AvoDepositManagerConstants,
    AvoDepositManagerVariables,
    AvoDepositManagerErrors,
    AvoDepositManagerEvents
{
    /***********************************|
    |              MODIFIERS            |
    |__________________________________*/

    /// @dev checks if an address is not the zero address
    modifier validAddress(address address_) {
        if (address_ == address(0)) {
            revert AvoDepositManager__InvalidParams();
        }
        _;
    }

    /// @dev checks if `msg.sender` is an allowed auth
    modifier onlyAuths() {
        // @dev using inverted positive case to save gas
        if (!(auths[msg.sender] == 1 || msg.sender == owner())) {
            revert AvoDepositManager__Unauthorized();
        }
        _;
    }

    /// @dev checks if `address_` is an Avocado smart wallet (through the AvoFactory)
    modifier onlyAvoSafe(address address_) {
        if (avoFactory.isAvoSafe(address_) == false) {
            revert AvoDepositManager__Unauthorized();
        }
        _;
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(
        IERC20 depositToken_,
        IAvoFactory avoFactory_
    )
        validAddress(address(depositToken_))
        validAddress(address(avoFactory_))
        AvoDepositManagerConstants(depositToken_, avoFactory_)
    {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /***********************************|
    |               INTERNAL            |
    |__________________________________*/

    /// @dev handles a withdraw request for `amount_` for `msg.sender`, giving it a `uniqueId_` and storing it
    function _handleRequestWithdraw(uint256 amount_) internal returns (bytes32 uniqueId_) {
        if (amount_ < minWithdrawAmount || amount_ == 0) {
            revert AvoDepositManager__MinWithdraw();
        }

        // get a unique id based on block timestamp, sender and amount
        uniqueId_ = keccak256(abi.encode(block.timestamp, msg.sender, amount_));

        if (withdrawRequests[uniqueId_].amount > 0) {
            revert AvoDepositManager__RequestAlreadyExist();
        }

        withdrawRequests[uniqueId_] = WithdrawRequest(msg.sender, amount_);
    }
}

abstract contract AvoDepositManagerOwnerActions is AvoDepositManagerCore {
    /// @notice                 Sets new withdraw limit. Only callable by owner.
    /// @param withdrawLimit_   new value
    function setWithdrawLimit(uint96 withdrawLimit_) external onlyOwner {
        withdrawLimit = withdrawLimit_;
        emit SetWithdrawLimit(withdrawLimit_);
    }

    /// @notice                 Sets new withdraw fee (in absolute amount). Only callable by owner.
    /// @param withdrawFee_     new value
    function setWithdrawFee(uint96 withdrawFee_) external onlyOwner {
        // minWithdrawAmount must cover the withdrawFee at all times
        if (minWithdrawAmount < withdrawFee_) {
            revert AvoDepositManager__InvalidParams();
        }
        withdrawFee = withdrawFee_;
        emit SetWithdrawFee(withdrawFee_);
    }

    /// @notice                     Sets new min withdraw amount. Only callable by owner.
    /// @param minWithdrawAmount_   new value
    function setMinWithdrawAmount(uint96 minWithdrawAmount_) external onlyOwner {
        // minWithdrawAmount must cover the withdrawFee at all times
        if (minWithdrawAmount_ < withdrawFee) {
            revert AvoDepositManager__InvalidParams();
        }
        minWithdrawAmount = minWithdrawAmount_;
        emit SetMinWithdrawAmount(minWithdrawAmount_);
    }

    /// @notice                   Sets new withdraw address. Only callable by owner.
    /// @param withdrawAddress_   new value
    function setWithdrawAddress(address withdrawAddress_) external onlyOwner validAddress(withdrawAddress_) {
        withdrawAddress = withdrawAddress_;
        emit SetWithdrawAddress(withdrawAddress_);
    }

    /// @notice                   Sets an address as allowed auth or not. Only callable by owner.
    /// @param auth_              address to set auth value for
    /// @param allowed_           bool flag for whether address is allowed as auth or not
    function setAuth(address auth_, bool allowed_) external onlyOwner validAddress(auth_) {
        auths[auth_] = allowed_ ? 1 : 0;
        emit SetAuth(auth_, allowed_);
    }

    /// @notice unpauses the contract, re-enabling withdraw requests and processing. Only callable by owner.
    function unpause() external onlyOwner {
        _unpause();
    }
}

abstract contract AvoDepositManagerAuthsActions is AvoDepositManagerCore {
    using SafeERC20 for IERC20;

    /// @notice             Authorizes and processes a withdraw request. Only callable by auths & owner.
    /// @param withdrawId_  unique withdraw request id as created in `requestWithdraw()`
    function processWithdraw(bytes32 withdrawId_) external onlyAuths whenNotPaused {
        WithdrawRequest memory withdrawRequest_ = withdrawRequests[withdrawId_];

        if (withdrawRequest_.amount == 0) {
            revert AvoDepositManager__RequestNotExist();
        }

        uint256 withdrawFee_ = withdrawFee;

        if (withdrawRequest_.amount < withdrawFee_) {
            // withdrawRequest_.amount could be < withdrawFee if config value was modified after request was created
            revert AvoDepositManager__FeeNotCovered();
        }

        uint256 withdrawAmount_;
        unchecked {
            // because of if statement above we know this can not underflow
            withdrawAmount_ = withdrawRequest_.amount - withdrawFee_;
        }
        delete withdrawRequests[withdrawId_];

        depositToken.safeTransfer(withdrawRequest_.to, withdrawAmount_);

        emit WithdrawProcessed(withdrawId_, withdrawRequest_.to, withdrawAmount_, withdrawFee_);
    }

    /// @notice pauses the contract, temporarily blocking withdraw requests and processing.
    ///         Only callable by auths & owner. Unpausing can only be triggered by owner.
    function pause() external onlyAuths {
        _pause();
    }
}

contract AvoDepositManager is AvoDepositManagerCore, AvoDepositManagerOwnerActions, AvoDepositManagerAuthsActions {
    using SafeERC20 for IERC20;

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(IERC20 depositToken_, IAvoFactory avoFactory_) AvoDepositManagerCore(depositToken_, avoFactory_) {}

    /// @notice         initializes the contract for `owner_` as owner, and various config values regarding withdrawals.
    ///                 Starts the contract in paused state.
    /// @param owner_              address of owner authorized to withdraw funds and set config values, auths etc.
    /// @param withdrawAddress_    address to which funds can be withdrawn to
    /// @param withdrawLimit_      minimum amount which must stay in contract and can not be withdrawn
    /// @param minWithdrawAmount_  static withdraw fee charged when a withdrawRequest is processed
    /// @param withdrawFee_        minimum withdraw amount that a user must request to withdraw
    function initialize(
        address owner_,
        address withdrawAddress_,
        uint96 withdrawLimit_,
        uint96 minWithdrawAmount_,
        uint96 withdrawFee_
    ) public initializer validAddress(owner_) validAddress(withdrawAddress_) {
        // minWithdrawAmount must cover the withdrawFee at all times
        if (minWithdrawAmount_ < withdrawFee_) {
            revert AvoDepositManager__InvalidParams();
        }

        _transferOwnership(owner_);

        // contract will be paused at start, must be manually unpaused
        _pause();

        withdrawAddress = withdrawAddress_;
        withdrawLimit = withdrawLimit_;
        minWithdrawAmount = minWithdrawAmount_;
        withdrawFee = withdrawFee_;
    }

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    /// @notice checks if a certain address `auth_` is an allowed auth
    function isAuth(address auth_) external view returns (bool) {
        return auths[auth_] == 1 || auth_ == owner();
    }

    /// @notice           Deposits `amount_` of deposit token to this contract and emits the `Deposit` event,
    ///                   with `receiver_` address used for off-chain tracking
    /// @param receiver_  address receiving funds via indirect off-chain tracking
    /// @param amount_    amount to deposit
    function depositOnBehalf(address receiver_, uint256 amount_) external validAddress(receiver_) {
        // @dev we can't use onlyAvoSafe modifier here because it would only work for an already deployed AvoSafe
        depositToken.safeTransferFrom(msg.sender, address(this), amount_);

        emit Deposit(msg.sender, receiver_, amount_);
    }

    /// @notice             removes a withdraw request, essentially denying it or retracting it.
    ///                     Only callable by auths or withdraw request receiver.
    /// @param withdrawId_  unique withdraw request id as created in `requestWithdraw()`
    function removeWithdrawRequest(bytes32 withdrawId_) external {
        WithdrawRequest memory withdrawRequest_ = withdrawRequests[withdrawId_];

        if (withdrawRequest_.amount == 0) {
            revert AvoDepositManager__RequestNotExist();
        }

        // only auths (& owner) or withdraw request receiver can remove a withdraw request
        // using inverted positive case to save gas
        if (!(auths[msg.sender] == 1 || msg.sender == owner() || msg.sender == withdrawRequest_.to)) {
            revert AvoDepositManager__Unauthorized();
        }

        delete withdrawRequests[withdrawId_];

        emit WithdrawRemoved(withdrawId_);
    }

    /// @notice Withdraws balance of deposit token down to `withdrawLimit` to the configured `withdrawAddress`
    function withdraw() external {
        IERC20 depositToken_ = depositToken;
        uint256 withdrawLimit_ = withdrawLimit;

        uint256 balance_ = depositToken_.balanceOf(address(this));
        if (balance_ > withdrawLimit_) {
            uint256 withdrawAmount_;
            unchecked {
                // can not underflow because of if statement just above
                withdrawAmount_ = balance_ - withdrawLimit_;
            }

            depositToken_.safeTransfer(withdrawAddress, withdrawAmount_);
        }
    }

    /// @notice         Requests withdrawal of `amount_`  of gas balance. Only callable by Avocado smart wallets.
    /// @param amount_  amount to withdraw
    /// @return         uniqueId_ the unique withdraw request id used to trigger processing
    function requestWithdraw(
        uint256 amount_
    ) external whenNotPaused onlyAvoSafe(msg.sender) returns (bytes32 uniqueId_) {
        uniqueId_ = _handleRequestWithdraw(amount_);
        emit WithdrawRequested(uniqueId_, msg.sender, amount_);
    }

    /// @notice         same as `requestWithdraw()` but anyone can request withdrawal of funds, not just
    ///                 Avocado smart wallets. Used for the Revenue sharing program.
    /// @param amount_  amount to withdraw
    /// @return         uniqueId_ the unique withdraw request id used to trigger processing
    function requestSourceWithdraw(uint256 amount_) external whenNotPaused returns (bytes32 uniqueId_) {
        uniqueId_ = _handleRequestWithdraw(amount_);
        emit SourceWithdrawRequested(uniqueId_, msg.sender, amount_);
    }
}

