// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IBrightPoolTreasury.sol";
import "./BrightPoolWarden.sol";

/**
 * @dev An abstract class defining what a BrightPoolLedger contract has to offer
 */
abstract contract IBrightPoolLedger is Ownable {
    /**
     * @dev Manager instance able to use ledgers functions
     */
    address public manager;

    /**
     * @dev The struct describing a single token amount and address for exchange purpose
     * One should use address(0) to point native blockchain asset.
     */
    struct Asset {
        IERC20 token;
        uint256 amount;
    }

    /**
     * @dev The struct describing a single order information
     */
    struct Order {
        uint256 id;
        Asset ask;
        Asset bid;
        address owner;
        uint256 reward;
        uint256 affId;
        address affRcpt;
    }

    /**
     * @dev The event emitted upon new order added to the ledger
     */
    event NewOrder(
        uint256 indexed id,
        IERC20 indexed askToken,
        IERC20 indexed bidToken,
        address owner,
        uint256 askAmount,
        uint256 bidAmount,
        uint256 reward
    );

    /**
     * @dev The event emitted upon order being cancelled from the ledger
     */
    event ExecutedOrder(uint256 indexed id);

    /**
     * @dev The event emitted upon order being cancelled from the ledger
     */
    event CancelledOrder(uint256 indexed id, uint256 reward);

    /**
     * @dev The event emitted upon new manager address being set for the ledger
     */
    event NewManager(address indexed manager);

    /**
     * @dev The event emitted when native currency is sent to the contract independently
     */
    event EthReceived(address indexed from, uint256 value);

    /**
     * @dev The event emitted when new exchange is added to exchange list
     */
    event NewExchange(address indexed exchange);

    /**
     * @dev The event emitted when the exchange is removed from the exchange list
     */
    event RemovedExchange(uint256 indexed exchangeIndex);

    /**
     * @dev Warden contract for manager changes
     */
    BrightPoolWarden private _warden;

    /**
     * @dev Modifier locking method from being run by third parties not being the manager of the contract
     */
    modifier onlyManager() {
        if (_msgSender() != manager) revert Restricted();
        _;
    }

    constructor(address owner_, BrightPoolWarden warden_) Ownable(owner_) {
        if (address(warden_) == address(0)) revert ZeroAddress();
        _warden = warden_;
    }

    /**
     * @dev Automatic retrieval of ETH funds
     */
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @dev The method for setting new manager of the contract.
     * The method restricted to contract owner.
     *
     * @param manager_ The address of the manager of the contract.
     */
    function setManager(address manager_) external onlyOwner {
        if (address(0) == manager_) revert ZeroAddress();
        if (manager == manager_) revert AlreadySet();

        // slither-disable-start reentrancy-events
        // slither-disable-next-line reentrancy-no-eth
        if (_warden.changeValue(manager_, "manager", address(0))) {
            manager = manager_;
            emit NewManager(manager_);
        }
        // slither-disable-end reentrancy-events
    }

    function _getWarden() internal view returns (BrightPoolWarden) {
        return _warden;
    }

    /**
     * @dev The method to check the owner of created order
     *
     * @param id_ The order id to be checked for the owner
     *
     * @return The owner address
     */
    function ownerOf(uint256 id_) external view virtual returns (address);

    /**
     * @dev The method for making new order signed in the ledger.
     * The method restricted to contract manager only.
     *
     * @param order_ The order struct. It's id has to be unique and cannot be 0
     * @param timeout_ The deadline after which this order can be executed (timestamp)
     */
    function makeOrder(Order calldata order_, uint256 timeout_) external payable virtual;

    /**
     * @dev The method for order execution with success or failure (cancellation).
     * The method restricted to contracts manager only.
     *
     * @param id_ The id of the order to be cancelled.
     * @param revoked_ Is the order revoked or executed should be processed
     * @param rewardConsumed_ The amount of the reward consumed upon order cancellation from the sender
     * @param treasury_ The treasury address to use as potential exchange
     * @param treasuryCap_ The amount cap for treasury usage in this order
     *
     * @return True if executed or reverted successfully, false if order does not exist
     */
    function executeOrder(
        uint256 id_,
        bool revoked_,
        uint256 rewardConsumed_,
        IBrightPoolTreasury treasury_,
        uint256 treasuryCap_
    ) external virtual returns (bool);
}

