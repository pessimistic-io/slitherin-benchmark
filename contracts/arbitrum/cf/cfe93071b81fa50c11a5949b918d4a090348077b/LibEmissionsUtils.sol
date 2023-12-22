// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Storage imports
import { LibStorage, BattleflyGameStorage } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";
import { IGameV2 } from "./IGameV2.sol";
import "./SafeERC20.sol";
import "./draft-EIP712.sol";
import "./MerkleProof.sol";

library LibEmissionsUtils {
    using SafeERC20 for IERC20;

    event ClaimedRNG(address account, uint256 claimableMagic, uint256 epoch);
    event MerkleRootSet(bytes32 root, uint256 emissionsEpoch);
    event MagicRNGEmissionsDeposited(address account, uint256 epoch, uint256 amount);
    event ProcessingEpochRolledOver(uint256 processingEpoch);

    function gs() internal pure returns (BattleflyGameStorage storage) {
        return LibStorage.gameStorage();
    }

    function rollOverProcessingEpoch() internal {
        gs().processingEpoch++;
        emit ProcessingEpochRolledOver(gs().processingEpoch);
    }

    function depositMagicRNGEmissions(uint256 depositAmountInWei, uint256 gameAmountInWei) internal {
        IERC20(gs().magic).safeTransferFrom(msg.sender, address(this), depositAmountInWei);
        IGameV2(gs().gameV2).withdrawMagicForRNGEmissions(gameAmountInWei);
        gs().magicRNGEmissionsForProcessingEpoch[gs().processingEpoch] += (depositAmountInWei + gameAmountInWei);
        emit MagicRNGEmissionsDeposited(msg.sender,gs().emissionsEpoch + 1, depositAmountInWei + gameAmountInWei);
    }

    function claimEmissions(
        uint256 index,
        uint256 epoch,
        bytes calldata data,
        bytes32[] calldata merkleProof
    ) internal {
        (uint256 cumulativeMagicRNGAmount) = abi.decode(data, (uint256));
        if(epoch != gs().emissionsEpoch) revert Errors.InvalidEpoch(epoch, gs().emissionsEpoch);
        _verifyClaimProof(
            index,
            epoch,
            data,
            msg.sender,
            merkleProof
        );
        uint256 claimedMagicRNG = gs().claimedMagicRNGEmissions[msg.sender];
        uint256 claimableMagicRNG = cumulativeMagicRNGAmount - claimedMagicRNG;
        if (claimableMagicRNG > 0) {
            gs().claimedMagicRNGEmissions[msg.sender] = claimedMagicRNG + claimableMagicRNG;
            IERC20(gs().magic).safeTransfer(msg.sender, claimableMagicRNG);
            emit ClaimedRNG(msg.sender, claimableMagicRNG, epoch);
        }
    }

    /**
    * @dev Set the merkle root and increase the emissions epoch
     */
    function setMerkleRoot(bytes32 root) internal {
        gs().merkleRoot = root;
        gs().emissionsEpoch++;
        emit MerkleRootSet(root, gs().emissionsEpoch);
    }

    /**
     * @dev Get the amount claimable for an account, given cumulative amounts data
     */
    function getClaimableMagicRNGEmissionsFor(
        address account,
        bytes calldata data
    ) internal view returns (uint256) {
        (uint256 cumulativeMagicRNGAmount) = abi.decode(data, (uint256));
        uint256 claimedMagicRNG = gs().claimedMagicRNGEmissions[account];
        return cumulativeMagicRNGAmount - claimedMagicRNG;
    }

    /**
     * @dev Get the amount claimed for an account
     */
    function getClaimedMagicRNGEmissionsFor(address account) internal view returns (uint256) {
        return gs().claimedMagicRNGEmissions[account];
    }

    function getMerkleRoot() internal view returns(bytes32) {
        return gs().merkleRoot;
    }

    function getEmissionsEpoch() internal view returns(uint256) {
        return gs().emissionsEpoch;
    }

    function getProcessingEpoch() internal view returns(uint256) {
        return gs().processingEpoch;
    }

    function _verifyClaimProof(
        uint256 index,
        uint256 epoch,
        bytes calldata data,
        address account,
        bytes32[] calldata merkleProof
    ) internal view {
        // Verify the merkle proof.
        bytes32 node = keccak256(
            abi.encode(
                index,
                account,
                epoch,
                data
            )
        );
        if(!MerkleProof.verify(merkleProof, gs().merkleRoot, node)) revert Errors.InvalidProof(merkleProof, gs().merkleRoot, node);
    }
}

