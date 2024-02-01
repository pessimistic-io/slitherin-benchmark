// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// import "../extensions/interfaces/ISalesPhase.sol";

/**
 *  The interface `IDrop` is written for Sparkblox's 'Drop' contracts, which are distribution mechanisms for tokens.
 *
 *  An authorized wallet can set a series of sales phases, ordered by their respective `startTimestamp`.
 *  A sales phase defines criteria under which accounts can mint tokens. Sales phases can be overwritten
 *  or added to by the contract admin. At any moment, there is only one active sales phase.
 */

interface INFTDrop {

    /// @notice Emitted when tokens are claimed via `claim`.
    event TokensClaimed(
        uint256 indexed salesPhaseIndex,
        address indexed claimer,
        address indexed receiver,
        uint256 quantityClaimed
    );

    /// @notice Emitted when the contract's sales phases are updated.
    event SalesPhasesUpdated(SalesPhase[] SalesPhases, bool resetEligibility);

    struct SalesPhase {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 maxClaimableSupply;
        uint256 supplyClaimed;
        uint256 quantityLimitPerWallet;
        uint256 waitTimeInSecondsBetweenClaims;
        bytes32 merkleRoot;
        uint256 pricePerToken;
        bool    isRandom;
        bool    isAirdrop;
    }
    /**
     *  @notice Lets an account claim a given quantity of NFTs.
     *
     *  @param receiver                       The receiver of the NFTs to claim.
     *  @param quantity                       The quantity of NFTs to claim.
     *  @param proofs                          The proof of the claimer's 
     *  @param quantityLimitPerWallet         The limit to mint per wallet
     *  @param salesPhaseId                   The salesPhaseId to mint
     */

    function claim(
        address receiver,
        uint256 quantity,
        bytes32[] calldata proofs,
        uint256 quantityLimitPerWallet,
        uint256 salesPhaseId
    ) external payable;

    /**
     *  @notice Lets a contract admin (account with `DEFAULT_ADMIN_ROLE`) set sales phases.
     *
     *  @param phases                   Sales phases in ascending order by `startTimestamp`.
     *
     *  @param resetClaimEligibility    Whether to honor the restrictions applied to wallets who have claimed tokens in the current phases,
     *                                  in the new sales phases being set.
     *
     */
    function setSalesPhases(SalesPhase[] calldata phases, bool resetClaimEligibility) external;

    function salesPhases(uint256 salesPhaseId) external view returns (SalesPhase memory);
}

