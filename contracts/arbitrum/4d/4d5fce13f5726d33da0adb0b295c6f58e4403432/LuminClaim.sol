// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {MerkleProof} from "./MerkleProof.sol";

/// @title LuminClaim
/// @author bull.haus
/// @notice Claim LUMIN from presale rounds.
/// @dev The team multisig is used as an emergency token holder in case anything goes wrong during the claim process. For
/// example, when for some reason some people cannot claim their tokens, the team multisig can then manually distribute
/// those tokens. Since all LUMIN is withdrawn at once, there is no risk of double claims. Note that despite the tokens
/// possibly being sent to the team multisig, the evidence who has claimed which amount of LUMIN will always remain
/// publicly visible in this contract.
contract LuminClaim {
    using SafeERC20 for IERC20;

    /// @notice Amount of LUMIN claimed per claimer address.
    /// @dev This member is public to validate any issues that may arise when claiming.
    mapping(address claimer => uint256 amountClaimed) public claimAmount;

    /// @notice LUMIN ERC20 contract address.
    IERC20 private constant LUMIN_TOKEN = IERC20(0x422e604492c9Bd9C43F03aD1F78C37968303ebD3);

    /// @notice Lumin Finance Team multisig contract address.
    address private constant TEAM_MULTISIG = 0xa489B76786AE756691744A240c1bB1349810773C;

    /// @notice Merkle root used for LUMIN claims. This value can be updated using `updateMerkleRoot`.
    /// @dev Claims are blocked when this value is bytes32(0).
    bytes32 private merkleRoot;

    /// @notice Emitted when the emergency withdraw method has been called.
    /// @param amount Amount of LUMIN withdrawn.
    /// @param transferSuccess `true` when `IERC20.transfer` has succeeded, `false` otherwise.
    event EmergencyWithdrawCalled(uint256 indexed amount, bool indexed transferSuccess);

    /// @notice Emitted when LUMIN has been claimed.
    /// @param claimer Address which claimed LUMIN.
    /// @param amount Amount of LUMIN claimed.
    event LuminClaimed(address indexed claimer, uint256 amount);

    /// @notice Emitted when the merkle root has been (re)set.
    /// @dev No data is emitted as this is irrelevant to the user, and when desired, can be read from the transaction
    /// payload.
    event MerkleRootUpdated();

    /// @notice Claiming LUMIN from an address that has already claimed LUMIN reverts with `AlreadyClaimed`.
    error AlreadyClaimed();

    /// @notice Claiming LUMIN while the merkle root has not been set or emergency withdrawal has been used, reverts
    /// with `ClaimsBlocked`.
    error ClaimsBlocked();

    /// @notice Claiming LUMIN providing invalid proof, or claiming 0 LUMIN reverts with `InvalidProof`.
    error InvalidMerkleProof();

    /// @notice Setting the merkle root to 0 would block claims without emitting the emergency withdraw event. When the
    /// team tries this, the transaction reverts with `InvalidMerkleRoot`.
    error InvalidMerkleRoot();

    /// @notice Calling `updateMerkleRoot` or `emergencyWithdraw` from an address different than `TEAM_MULTISIG` reverts
    /// with `NotAuthorized`.
    error NotAuthorized();

    /// @notice Validate that team multisig wallet initiated the transaction.
    /// @custom:error NotAuthorized
    modifier onlyTeamMultisig() {
        if (msg.sender != TEAM_MULTISIG) {
            revert NotAuthorized();
        }
        _;
    }

    /// @notice Claim LUMIN by providing a merkle proof. The claimed LUMIN is sent to the claimer's address.
    /// @dev Merkle proof is a tuple of <address claimer, uint256 amount>.
    /// @param proof Merkle proof for claim.
    /// @param amount Amount of LUMIN to claim.
    /// @custom:event LuminClaimed
    /// @custom:error ClaimsBlocked
    /// @custom:error AlreadyClaimed
    /// @custom:error InvalidMerkleProof
    /// @custom:error SafeERC20FailedOperation(token address)
    /// @custom:safe-call SafeERC20.safeTransfer
    function claim(bytes32[] calldata proof, uint256 amount) external {
        if (merkleRoot == 0) {
            revert ClaimsBlocked();
        }

        address claimer = msg.sender;

        if (claimAmount[claimer] != 0) {
            revert AlreadyClaimed();
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(claimer, amount))));
        if (amount == 0 || !MerkleProof.verifyCalldata(proof, merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        claimAmount[claimer] = amount;

        LUMIN_TOKEN.safeTransfer(claimer, amount);

        emit LuminClaimed(claimer, amount);
    }

    /// @notice (Re)set the merkle root.
    /// @dev Previously claimed addresses remain set. Changing claim amounts of already claimed addresses has no effect.
    /// @dev In case claim amounts should be changed, another claim contract shall be deployed containing the new
    /// claimable balance.
    /// @dev It is prohibited to set the merkle root back to 0, as this would implicitly block claims without emitting
    /// the `EmergencyWithdrawCalled` event.
    /// @custom:event MerkleRootUpdated
    /// @custom:error NotAuthorized
    /// @custom:error InvalidMerkleRoot
    function updateMerkleRoot(bytes32 merkleRoot_) external onlyTeamMultisig {
        if (merkleRoot_ == 0) {
            revert InvalidMerkleRoot();
        }

        merkleRoot = merkleRoot_;

        emit MerkleRootUpdated();
    }

    /// @notice Withdraw the complete LUMIN balance of the claim contract to the Lumin Finance Team multisig wallet.
    /// @dev This shall only be done in the case of a known error in the claim contract.
    /// @dev Contrary to the `claim` method, `transfer` is used instead of `safeTransfer`. This is to always emit an
    /// event in case an attempt is made to call the emergency withdraw method. It is however still a `safe-call`, as
    /// the called contract is a trusted contract, and LUMIN's ERC20 contract has no external calls potentially blocking
    /// a transaction.
    /// @param amount Amount of LUMIN to withdraw. Use `0` to withdraw the full balance.
    /// @custom:event EmergencyWithdrawCalled
    /// @custom:error NotAuthorized
    /// @custom:safe-call IERC.transfer
    function emergencyWithdraw(uint256 amount) external onlyTeamMultisig {
        if (amount == 0) {
            amount = LUMIN_TOKEN.balanceOf(address(this));
        }

        merkleRoot = 0;

        bool transferSuccess = LUMIN_TOKEN.transfer(TEAM_MULTISIG, amount);

        emit EmergencyWithdrawCalled(amount, transferSuccess);
    }
}

