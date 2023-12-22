// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Ownable } from "./Ownable.sol";
import { Multicall } from "./Multicall.sol";
import { ERC1155 } from "./ERC1155.sol";
import { ERC1155Receiver } from "./ERC1155Receiver.sol";
import { ERC1155Holder } from "./ERC1155Holder.sol";
import { AccessControl } from "./AccessControl.sol";
import { IToggleGovernance } from "./ToggleGovernance.sol";
import { IERC1155Supply } from "./IERC1155Supply.sol";
import { ConfigStore } from "./ConfigStore.sol";
import { GenesisText } from "./GenesisText.sol";
import { GlobalConstants } from "./Constants.sol";
import { ISpire } from "./ISpire.sol";
import { IContest } from "./Contest.sol";

error NotBeneficiary();
error InvalidGenesisTextIdSetEchoContestWinner();
error MustSetPreviousEchoContestWinner();
error CannotAdvanceEchoFlow();
error ChapterFlowInitialized();
error InvalidGenesisTextIdSetChapterContestWinner();
error MustSetPreviousChapterContestWinner();
error CannotAdvanceChapterFlow();
error AllGenesisTextsSkipped();
error InvalidAdditionalEchoContestId();

// Maintains the flow of Chapter and Echo Contests. Mints Genesis text tokens to deployer.
// This contract should be the only entrypoint for the Owner to:
// - Set Chapter and Echo contest winner
// - Approve Chapter and Echo contest entries
// Upon approving the latest contest entries, the next contests can open up.

// Losing entrants in Chapter Contests: Tokens unique to losing entry ID's can be minted for a price set by the
// beneficiary. This is only possible if the beneficiary decides to set a losing mint price for the chapter and
// genesis text.
contract Spire is ISpire, GenesisText, ERC1155Holder, AccessControl, Ownable, ReentrancyGuard, Multicall {
    enum Flow {
        Echo,
        Chapter
    }

    string public constant name = "SPIRE";
    string public constant symbol = "SPIRE";

    // Track the ID's of the Genesis Texts whose Chapter/Echo Contests are currently open for submissions.
    // The chapter and echo contests take place in parallel, so we need two sets of tracking variables. This is
    // why we are labeling the t..rackers as "FlowId's" because they track the genesis text ID that the chapter/echo
    // flow is on. The flows are circular, going from ID 0 --> GENESIS_TEXT_COUNT - 1 --> 0 --> etc.
    // Specifically, the counters are used so that we know when we can open new contests when the
    // following conditions are met:
    // - when the current contest can select a winner
    // - when the previous contest has selected a winner

    uint256 public currentChapterFlowId;
    uint256 public previousChapterFlowId;
    uint256 public currentEchoFlowId;
    uint256 public previousEchoFlowId;

    // Governor contracts for each genesis text. These are used to govern whether to skip a genesis text.
    mapping(uint256 => address) public genesisGovernors;

    // If initiated
    bool private _initiatedSpire;
    bool private _initializeChapterFlow;

    event AdvancedEchoFlow(uint256 indexed previousEchoFlowId, uint256 indexed currentEchoFlowId);
    event AdvancedChapterFlow(uint256 indexed previousChapterFlowId, uint256 indexed currentChapterFlowId);

    // Deployer can pass in address of ConfigStore so that they can re-use factories amongst Spire contracts.
    // This is a UX enhancement as it allows users to re-use stake for contests for different Spire contracts.
    // @dev: If the ContestFactory changes in the ConfigStore, then users will have to migrate their stake. The
    // ContestFactory owner should be sure that that stakeable token ID's are carried over between ContestFactories.
    constructor(ConfigStore _configStore) GenesisText(_configStore, "GENESIS_TEXT_URI") {
        // Mint genesis text tokens to deployer.

        // Slither complains that the external call `deployNewToggleGovernor` is made inside the following loop,
        // which we choose to ignore. We could have made ToggleGovernanceFactory an internal library but that would
        // increase this contract's bytecode size, which we are willing to live with in exchange for more gas when
        // deploying this contract. Since these calls take place in the constructor we are OK living with the tradeoff.

        // slither-disable-start calls-loop
        for (uint256 i; i < GlobalConstants.GENESIS_TEXT_COUNT;) {
            // The genesis text tokens are used to govern whether to skip a genesis text.
            genesisGovernors[i] = _getToggleGovernorFactory().deployNewToggleGovernor(IERC1155Supply(address(this)), i);
            unchecked {
                ++i;
            }
        }
        //slither-disable-end calls-loop
    }

    function init() external onlyOwner nonReentrant {
        require(!_initiatedSpire, "already initiated Spire");
        _mintContestWinnerBatch(msg.sender, GlobalConstants.GENESIS_TEXT_COUNT);

        // Begin echo 0 contests for genesis text 0.
        _createNextEchoContests(0);

        // Gives msg.sender aka Owner the SUPER_ADMIN_ROLE
        _setupRole(GlobalConstants.SUPER_ADMIN_ROLE, msg.sender);

        // SpireSuperAdmin is Also MID_ADMIN_ROLE
        _setupRole(GlobalConstants.MID_ADMIN_ROLE, msg.sender);

        // SpireSuperAdmin is "admin" for MID_ADMIN_ROLE
        _setRoleAdmin(GlobalConstants.MID_ADMIN_ROLE, GlobalConstants.SUPER_ADMIN_ROLE);

        _initiatedSpire = true;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC1155Receiver)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // To be called after contract deployment by the owner
    function grantRoles(address[] memory _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i; i < len;) {
            _grantRole(GlobalConstants.MID_ADMIN_ROLE, _addresses[i]);
            unchecked {
                ++i;
            }
        }
    }

    function withdrawRoles(address[] memory _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i; i < len;) {
            _revokeRole(GlobalConstants.MID_ADMIN_ROLE, _addresses[i]);
            unchecked {
                ++i;
            }
        }
    }

    // allows the super admin to revoke their own access
    function setAdminContractAccess(bool access) external onlyOwner {
        _setAdminContractAccess(access);
    }

    // allows the super admin to revoke team access
    function setTeamContractAccess(bool access) external onlyOwner {
        _setTeamContractAccess(access);
    }

    function checkContractRole(address account) external view override {
        _checkContractRole(account);
    }

    function setURI(uint256 tokenId, string calldata _uri) external onlyRole(GlobalConstants.MID_ADMIN_ROLE) {
        _setURI(tokenId, _uri);
    }

    function getURI(uint256 tokenId) external view returns (string memory) {
        return _getURI(tokenId);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return _getURI(tokenId);
    }

    // Will revert unless winningIds.length == initial echo count. Will set winner for echo contests that are closed.
    // This will not revert if no new winner are set.
    function setEchoContestWinner(
        uint256 genesisTextId,
        uint256 winningId,
        uint256 echoId,
        uint256[] memory losingEntryIds,
        bool toBeneficiary
    )
        external
        onlyRole(GlobalConstants.MID_ADMIN_ROLE)
        nonReentrant
    {
        uint256 previousFlow = previousEchoFlowId;
        uint256 currentFlow = currentEchoFlowId;

        // Can only set current or previous echo contest winner.
        if (genesisTextId != previousFlow && genesisTextId != currentFlow) {
            revert InvalidGenesisTextIdSetEchoContestWinner();
        }

        // Must set previous echo contest winner before current one.
        if (genesisTextId == currentFlow && currentFlow != previousFlow) {
            if (!_latestEchoContestsHaveWinner(previousFlow)) revert MustSetPreviousEchoContestWinner();
        }
        _setLatestEchoContestWinner(genesisTextId, winningId, echoId, losingEntryIds, toBeneficiary);
        _advanceEchoFlowIfPossible();
        if (_initializeChapterFlow) _advanceChapterFlowIfPossible();
    }

    function setChapterContestWinner(
        uint256 genesisTextId,
        uint256 winningId,
        uint256[] memory losingEntryIds,
        bool toBeneficiary
    )
        external
        onlyRole(GlobalConstants.MID_ADMIN_ROLE)
        nonReentrant
    {
        uint256 previousFlow = previousChapterFlowId;
        uint256 currentFlow = currentChapterFlowId;

        // Can only set current or previous chapter contest winner.
        if (genesisTextId != previousFlow && genesisTextId != currentFlow) {
            revert InvalidGenesisTextIdSetChapterContestWinner();
        }

        // Must set previous chapter contest winner before current one.
        if (genesisTextId == currentFlow && currentFlow != previousFlow) {
            if (!_latestChapterContestHasWinner(previousFlow)) revert MustSetPreviousChapterContestWinner();
        }
        _setLatestChapterContestWinner(genesisTextId, winningId, losingEntryIds, toBeneficiary);
        _advanceChapterFlowIfPossible();
        _advanceEchoFlowIfPossible();
    }

    // Calling function should not use newCurrentFlowId and newPreviousFlowId if canAdvance is false.
    function _advanceFlowIfPossible(
        uint256 prevFlowId,
        uint256 currFlowId,
        Flow flow
    )
        private
        view
        returns (bool canAdvance, uint256 newCurrentFlowId, uint256 newPreviousFlowId)
    {
        // If current contest can be closed and previous one has selected a winner, increment the flow
        // pointers. If current and previous IDs are the same, then only check if the current contest can be closed.
        bool currEqualsPrev = prevFlowId == currFlowId;
        bool previousContestHasWinner;
        if (flow == Flow.Chapter) {
            previousContestHasWinner = currEqualsPrev || _latestChapterContestHasWinner(prevFlowId);
        } else {
            previousContestHasWinner = currEqualsPrev || _latestEchoContestsHaveWinner(prevFlowId);
        }
        bool latestContestsHaveClosed =
            flow == Flow.Chapter ? _canCloseLatestChapterContest(currFlowId) : _latestEchoContestsClosed(currFlowId);

        if (latestContestsHaveClosed && previousContestHasWinner) {
            canAdvance = true;
            (newCurrentFlowId, newPreviousFlowId) = _incrementFlowCounter(currFlowId, prevFlowId, flow);
        } else {
            canAdvance = false;
        }
    }

    function _advanceEchoFlowIfPossible() private returns (bool) {
        (bool canAdvance, uint256 newCurrentFlowId, uint256 newPreviousFlowId) =
            _advanceFlowIfPossible(previousEchoFlowId, currentEchoFlowId, Flow.Echo);
        if (canAdvance) {
            if (nextEchoChapterId[newCurrentFlowId] > 0) {
                uint256 latestEchoId = _latestEchoChapterId(newCurrentFlowId);
                // The chapter contest should be created and must have set a winner before we can open its echoes.
                if (!_hasCreatedChapterContest(newCurrentFlowId, latestEchoId)) {
                    return false;
                }
                if (!IContest(chapterContests[newCurrentFlowId][latestEchoId]).hasWinner()) {
                    return false;
                }
            }

            currentEchoFlowId = newCurrentFlowId;
            previousEchoFlowId = newPreviousFlowId;
            emit AdvancedEchoFlow(newPreviousFlowId, newCurrentFlowId);

            // If next genesis text hasn't opened its echo contests yet then open them.
            _createNextEchoContests(newCurrentFlowId);
        }
        return canAdvance;
    }

    function _advanceChapterFlowIfPossible() private returns (bool) {
        uint256 curChapterFlowId = currentChapterFlowId;
        uint256 flowCount;

        while (_shouldSkipGenesisText(curChapterFlowId, Flow.Chapter)) {
            if (curChapterFlowId + 1 < GlobalConstants.GENESIS_TEXT_COUNT) {
                curChapterFlowId++;
            } else {
                curChapterFlowId = 0;
            }
            if (
                flowCount == GlobalConstants.GENESIS_TEXT_COUNT - 1
                    && _shouldSkipGenesisText(curChapterFlowId, Flow.Chapter)
            ) {
                return false;
            }

            flowCount++;
        }

        (bool canAdvance, uint256 newCurrentFlowId, uint256 newPreviousFlowId) =
            _advanceFlowIfPossible(previousChapterFlowId, currentChapterFlowId, Flow.Chapter);
        if (canAdvance) {
            uint256 _nextChapterId = nextChapterId[newCurrentFlowId];
            if (_nextChapterId == 0) {
                if (nextEchoChapterId[newCurrentFlowId] == 0 || !_initialEchoContestsHaveWinner(newCurrentFlowId, 0)) {
                    return false;
                }
            } else {
                if (
                    !IContest(chapterContests[newCurrentFlowId][_nextChapterId - 1]).hasWinner()
                        || !_initialEchoContestsHaveWinner(newCurrentFlowId, _nextChapterId)
                ) {
                    return false;
                }
            }

            currentChapterFlowId = newCurrentFlowId;
            previousChapterFlowId = newPreviousFlowId;
            emit AdvancedChapterFlow(newPreviousFlowId, newCurrentFlowId);

            _createNextChapterContest(newCurrentFlowId);
        }
        return canAdvance;
    }

    // Helpful manual trigger to advance echo flow.
    function advanceEchoFlow() external nonReentrant {
        if (!_advanceEchoFlowIfPossible()) revert CannotAdvanceEchoFlow();
    }

    // This method kicks off the chapter flow, which flows automatically from here on out. This method should only be
    // callable once. This method is callable by anyone to save gas. The alternative implementation would be to
    // check whether the first chapter was created everytime we set an Echo chapter contest winner. We only need to
    // kickstart the chapter flow once, so requiring it to be manually called once seems OK.
    function initializeChapterFlow() external nonReentrant {
        if (_initializeChapterFlow) revert ChapterFlowInitialized();

        while (_shouldSkipGenesisText(currentChapterFlowId, Flow.Chapter)) {
            if (currentChapterFlowId + 1 < GlobalConstants.GENESIS_TEXT_COUNT) {
                currentChapterFlowId++;
            }

            if (currentChapterFlowId == GlobalConstants.GENESIS_TEXT_COUNT - 1) {
                if (_shouldSkipGenesisText(currentChapterFlowId, Flow.Chapter)) revert AllGenesisTextsSkipped();
            }
        }

        previousChapterFlowId = currentChapterFlowId;
        _createNextChapterContest(currentChapterFlowId);

        _initializeChapterFlow = true;
    }

    // Convenient method to approve contest entry in current chapter flow genesis text. Owner will never need to
    // approve entry in previous capter flow genesis text because that contest must have been closed in order for the
    // current one to have opened.
    function approveChapterContestEntries(uint256[] memory entryIds)
        external
        onlyRole(GlobalConstants.MID_ADMIN_ROLE)
        nonReentrant
    {
        uint256 currentChapterFlow = currentChapterFlowId;
        IContest(chapterContests[currentChapterFlow][_latestChapterId(currentChapterFlow)]).acceptEntries(entryIds);
        _advanceChapterFlowIfPossible();
    }

    // Helper function to advance flow anyone can call
    function advanceChapterFlow() external nonReentrant {
        if (!_advanceChapterFlowIfPossible()) revert CannotAdvanceChapterFlow();
    }

    // Convenient method to approve contest entries in current echo flow genesis text. Owner will never need to
    // approve entries in previous echo flow genesis text because those contests must have been closed in order for the
    // current one to have opened.
    function approveEchoContestEntries(
        uint256 echoId,
        uint256[] memory entryIds
    )
        external
        onlyRole(GlobalConstants.MID_ADMIN_ROLE)
        nonReentrant
    {
        uint256 currentEchoFlow = currentEchoFlowId;
        _approveEchoContestEntries(currentEchoFlow, _latestEchoChapterId(currentEchoFlow), echoId, entryIds);
        _advanceEchoFlowIfPossible();
    }

    function _shouldSkipGenesisText(uint256 genesisTextId, Flow flow) internal view returns (bool) {
        if (flow == Flow.Chapter && nextChapterId[genesisTextId] >= GlobalConstants.MAX_CHAPTER_COUNT) {
            return true;
        }

        if (flow == Flow.Echo) {
            uint256 _nextEchoChapterId = nextEchoChapterId[genesisTextId];
            if (_nextEchoChapterId == 0) {
                return false;
            } else if (
                _hasCreatedChapterContest(genesisTextId, _nextEchoChapterId - 1)
                    && IContest(chapterContests[genesisTextId][_latestChapterId(genesisTextId)]).hasWinner()
            ) {
                return false;
            } else {
                return true;
            }
        }

        // Genesis Text Owners can “toggle” their NFT as “Open” or “Closed”, at any time.
        // Each time the Chapter Flow has the required Spire Owner and Creator actions completed to move to a
        // new Chapter, the last thing that must be checked is the “toggles”. If there are not enough “Open” for
        // the Genesis Text that the chapter is built on, then the Chapter’s competition is skipped.
        // The Chapter Flow moves onto the next storyline.
        // For example, if the Chapter flow is scheduled to open a contest for Chapter #4 of “The Dragon”,
        // then only four of the Genesis Texts for “The Dragon” storyline are required to be set to “Open”.
        // If it’s Chapter #17, then 17 need to be Open. If it’s Chapter #64, then 64 need to be open.
        // If it’s Chapter #100 or higher, all 100 Genesis Texts need to be “Open” at the time the Chapter Flow
        // moves through this storyline.
        bool hasEnoughOpenContest = IToggleGovernance(genesisGovernors[genesisTextId]).hasEnoughOpenGovernToggles(
            nextChapterId[genesisTextId] + 1
        );
        return !hasEnoughOpenContest;
    }

    // This function should not modify state. It returns what the incremented current and previous flow ID's
    // should be while taking into account chapters that should be skipped, and when ID's should roll over from the
    // highest possible genesis text ID to the first.
    function _incrementFlowCounter(
        uint256 currentFlowId,
        uint256 previousFlowId,
        Flow flow
    )
        internal
        view
        returns (uint256 newCurrentFlowId, uint256 newPreviousFlowId)
    {
        // Update previous flow pointer to current one. Then enter loop to figure out what
        // current pointer should update to.
        previousFlowId = currentFlowId;

        do {
            if (currentFlowId + 1 < GlobalConstants.GENESIS_TEXT_COUNT) {
                currentFlowId++;
            } else {
                // We've completed a full circle around the spire. Reset the genesis text ID to 0.
                currentFlowId = 0;
            }

            // If current flow pointer gets updated to the previous one, then we've gone around a full
            // circle meaning. If the current genesis text is then closed, then every single genesis text is closed.
            if (previousFlowId == currentFlowId && _shouldSkipGenesisText(currentFlowId, flow)) {
                if (flow == Flow.Chapter) {
                    revert AllGenesisTextsSkipped();
                } else {
                    break;
                }
            }

            newCurrentFlowId = currentFlowId;
            newPreviousFlowId = previousFlowId;
        } while (_shouldSkipGenesisText(currentFlowId, flow));
    }

    function _latestEchoContestsClosed(uint256 genesisTextId) internal view returns (bool) {
        return _initialEchoContestsClosed(genesisTextId, _latestEchoChapterId(genesisTextId));
    }

    function _latestEchoContestsHaveWinner(uint256 genesisTextId) internal view returns (bool) {
        return _initialEchoContestsHaveWinner(genesisTextId, _latestEchoChapterId(genesisTextId));
    }

    function _latestChapterContestHasWinner(uint256 genesisTextId) internal view returns (bool) {
        return IContest(chapterContests[genesisTextId][_latestChapterId(genesisTextId)]).hasWinner();
    }

    function _setLatestChapterContestWinner(
        uint256 genesisTextId,
        uint256 winningId,
        uint256[] memory losingEntryIds,
        bool toBeneficiary
    )
        internal
    {
        _setChapterContestWinner(
            genesisTextId, _latestChapterId(genesisTextId), winningId, losingEntryIds, toBeneficiary
        );
    }

    function _setLatestEchoContestWinner(
        uint256 genesisTextId,
        uint256 winningId,
        uint256 echoId,
        uint256[] memory losingEntryIds,
        bool toBeneficiary
    )
        internal
    {
        _setEchoContestWinner(
            genesisTextId, _latestEchoChapterId(genesisTextId), echoId, winningId, losingEntryIds, toBeneficiary
        );
    }

    function getChapterContests(uint256 genesisTextId, uint256 chapterId) external view returns (address) {
        return chapterContests[genesisTextId][chapterId];
    }

    // Custom implementation of transferOwnership in MyContract
    // Additional logic to grant MID_ADMIN_ROLE
    function transferOwnership(address newOwner) public override onlyOwner {
        if (owner() == newOwner) return;

        // Revoke SUPER_ADMIN_ROLE & MID_ADMIN_ROLE for old owner
        _revokeRole(GlobalConstants.MID_ADMIN_ROLE, owner());
        _revokeRole(GlobalConstants.SUPER_ADMIN_ROLE, owner());

        // Gives newOwner the SUPER_ADMIN_ROLE & MID_ADMIN_ROLE
        _setupRole(GlobalConstants.SUPER_ADMIN_ROLE, newOwner);
        _setupRole(GlobalConstants.MID_ADMIN_ROLE, newOwner);

        super.transferOwnership(newOwner);
    }
}

