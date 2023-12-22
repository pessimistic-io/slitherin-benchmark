// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ExtendedSelfMulticall.sol";
import "./IMerkleFunder.sol";
import "./MerkleProof.sol";
import "./Create2.sol";
import "./MerkleFunderDepository.sol";

/// @title Contract that can be called to deploy MerkleFunderDepository
/// contracts or transfer the funds in them within the limitations specified by
/// the respective Merkle trees
/// @notice Use-cases such as self-funded data feeds require users to keep
/// multiple accounts funded. The only way to achieve this without relying on
/// on-chain activity is running a bot that triggers the funding using a hot
/// wallet. In the naive implementation, the funds to be used would also be
/// kept by this hot wallet, which is obviously risky. This contract allows one
/// to deploy a MerkleFunderDepository where they can keep the funds, which
/// this contract only allows to be transferred within the limitations
/// specified by the respective Merkle tree. This means the bot's hot wallet no
/// longer needs to be trusted with the funds, and multiple bots with different
/// hot wallets can be run against the same MerkleFunderDepository deployment
/// for redundancy.
/// @dev MerkleFunder inherits SelfMulticall to allow `fund()` to be
/// multi-called so that multiple fundings can be executed in a single
/// transaction without depending on an external contract. Furthermore, it
/// inherits ExtendedSelfMulticall to allow `getBlockNumber()` be multi-called
/// to avoid race conditions that would have caused the bot implementation to
/// make redundant transactions that revert.
contract MerkleFunder is ExtendedSelfMulticall, IMerkleFunder {
    /// @notice Returns the address of the MerkleFunderDepository deployed for
    /// the owner address and the Merkle tree root, and zero-address if such a
    /// MerkleFunderDepository is not deployed yet
    /// @dev The MerkleFunderDepository address can be derived from the owner
    /// address and the Merkle tree root using
    /// `computeMerkleFunderDepositoryAddress()`, yet doing so is more
    /// expensive than reading it from this mapping, which is why we prefer
    /// storing it during deployment
    mapping(address => mapping(bytes32 => address payable))
        public
        override ownerToRootToMerkleFunderDepositoryAddress;

    /// @notice Called to deterministically deploy the MerkleFunderDepository
    /// with the owner address and the Merkle tree root
    /// @dev The owner address is allowed to be zero in case the deployer wants
    /// to disallow `withdraw()` from being called for the respective
    /// MerkleFunderDepository.
    /// See `fund()` for how the Merkle tree leaves are derived and how the
    /// comprising parameters are validated.
    /// @param owner Owner address
    /// @param root Merkle tree root
    /// @return merkleFunderDepository MerkleFunderDepository address
    function deployMerkleFunderDepository(
        address owner,
        bytes32 root
    ) external override returns (address payable merkleFunderDepository) {
        if (root == bytes32(0)) revert RootZero();
        merkleFunderDepository = payable(
            new MerkleFunderDepository{salt: bytes32(0)}(owner, root)
        );
        ownerToRootToMerkleFunderDepositoryAddress[owner][
            root
        ] = merkleFunderDepository;
        emit DeployedMerkleFunderDepository(
            merkleFunderDepository,
            owner,
            root
        );
    }

    /// @notice Called to transfer funds from a MerkleFunderDepository to the
    /// recipient within the limitations specified by the respective Merkle
    /// tree
    /// @param owner Owner address
    /// @param root Merkle tree root
    /// @param proof Merkle tree proof
    /// @param recipient Recipient address
    /// @param lowThreshold Low hysteresis threshold
    /// @param highThreshold High hysteresis threshold
    /// @return amount Amount used in funding
    function fund(
        address owner,
        bytes32 root,
        bytes32[] calldata proof,
        address recipient,
        uint256 lowThreshold,
        uint256 highThreshold
    ) external override returns (uint256 amount) {
        if (recipient == address(0)) revert RecipientAddressZero();
        if (lowThreshold > highThreshold) revert LowThresholdHigherThanHigh();
        if (highThreshold == 0) revert HighThresholdZero();
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(abi.encode(recipient, lowThreshold, highThreshold))
            )
        );
        if (!MerkleProof.verify(proof, root, leaf)) revert InvalidProof();
        uint256 recipientBalance = recipient.balance;
        if (recipientBalance > lowThreshold)
            revert RecipientBalanceLargerThanLowThreshold();
        address payable merkleFunderDepository = ownerToRootToMerkleFunderDepositoryAddress[
                owner
            ][root];
        if (merkleFunderDepository == address(0))
            revert NoSuchMerkleFunderDepository();
        uint256 amountNeededToTopUp;
        unchecked {
            amountNeededToTopUp = highThreshold - recipientBalance;
        }
        amount = amountNeededToTopUp <= merkleFunderDepository.balance
            ? amountNeededToTopUp
            : merkleFunderDepository.balance;
        if (amount == 0) revert AmountZero();
        MerkleFunderDepository(merkleFunderDepository).transfer(
            recipient,
            amount
        );
        emit Funded(merkleFunderDepository, recipient, amount);
    }

    /// @notice Called by the owner of the respective MerkleFunderDepository to
    /// withdraw funds in a way that is exempt from the limitations specified
    /// by the respective Merkle tree
    /// @param root Merkle tree root
    /// @param recipient Recipient address
    /// @param amount Withdrawal amount
    function withdraw(
        bytes32 root,
        address recipient,
        uint256 amount
    ) public override {
        if (recipient == address(0)) revert RecipientAddressZero();
        if (amount == 0) revert AmountZero();
        address payable merkleFunderDepository = ownerToRootToMerkleFunderDepositoryAddress[
                msg.sender
            ][root];
        if (merkleFunderDepository == address(0))
            revert NoSuchMerkleFunderDepository();
        if (merkleFunderDepository.balance < amount)
            revert InsufficientBalance();
        MerkleFunderDepository(merkleFunderDepository).transfer(
            recipient,
            amount
        );
        emit Withdrew(merkleFunderDepository, recipient, amount);
    }

    /// @notice Called by the owner of the respective MerkleFunderDepository to
    /// withdraw its entire balance in a way that is exempt from the
    /// limitations specified by the respective Merkle tree
    /// @param root Merkle tree root
    /// @param recipient Recipient address
    /// @return amount Withdrawal amount
    function withdrawAll(
        bytes32 root,
        address recipient
    ) external override returns (uint256 amount) {
        amount = ownerToRootToMerkleFunderDepositoryAddress[msg.sender][root]
            .balance;
        withdraw(root, recipient, amount);
    }

    /// @notice Computes the address of the MerkleFunderDepository
    /// @param owner Owner address
    /// @param root Merkle tree root
    /// @return merkleFunderDepository MerkleFunderDepository address
    function computeMerkleFunderDepositoryAddress(
        address owner,
        bytes32 root
    ) external view override returns (address merkleFunderDepository) {
        if (root == bytes32(0)) revert RootZero();
        merkleFunderDepository = Create2.computeAddress(
            bytes32(0),
            keccak256(
                abi.encodePacked(
                    type(MerkleFunderDepository).creationCode,
                    abi.encode(owner, root)
                )
            )
        );
    }
}

