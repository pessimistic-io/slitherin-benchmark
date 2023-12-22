// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {IERC721} from "./IERC721.sol";

/**
 * @title Card Game Voting Contract
 *
 * @notice Contracts for voting on the teams of
 * tournament (for different phases)
 */
contract CardGame is AccessControlUpgradeable {
    // Operator Role to manage the phase teams and time slots for tournaments
    bytes32 public constant ROLE_OPERATOR = keccak256("ROLE_OPERATOR");

    // Maximum available teams to be used
    uint256 private constant MAX_TEAMS = 128;

    // Maximum phases possible
    uint256 private constant MAX_PHASES = 16;

    // Maximum phases possible
    uint256 private constant MAX_VOTES = 5;

    // Event about storing team names
    event LogTeamsSet();

    // Event about adding team name
    event LogTeamAdd(bytes32 id, string name);

    // Event about removing the team name
    event LogTeamRemove(bytes32 id);

    // Event about phase added to the contract
    event LogPhaseSet(uint256 indexed phase, uint256 startAt, uint256 endAt);

    // Event about phase removed from contract
    event LogPhaseRemove(uint256 indexed phase);

    // Event about voting
    event LogPhaseVote(uint256 indexed phase, address indexed voter, uint256 indexed tokenId, string[] teams);

    struct Team {
        // team name
        string name;
        // team ID
        bytes32 id;
    }

    struct Vote {
        // Address of the voter
        address voter;
        // Teams
        bytes32[] teams;
    }

    struct Phase {
        // Start time of the phase
        uint64 startAt;
        // End time of the phase
        uint64 endAt;
    }

    // NFT contract of the Sesson Pass
    IERC721 public seasonPass;

    // Mapping of phase number to phase configuration
    mapping(uint256 => Phase) private phases;

    // Mapping of team ID to team name
    mapping(bytes32 => string) private teamNames;

    // Phase number => Token Id => Vote
    mapping(uint256 => mapping(uint256 => Vote)) private userVotes;

    /**
     * @dev Throws an error if the user doesn't have the Season Pass
     */
    modifier hasSeasonPass(uint256 tokenId) {
        require(seasonPass.ownerOf(tokenId) == msg.sender, "NO_SEASON_PASS");
        _;
    }

    /**
     * @dev Throws an error if the phase is not currently active (so voting is not possible)
     */
    modifier activePhase(uint256 phase) {
        require(block.timestamp > phases[phase].startAt, "PHASE_NOT_STARTED");
        require(block.timestamp < phases[phase].endAt, "PHASE_ENDED");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializes the card game contract
     */
    function initialize(address tokenAddress) external initializer {
        __AccessControl_init();

        require(tokenAddress != address(0), "ZERO_ADDRESS");

        seasonPass = IERC721(tokenAddress);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_OPERATOR, msg.sender);
    }

    /**
     * @notice Perform voting for the active teams (up to MAX_VOTES)
     * @param phase Phase number
     * @param tokenId Season Pass Token Id
     * @param teamIds Array of team ids
     */
    function vote(
        uint256 phase,
        uint256 tokenId,
        bytes32[] calldata teamIds
    ) external hasSeasonPass(tokenId) activePhase(phase) {
        require(teamIds.length <= MAX_VOTES, "INCORRECT_VOTE_SIZE");
        require(userVotes[phase][tokenId].voter == address(0), "ALREADY_VOTED");

        for (uint256 i = 0; i < teamIds.length; ) {
            if (bytes(teamNames[teamIds[i]]).length == 0) {
                revert("INCORRECT_TEAM_ID");
            }
            unchecked {
                ++i;
            }
        }

        string[] memory votedTeams = new string[](teamIds.length);
        for (uint256 i = 0; i < teamIds.length; ) {
            votedTeams[i] = teamNames[teamIds[i]];
            unchecked {
                ++i;
            }
        }

        userVotes[phase][tokenId] = Vote(_msgSender(), teamIds);

        emit LogPhaseVote(phase, msg.sender, tokenId, votedTeams);
    }

    /**
     * @notice Set the teams configuration
     * @param teams_ array of teams structs (name, id)
     */
    function setTeams(Team[] calldata teams_) external onlyRole(ROLE_OPERATOR) {
        require(teams_.length <= MAX_TEAMS, "MAX_TEAMS_EXCEEDED");

        for (uint256 i = 0; i < teams_.length; ) {
            teamNames[teams_[i].id] = teams_[i].name;
            unchecked {
                ++i;
            }
        }

        emit LogTeamsSet();
    }

    /**
     * @notice Add the team configuration
     * @param team team configuration
     */
    function storeTeam(Team calldata team) external onlyRole(ROLE_OPERATOR) {
        teamNames[team.id] = team.name;

        emit LogTeamAdd(team.id, team.name);
    }

    /**
     * @notice Remove the team configuration
     * @param teamId identifier of the team
     */
    function removeTeam(bytes32 teamId) external onlyRole(ROLE_OPERATOR) {
        delete teamNames[teamId];

        emit LogTeamRemove(teamId);
    }

    /**
     * @notice Set the phase configuration
     *
     * @param phase phase number
     * @param startAt start time for the phase
     * @param endAt end time for the phase
     */
    function setPhase(
        uint256 phase,
        uint64 startAt,
        uint64 endAt
    ) external onlyRole(ROLE_OPERATOR) {
        require(phase < MAX_PHASES, "WRONG_PHASE");
        require(endAt > startAt, "INCORRECT_END_DATE");

        phases[phase] = Phase(startAt, endAt);

        emit LogPhaseSet(phase, startAt, endAt);
    }

    /**
     * @notice Remove the phase configuration
     * @param phase the phase number to be removed
     */
    function removePhase(uint256 phase) external onlyRole(ROLE_OPERATOR) {
        require(phase < MAX_PHASES, "WRONG_PHASE");

        delete phases[phase];

        emit LogPhaseRemove(phase);
    }

    /**
     * @notice Returns the team name by id
     * @param teamId the team identifier
     */
    function getTeamName(bytes32 teamId) external view returns (string memory) {
        return teamNames[teamId];
    }

    /**
     * @notice Returns the current phase
     * @return phase Active phase
     */
    function getCurrentPhase() external view returns (uint256 phase) {
        phase = 0;

        for (uint256 i = 0; i < MAX_PHASES; ) {
            if (block.timestamp <= phases[i].endAt) {
                phase = i;
            } else if (phases[i].endAt == 0) {
                return phase;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns the phase by number
     * @return phase phase struct
     */
    function getPhase(uint256 phase) external view returns (Phase memory) {
        return phases[phase];
    }
}

