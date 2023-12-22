// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

import {IERC20} from "./ERC20_IERC20.sol";
import {SafeERC20} from "./utils_SafeERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {Create2} from "./Create2.sol";
import {IMerkleDistributorWithDeadline} from "./IMerkleDistributorWithDeadline.sol";
import {MerkleDistributorWithDeadline} from "./MerkleDistributorWithDeadline.sol";
import {IMerkleDistributorPeriphery} from "./IMerkleDistributorPeriphery.sol";
import {IOwnable2Step} from "./IOwnable2Step.sol";
import {Amount} from "./Amount.sol";
import {Id} from "./Id.sol";
import {Index} from "./Index.sol";
import {MerkleProof} from "./cryptography_MerkleProof.sol";
import {MerkleRoot} from "./MerkleRoot.sol";
import {Number} from "./Number.sol";
import {Timestamp} from "./Timestamp.sol";

/// @title A periphery contract implementation to manage multiple Merkle Distributor contracts.
/// @author Timelord
contract MerkleDistributorPeriphery is
    IMerkleDistributorPeriphery,
    Ownable2Step
{
    using SafeERC20 for IERC20;

    /// @dev Mapping storage from id to the distributor contract addresses.
    IMerkleDistributorWithDeadline[] private storedDistributors;

    mapping(Id => address) private ownerships;
    mapping(IMerkleDistributorWithDeadline distributor => address)
        private ownershipGivenDistributors;

    address private queuedDeployer;
    IERC20 private queuedToken;
    Amount private queuedTotalAmount;
    MerkleRoot private queuedMerkleRoot;
    Timestamp private queuedEndTime;

    /// @notice Sets the contract deployer as the owner.
    constructor(address chosenOwner) Ownable(chosenOwner) {}

    /// @inheritdoc IMerkleDistributorPeriphery
    function merkleDistributor(
        Id id
    ) external view override returns (IMerkleDistributorWithDeadline) {
        return storedDistributors[Id.unwrap(id)];
    }

    /// @inheritdoc IMerkleDistributorPeriphery
    function totalMerkleDistributors() external view override returns (Number) {
        return Number.wrap(storedDistributors.length);
    }

    function ownerGivenId(Id id) external view override returns (address) {
        if (Id.unwrap(id) >= storedDistributors.length) return address(0);
        address ownership = ownerships[id];
        return ownership == address(0) ? owner() : ownership;
    }

    /// @inheritdoc IMerkleDistributorPeriphery
    function areClaimed(
        Query[] calldata queries
    ) external view override returns (bool[] memory results) {
        uint256 length = queries.length;
        results = new bool[](length);
        for (uint256 i; i < length; ) {
            Query memory query = queries[i];
            results[i] = query.distributor.isClaimed(Index.unwrap(query.index));

            unchecked {
                i++;
            }
        }
    }

    function queued()
        external
        view
        override
        returns (
            address deployer,
            IERC20 token,
            Amount totalAmount,
            MerkleRoot merkleRoot,
            Timestamp endTime
        )
    {
        deployer = queuedDeployer;
        token = queuedToken;
        totalAmount = queuedTotalAmount;
        merkleRoot = queuedMerkleRoot;
        endTime = queuedEndTime;
    }

    function queue(
        address deployer,
        IERC20 token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    ) external override onlyOwner {
        if (deployer == address(0))
            revert CannotQueueWithDeployerAsZeroAddress();
        if (address(token) == address(0))
            revert CannotQueueWithTokenAsZeroAddress();
        if (totalAmount.isZero()) revert CannotQueueWithTotalAmountAsZero();
        if (endTime <= Timestamp.wrap(block.timestamp))
            revert CannotQueueWithEndTimeInThePast();

        queuedDeployer = deployer;
        queuedToken = token;
        queuedTotalAmount = totalAmount;
        queuedMerkleRoot = merkleRoot;
        queuedEndTime = endTime;

        emit Queue(deployer, token, totalAmount, merkleRoot, endTime);
    }

    function unqueue() external override onlyOwner {
        queuedDeployer = address(0);
        queuedToken = IERC20(address(0));
        queuedTotalAmount = Amount.wrap(0);
        queuedMerkleRoot = MerkleRoot.wrap(0);
        queuedEndTime = Timestamp.wrap(0);

        emit Unqueue();
    }

    function createFromQueue(
        IERC20 token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    )
        external
        override
        returns (Id id, IMerkleDistributorWithDeadline distributor)
    {
        if (msg.sender != queuedDeployer)
            revert OnlyAuthorizedOwner(msg.sender);
        if (address(token) != address(queuedToken))
            revert InconsistentQueuedToken();
        if (Amount.unwrap(totalAmount) != Amount.unwrap(queuedTotalAmount))
            revert InconsistentQueuedTotalAmount();
        if (MerkleRoot.unwrap(merkleRoot) != MerkleRoot.unwrap(merkleRoot))
            revert InconsistentQueuedMerkleRoot();
        if (Timestamp.unwrap(endTime) != Timestamp.unwrap(queuedEndTime))
            revert InconsistentQueuedEndTime();
        if (queuedEndTime <= Timestamp.wrap(block.timestamp))
            revert CannotCreateWithEndTimeInThePast();

        id = Id.wrap(storedDistributors.length);
        distributor = IMerkleDistributorWithDeadline(
            Create2.deploy(
                0,
                bytes32(Id.unwrap(id)),
                abi.encodePacked(
                    type(MerkleDistributorWithDeadline).creationCode,
                    abi.encode(
                        address(token),
                        MerkleRoot.unwrap(merkleRoot),
                        Timestamp.unwrap(endTime)
                    )
                )
            )
        );
        storedDistributors.push(distributor);
        queuedDeployer = address(0);
        queuedToken = IERC20(address(0));
        queuedTotalAmount = Amount.wrap(0);
        queuedMerkleRoot = MerkleRoot.wrap(0);
        queuedEndTime = Timestamp.wrap(0);
        ownerships[id] = msg.sender;
        ownershipGivenDistributors[distributor] = msg.sender;
        token.safeTransferFrom(
            msg.sender,
            address(distributor),
            Amount.unwrap(totalAmount)
        );
        emit CreateFromQueue(
            id,
            distributor,
            token,
            totalAmount,
            merkleRoot,
            endTime
        );
    }

    /// @inheritdoc IMerkleDistributorPeriphery
    function create(
        IERC20 token,
        Amount totalAmount,
        MerkleRoot merkleRoot,
        Timestamp endTime
    )
        external
        override
        onlyOwner
        returns (Id id, IMerkleDistributorWithDeadline distributor)
    {
        if (address(token) == address(0))
            revert CannotCreateWithTokenAsZeroAddress();
        if (totalAmount.isZero()) revert CannotCreateWithTotalAmountAsZero();
        if (endTime <= Timestamp.wrap(block.timestamp))
            revert CannotCreateWithEndTimeInThePast();

        id = Id.wrap(storedDistributors.length);
        distributor = IMerkleDistributorWithDeadline(
            Create2.deploy(
                0,
                bytes32(Id.unwrap(id)),
                abi.encodePacked(
                    type(MerkleDistributorWithDeadline).creationCode,
                    abi.encode(
                        address(token),
                        MerkleRoot.unwrap(merkleRoot),
                        Timestamp.unwrap(endTime)
                    )
                )
            )
        );
        storedDistributors.push(distributor);
        token.safeTransferFrom(
            msg.sender,
            address(distributor),
            Amount.unwrap(totalAmount)
        );
        emit Create(id, distributor, token, totalAmount, merkleRoot, endTime);
    }

    /// @inheritdoc IMerkleDistributorPeriphery
    function claim(Order[] calldata orders) external override {
        uint256 length = orders.length;
        for (uint256 i; i < length; ) {
            Order memory order = orders[i];

            MerkleProof[] memory merkleProof = order.merkleProof;
            uint256 lengthOfMerkleProof = merkleProof.length;
            bytes32[] memory merkleProofInBytes32 = new bytes32[](
                lengthOfMerkleProof
            );
            for (uint256 j; j < lengthOfMerkleProof; ) {
                merkleProofInBytes32[j] = MerkleProof.unwrap(merkleProof[j]);
                unchecked {
                    j++;
                }
            }

            order.distributor.claim(
                Index.unwrap(order.index),
                msg.sender,
                Amount.unwrap(order.amount),
                merkleProofInBytes32
            );

            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IMerkleDistributorPeriphery
    function withdraw(
        IMerkleDistributorWithDeadline[] calldata distributors
    ) external override returns (Amount[] memory amounts) {
        uint256 length = distributors.length;
        amounts = new Amount[](length);
        for (uint256 i; i < length; ) {
            IMerkleDistributorWithDeadline distributor = distributors[i];
            address deployer = ownershipGivenDistributors[distributor];
            if (deployer == address(0)) deployer = owner();
            if (deployer != msg.sender) revert OnlyAuthorizedOwner(msg.sender);
            IERC20 token = IERC20(distributor.token());
            Amount amount = Amount.wrap(token.balanceOf(address(distributor)));

            if (!amount.isZero()) {
                amounts[i] = amount;
                distributor.withdraw();
                token.safeTransfer(msg.sender, Amount.unwrap(amount));
                emit Withdraw(distributor, amount);
            }

            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IOwnable2Step
    function owner()
        public
        view
        override(Ownable, IOwnable2Step)
        returns (address)
    {
        return super.owner();
    }

    /// @inheritdoc IOwnable2Step
    function renounceOwnership() public override(Ownable, IOwnable2Step) {
        super.renounceOwnership();
    }

    /// @inheritdoc IOwnable2Step
    function pendingOwner()
        public
        view
        override(Ownable2Step, IOwnable2Step)
        returns (address)
    {
        return super.pendingOwner();
    }

    /// @inheritdoc IOwnable2Step
    function transferOwnership(
        address newOwner
    ) public override(Ownable2Step, IOwnable2Step) {
        super.transferOwnership(newOwner);
    }

    /// @inheritdoc IOwnable2Step
    function acceptOwnership() public override(Ownable2Step, IOwnable2Step) {
        super.acceptOwnership();
    }
}

