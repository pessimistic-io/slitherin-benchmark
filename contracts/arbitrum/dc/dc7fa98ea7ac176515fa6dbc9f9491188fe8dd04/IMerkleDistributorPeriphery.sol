// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

import {IERC20} from "./ERC20_IERC20.sol";
import {IMerkleDistributorWithDeadline} from "./IMerkleDistributorWithDeadline.sol";
import {IOwnable2Step} from "./IOwnable2Step.sol";
import {Amount} from "./Amount.sol";
import {Id} from "./Id.sol";
import {Index} from "./Index.sol";
import {MerkleProof} from "./cryptography_MerkleProof.sol";
import {MerkleRoot} from "./MerkleRoot.sol";
import {Number} from "./Number.sol";
import {Timestamp} from "./Timestamp.sol";

/// @title A periphery contract to deploy and manage Merkle Distributor contracts.
/// @author Timelord
/// @dev The owner can deploy new Merkle Distributor contracts and token transfer.
/// @dev Users can claim rewards from multiple Distributor contracts.
interface IMerkleDistributorPeriphery is IOwnable2Step {
    event Queue(
        address indexed deployer,
        IERC20 indexed token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    );
    
    event Unqueue();

    event CreateFromQueue(
        Id indexed id,
        IMerkleDistributorWithDeadline indexed distributor,
        IERC20 indexed token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    );

    /// @dev Event emitted when the contract deploys a new distributor contract.
    /// @notice Only emitted once for a unique id and distributor address.
    /// @param id The id of the newly deployed distributor contract. Id increments per new deployment.
    /// The id parameter is indexed, to query for one specific event for the given id.
    /// @param distributor The address of the newly deployed distributor contract.
    /// The distributor parameter is indexed, to query for one specific event for the given address.
    /// @param token The address of the ERC20 token reward.
    /// The token parameter is indexed, to query for all events where the reward is the ERC20 token.
    /// @param totalAmount The total amount of ERC20 token reward.
    /// @param merkleRoot The 32 bytes merkle root.
    /// @param endTime The deadline for claiming the rewards in unix timestamp.
    event Create(
        Id indexed id,
        IMerkleDistributorWithDeadline indexed distributor,
        IERC20 indexed token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    );

    /// @dev Event emitted when the owner withdraws the remaining rewards after deadline from a distributor contract.
    /// @notice Only emitted once for a unique id and distributor address.
    /// @param distributor The address of the distributor contract where the rewards were withdrawn.
    /// The distributor parameter is indexed, to query for one specific withdraw event for the given address.
    /// @param amount The amount of remaining ERC20 token reward withdrawn.
    event Withdraw(
        IMerkleDistributorWithDeadline indexed distributor,
        Amount amount
    );

    error CannotQueueWithDeployerAsZeroAddress();

    error CannotQueueWithTokenAsZeroAddress();

    error CannotQueueWithTotalAmountAsZero();

    error CannotQueueWithEndTimeInThePast();

    /// @dev Reverts with this error when calling the create function with token address as zero.
    error CannotCreateWithTokenAsZeroAddress();

    /// @dev Reverts with this error when calling the create function with total amount as zero.
    error CannotCreateWithTotalAmountAsZero();

    /// @dev Reverts with this error when calling the create function with end time in the past.
    error CannotCreateWithEndTimeInThePast();

    error OnlyAuthorizedOwner(address account);

    error InconsistentQueuedToken();

    error InconsistentQueuedTotalAmount();

    error InconsistentQueuedMerkleRoot();

    error InconsistentQueuedEndTime();

    /// @dev View the address given the id of the distributor contract.
    /// @notice Returns the zero address if the distributor contract is not deployed given the id.
    /// @param id The id of the distributor address.
    function merkleDistributor(
        Id id
    ) external view returns (IMerkleDistributorWithDeadline);

    /// @dev View the total number of distributor contracts deployed.
    function totalMerkleDistributors() external view returns (Number);

    function ownerGivenId(Id id) external view returns (address);

    /// @dev A record of a single query for areClaimed function call.
    /// @param distributor The address of the distributor contract being queried.
    /// @param index The index of the mapping of user address and reward amount where the merkle root is generated from.
    struct Query {
        IMerkleDistributorWithDeadline distributor;
        Index index;
    }

    /// @dev Checks that the reward from multiple distributors are claimed given the index of the mapping.
    /// @param queries The list of queries.
    /// @return results The list of boolean results.
    /// @notice The length of queries and results will always be equal.
    /// @notice When the query distributor address does not exist or the index does not exist for the mapping, it will return false.
    function areClaimed(
        Query[] calldata queries
    ) external view returns (bool[] memory results);

    function queued()
        external
        view
        returns (
            address deployer,
            IERC20 token,
            Amount totalAmount,
            MerkleRoot merkleRoot,
            Timestamp endTime
        );

    function queue(
        address deployer,
        IERC20 token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    ) external;

    function unqueue() external;

    function createFromQueue(
        IERC20 token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    ) external returns (Id id, IMerkleDistributorWithDeadline distributor);

    /// @dev The owner deploys a new distributor contract and transfer the necessary ERC20 tokens to the distributor.
    /// @dev Emits the Create event.
    /// @notice Can only be called by the owner.
    /// @notice The owner must first approve this contract for token transfer.
    /// @param token The address of the ERC20 token reward.
    /// Reverts when the address does not follow ERC20 standard or is zero address.
    /// Reverts with CannotCreateWithTokenAsZeroAddress when the address is the zero address.
    /// @param totalAmount The total amount of ERC20 token reward being distributed.
    /// Reverts when there is not enough ERC20 token from the owner.
    /// Reverts with CannotCreateWithTotalAmountAsZero when the totalAmount is zero.
    /// @param merkleRoot The merkle root of the distributor contract for claiming verification.
    /// @param endTime The deadline of distribution and claim in unix timestamp.
    /// Reverts when with CannotCreateWithEndTimeInThePast the block timestamp is greater than the endTime on function call.
    /// @return id The id of the newly deployed distributor contract.
    /// @return distributor The address of the newly deployed distributor contract.
    function create(
        IERC20 token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    ) external returns (Id id, IMerkleDistributorWithDeadline distributor);

    /// @dev A record of a single order for claim function call.
    /// @param distributor The address of the distributor contract being claimed.
    /// @param index The index of the mapping of user address and reward amount where the merkle root is generated from.
    /// @param amount The exact amount of ERC20 token address being claimed.
    /// @notice The amount must be exactly equal to the mapping of user address and reward amount.
    /// @param merkleProof A list of 32 bytes for verification of claiming.
    struct Order {
        IMerkleDistributorWithDeadline distributor;
        Index index;
        Amount amount;
        MerkleProof[] merkleProof;
    }

    /// @dev Msg sender claims the rewards given the list of orders.
    /// @dev Transfer the ERC20 token rewards to the correct user.
    /// @notice Reverts when any of the orders fail.
    /// @notice User can alternatively claim the rewards directly from the individual distributor contracts, but one at a time.
    /// @notice The contract does not emit any events. Instead the individual distributor contracts will emit the Claimed events.
    /// Ingest these events by getting the address of the deployed distributor contracts from the Create event.
    /// @param orders The list of orders for claiming.
    function claim(Order[] calldata orders) external;

    /// @dev The owner withdraws the remaining rewards of the distributor contracts.
    /// @dev Can only be called when the distributor contracts have reached the endTime deadline.
    /// @dev Emits Withdraw event for each withdrawal of distributor contracts.
    /// @notice Reverts when any withdrawals fail.
    /// @param distributors The list of distributor addresses to withdraw from.
    /// @return amounts The list of amount of token withdrawn.
    /// Distributors and amounts will always have the same length.
    /// The token denomination of amount is the token reward of the distributor of the same index.
    function withdraw(
        IMerkleDistributorWithDeadline[] calldata distributors
    ) external returns (Amount[] memory amounts);
}

