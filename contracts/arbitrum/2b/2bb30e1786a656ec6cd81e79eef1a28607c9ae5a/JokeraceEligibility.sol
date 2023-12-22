// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { IHatsEligibility } from "./IHatsEligibility.sol";
import { IHats } from "./IHats.sol";
import { HatsEligibilityModule, HatsModule } from "./HatsEligibilityModule.sol";
import { GovernorSorting } from "./GovernorSorting.sol";
import { IGovernor } from "./IGovernor.sol";

contract JokeraceEligibility is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

  /// @notice Indicates that the underlying contest has not completed yet
  error JokeraceEligibility_ContestNotCompleted();
  /// @notice Indicates that the current term is still on-going
  error JokeraceEligibility_TermNotCompleted();
  /// @notice Indicates that top K election winners cannot be deduced because of a tie
  error JokeraceEligibility_NoTies();
  /// @notice Indicates that the caller doesn't have admin permsissions
  error JokeraceEligibility_NotAdmin();

  /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a reelection is set
  event NewTerm(address NewContest, uint256 newTopK, uint256 newTermEnd);

  /*//////////////////////////////////////////////////////////////
                          PUBLIC  CONSTANTS
    //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their locations. In this module, all are inherited from HatsModule.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * --------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                           |
   * --------------------------------------------------------------------|
   * Offset  | Constant        | Type    | Length  | Source Contract     |
   * --------------------------------------------------------------------|
   * 0       | IMPLEMENTATION  | address | 20      | HatsModule          |
   * 20      | HATS            | address | 20      | HatsModule          |
   * 40      | hatId           | uint256 | 32      | HatsModule          |
   * 72      | ADMIN_HAT       | uint256 | 32      | this                |
   * --------------------------------------------------------------------+
   */

  /// @notice Optional admin hat, granted a permission to create a new term (reelection). If not provided (equals zero),
  /// then this permission is granted to the admins of hatId in Hats
  function ADMIN_HAT() public pure returns (uint256) {
    return _getArgUint256(72);
  }

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

  /// @notice Current Jokerace contest (election)
  address public underlyingContest;
  /// @notice First second after the current term (a unix timestamp)
  uint256 public termEnd;
  /// @notice First K winners of the contest will be eligible
  uint256 public topK;
  /// @notice Eligible wearers according to each contest
  mapping(address wearer => mapping(address contest => bool eligible)) public eligibleWearersPerContest;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets up this instance with initial operational values
   * @dev Only callable by the hats-module factory. Since the factory only calls this function during a new deployment,
   * this ensures
   * it can only be called once per instance, and that the implementation contract is never initialized.
   * @param _initData Packed initialization data with the following parameters:
   *  _underlyingContest - Jokerace contest
   *  _termEnd - Final second of the current term (a unix timestamp), i.e. the point at which hats become inactive
   *  _topK - First K winners of the contest will be eligible
   */
  function _setUp(bytes calldata _initData) internal override {
    (address payable _underlyingContest, uint256 _termEnd, uint256 _topK) =
      abi.decode(_initData, (address, uint256, uint256));
    // initialize the mutable state vars
    underlyingContest = _underlyingContest;
    termEnd = _termEnd;
    topK = _topK;
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the JokeraceEligibility implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                          HATS ELIGIBILITY FUNCTION
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Check if a wearer is eligible for a given hat according to the current term contest.
   * @dev The _hatId parameter is not used. This module is tied to a specific hat at creation and checks eligibility
   * according to the current contest that is set. Additionally, this module only checks for eligibility and returns
   * good standing for all wearers.
   */
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    standing = true;
    if (block.timestamp < termEnd) {
      eligible = eligibleWearersPerContest[_wearer][underlyingContest];
    }
  }

  /*//////////////////////////////////////////////////////////////
                           PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Pulls the contest results from the jokerace contest contract.
   * @dev The eligible wearers for a given completed contest are the top K winners of the contract. In case there is a
   * tie, meaning that candidates in places K and K+1 have the same score, then the results of this contest rejected.
   * Additionally, negative scores are also counted as valid scores.
   */
  function pullElectionResults() public {
    GovernorSorting currentContest = GovernorSorting(payable(underlyingContest));

    if (currentContest.state() != IGovernor.ContestState.Completed) {
      revert JokeraceEligibility_ContestNotCompleted();
    }

    // sorted in ascending order
    uint256[] memory sortedProposalIds = currentContest.sortedProposals(true);
    uint256 numProposals = sortedProposalIds.length;
    uint256 numEligibleWearers;

    uint256 k = topK; // save SLOADs

    // check if there's a tie between place k and k + 1. If so, election results are rejected
    if (numProposals > k) {
      numEligibleWearers = k;
      // get the score of candidate in place K
      uint256 placeK = numProposals - k; // only do this operation once
      int256 totalVotesPlaceK = getTotalVotes(currentContest, sortedProposalIds[placeK]);
      // get the score of candidate in place K + 1
      int256 totalVotesPlaceKPlusOne = getTotalVotes(currentContest, sortedProposalIds[placeK - 1]);

      if (totalVotesPlaceK == totalVotesPlaceKPlusOne) {
        revert JokeraceEligibility_NoTies();
      }
    } else {
      numEligibleWearers = numProposals;
    }

    for (uint256 i; i < numEligibleWearers;) {
      address candidate = getCandidate(currentContest, sortedProposalIds[numProposals - i - 1]);
      eligibleWearersPerContest[candidate][address(currentContest)] = true;

      // should not overflow based on < numEligibleWearers stopping condition
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @notice Sets a reelection, i.e. updates the contest for a new term.
   * @dev Only the module's admin/s have the permission to set a reelection. If an admin is not set at the module
   * creation, then any admin of hatId is considered an admin by the module.
   */
  function reelection(address newUnderlyingContest, uint256 newTermEnd, uint256 newTopK) public {
    if (!reelectionAllowed()) {
      revert JokeraceEligibility_TermNotCompleted();
    }

    uint256 admin = ADMIN_HAT();
    // if an admin hat is not set, then the Hats admins of hatId are granted the permission to set a reelection
    if (admin == 0) {
      if (!HATS().isAdminOfHat(msg.sender, hatId())) {
        revert JokeraceEligibility_NotAdmin();
      }
    } else {
      if (!HATS().isWearerOfHat(msg.sender, admin)) {
        revert JokeraceEligibility_NotAdmin();
      }
    }

    underlyingContest = newUnderlyingContest;
    termEnd = newTermEnd;
    topK = newTopK;

    emit NewTerm(newUnderlyingContest, newTopK, newTermEnd);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Check if setting a new election is allowed.
  function reelectionAllowed() public view returns (bool allowed) {
    allowed = block.timestamp >= termEnd
      || GovernorSorting(payable(underlyingContest)).state() == IGovernor.ContestState.Canceled;
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  function getTotalVotes(GovernorSorting contest, uint256 proposalId) internal view returns (int256 totalVotes) {
    (uint256 forVotes, uint256 againstVotes) = contest.proposalVotes(proposalId);
    totalVotes = int256(forVotes) - int256(againstVotes);
  }

  function getCandidate(GovernorSorting contest, uint256 proposalId) internal view returns (address candidate) {
    candidate = contest.getProposal(proposalId).author;
  }
}

