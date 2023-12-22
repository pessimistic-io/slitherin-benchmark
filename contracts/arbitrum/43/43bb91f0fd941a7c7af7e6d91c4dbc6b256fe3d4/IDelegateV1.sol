// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "./SafeERC20Upgradeable.sol";

import "./IVotingEscrow.sol";
import "./IVoter.sol";
import "./IRewardsDistributor.sol";

interface IDelegateV1 {
    error InvalidArrayLength();
    error InvalidSum();
    error InvalidPartnerAddress();
    error ForbiddenToMerge(uint256 tokenId);
    error InvalidCallee();
    error OwnershipCannotBeRenounced();

    event PartnerRemoved(address indexed partner);
    event Split(address[] partners, uint256[] amounts);
    event PartnerCreated(address indexed partner, uint256 indexed amount);

    /// @notice Initializes the contract.
    /// @param votingEscrow_ VotingEscrow contract address.
    /// @param voter_ Voter contract address.
    /// @param rewardsDistributor_ RewardsDistributor contract address.
    /// @param horiza_ Horiza contract address.
    function initialize(
        IVotingEscrow votingEscrow_, 
        IVoter voter_,
        IRewardsDistributor rewardsDistributor_,
        IERC20Upgradeable horiza_
    ) 
        external;

    /// @notice Removes partner.
    /// @param partner_ Partner address.
    function removePartner(address partner_) external;

    /// @notice Splits owner's lock to new partners.
    /// @param partners_ Partner addresses.
    /// @param amounts_ Locked amounts for partners.
    function splitOwnerTokenId(address[] calldata partners_, uint256[] calldata amounts_) external;

    /// @notice Creates lock for the new partner.
    /// @param partner_ Partner address.
    /// @param amount_ Locked amount for the partner.
    function createLockFor(address partner_, uint256 amount_) external;

    /// @notice Extends partners' locks on the admin call.
    /// @param partners_ Partner addresses.
    function extendFor(address[] calldata partners_) external;

    /// @notice Increases locked amounts for partners' locks on the admin call.
    /// @param partners_ Partner addresses.
    /// @param amounts_ Additional locked amounts.
    function increaseFor(address[] calldata partners_, uint256[] calldata amounts_) external;

    /// @notice Extends partners' locks.
    function extend() external;

    /// @notice Votes in pools for partners' locks.
    /// @param pools_ Pools contract addresses.
    /// @param weights_ Weights for vote distribution.
    function vote(address[] calldata pools_, uint256[] calldata weights_) external;

    /// @notice Resets votes for partners' locks.
    function reset() external;

    /// @notice Recasts the saved votes for partners' locks.
    function poke() external;

    /// @notice Claims rewards from external bribes for partners' locks.
    /// @param bribes_ External bribe contract addresses.
    /// @param bribeTokens_ Bribe token contract addresses.
    function claimBribes(address[] calldata bribes_, address[][] calldata bribeTokens_) external;

    /// @notice Claims rewards from internal bribes for partners' locks.
    /// @param fees_ Internal bribe contract addresses.
    /// @param feeTokens_ Fee token contract addresses.
    function claimFees(address[] calldata fees_, address[][] calldata feeTokens_) external;

    /// @notice Claims rebase rewards for partners' locks.
    function claimRebaseRewards() external;

    /// @notice Retrieves the number of partners.
    /// @return Number of partners.
    function numberOfPartners() external view returns (uint256);

    /// @notice Retrieves the partner address by index.
    /// @param index_ Index value.
    /// @return Partner address by index.
    function getPartnerAt(uint256 index_) external view returns (address);
}
