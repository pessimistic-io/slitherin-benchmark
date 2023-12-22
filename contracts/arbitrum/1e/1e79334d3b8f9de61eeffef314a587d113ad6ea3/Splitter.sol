// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC721Receiver.sol";
import "./SafeMath.sol";
import "./Math.sol";

import "./IGauge.sol";
import "./ILpDepositor.sol";
import "./IVeDepositor.sol";

import "./IBaseV1Voter.sol";
import "./IVotingEscrow.sol";
import "./IBaseV1Minter.sol";

/**************************************************
 *                 Splitter
 **************************************************/

/**
 * Methods in this contract assumes all interactions with gauges and bribes are safe
 * and that the anti-bricking logics are all already processed by voterProxy
 */

contract Splitter is
    IERC721Receiver,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using SafeMath for uint256;

    uint256 public constant workTimeLimit = 3600;

    /********** Storage slots start here **********/

    // re-entrancy
    uint256 internal _unlocked;

    // Public addresses
    uint256 public splitTokenId;
    IBaseV1Voter public solidlyVoter;
    IVotingEscrow public votingEscrow;
    IBaseV1Minter public minter;

    ILpDepositor public lpDepositor;
    IVeDepositor public moSolid;

    // Tips
    uint256 public minTipPerGauge;

    // States
    uint256 public lastSplitTimestamp; // Records last successful split timestamp
    address public currentWorker;
    uint256 public workingStage;
    uint256 public workFinishDeadline;

    mapping(address => bool) public reattachGauge; // Gauges to reattach
    uint256 public reattachGaugeLength; // Length of gauges to reattach

    // Accounting
    uint256 public totalSplitRequested;
    mapping(address => uint256) public balanceOf; // User => claimable balance
    mapping(address => uint256) public lastBurnTimestamp; // User => last burn timestamp

    /****************************************
     *              Events
     ****************************************/

    event RequestBurn(address indexed from, uint256 amount);
    event WorkStarted(address indexed worker, uint256 deadline);
    event WorkerSplit(uint256 amount);
    event SplitClaimed(address indexed user, uint256 tokenId, uint256 amount);

    /****************************************
     *              Modifiers
     ****************************************/

    modifier lock() {
        require(_unlocked != 2, "Reentrancy");
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    modifier onlyStage(uint256 stage) {
        require(stage == workingStage, "Not current stage");
        _;
    }

    function initialize(
        address _votingEscrow,
        address _minterAddress,
        address _solidlyVoter,
        uint256 _minTipPerGauge
    ) public initializer {
        __Ownable_init();
        votingEscrow = IVotingEscrow(_votingEscrow);
        solidlyVoter = IBaseV1Voter(_solidlyVoter);
        minter = IBaseV1Minter(_minterAddress);

        // Set presets
        _unlocked = 1;
        minTipPerGauge = _minTipPerGauge;
    }

    /****************************************
     *             Initialize
     ****************************************/

    /**
     * @notice Initialize proxy storage
     */
    function setAddresses(address _lpDepositor, address _moSolid) public {
        // Set addresses and interfaces
        lpDepositor = ILpDepositor(_lpDepositor);
        moSolid = IVeDepositor(_moSolid);
    }

    /****************************************
     *            View Methods
     ****************************************/

    function totalTips() external view returns (uint256) {
        return address(this).balance;
    }

    function minTip() public view returns (uint256) {
        return votingEscrow.attachments(lpDepositor.tokenID()) * minTipPerGauge;
    }

    /****************************************
     *            User Methods
     ****************************************/
    function requestSplit(uint256 splitAmount)
        external
        payable
        onlyStage(0)
        whenNotPaused
    {
        require(splitAmount > 0, "Cannot split 0");
        require(
            balanceOf[msg.sender] == 0 ||
                lastBurnTimestamp[msg.sender] > lastSplitTimestamp,
            "Claim available split first"
        );
        require(msg.value >= minTip(), "Not enough tips");

        // Burn moSolid
        moSolid.burnFrom(msg.sender, splitAmount);

        // Record user data
        balanceOf[msg.sender] += splitAmount;
        lastBurnTimestamp[msg.sender] = block.timestamp;

        // Record global data
        totalSplitRequested += splitAmount;

        emit RequestBurn(msg.sender, splitAmount);
    }

    function claimSplitVeNft()
        external
        lock
        whenNotPaused
        returns (uint256 tokenId)
    {
        require(
            lastBurnTimestamp[msg.sender] < lastSplitTimestamp,
            "Split not processed"
        );
        uint256 amount = balanceOf[msg.sender];
        require(amount > 0, "Nothing to claim");

        // Reset state
        balanceOf[msg.sender] = 0;

        // Split if amount < total locked
        (uint256 lockedAmount, ) = votingEscrow.locked(splitTokenId);
        if (amount < uint128(lockedAmount)) {
            tokenId = votingEscrow.split(splitTokenId, amount);
        } else {
            // Transfer splitTokenId instead of split if amount = locked
            tokenId = splitTokenId;
            splitTokenId = 0;
        }
        votingEscrow.safeTransferFrom(address(this), msg.sender, tokenId);

        emit SplitClaimed(msg.sender, tokenId, amount);
        return tokenId;
    }

    /****************************************
     *            Worker Methods
     ****************************************/

    function startWork() external payable lock onlyStage(0) whenNotPaused {
        uint256 activePeriod = minter.active_period();
        require(activePeriod > lastSplitTimestamp, "Not new epoch");
        require(
            block.timestamp <
                activePeriod +
                    1 weeks -
                    // todo
                    // votingSnapshot.window() -
                    workTimeLimit,
            "Cannot start work close to voting window"
        );
        // Require workers to post bonds of 10% of the rewards, minimum 5 ETH
        require(
            msg.value >=
                Math.max(5 ether, address(this).balance.sub(msg.value) / 10),
            "Not enough bond"
        );

        // todo
        // voterProxyAssets.enterSplitMode();

        // Set work status
        currentWorker = msg.sender;
        workFinishDeadline = block.timestamp + workTimeLimit;
        workingStage = 1;

        emit WorkStarted(msg.sender, block.timestamp + workTimeLimit);
    }

    function detachGauges(address[] memory gaugeAddresses)
        external
        onlyStage(1)
    {
        uint256 _reattachGaugeLength = 0;
        address[] memory validGauges = new address[](gaugeAddresses.length);

        for (uint256 i = 0; i < gaugeAddresses.length; i++) {
            require(solidlyVoter.isGauge(gaugeAddresses[i]), "Invalid gauge");

            if (IGauge(gaugeAddresses[i]).tokenIds(address(lpDepositor)) > 0) {
                reattachGauge[gaugeAddresses[i]] = true;
                validGauges[_reattachGaugeLength] = gaugeAddresses[i];
                _reattachGaugeLength++;
            }
        }

        // Update array length
        assembly {
            mstore(validGauges, _reattachGaugeLength)
        }
        reattachGaugeLength += _reattachGaugeLength;

        // Detach gauges
        lpDepositor.detachGauges(validGauges);
    }

    function resetVotes() external onlyStage(1) {
        require(
            block.timestamp < minter.active_period() + 1 weeks, //- votingSnapshot.window(),
            "Voting underway"
        );
        solidlyVoter.vote(
            lpDepositor.tokenID(),
            new address[](0),
            new int256[](0)
        );
    }

    /**
     * @notice Split and enter next stage if possible
     */
    function finishStage1() external lock onlyStage(1) {
        uint256 _primaryTokenId = lpDepositor.tokenID();
        require(
            votingEscrow.attachments(_primaryTokenId) == 0,
            "Gauge Attachments"
        );
        require(!votingEscrow.voted(_primaryTokenId), "Vote not cleared");

        // Split veNFT
        uint256 incomingTokenId = votingEscrow.split(
            _primaryTokenId,
            totalSplitRequested
        );
        emit WorkerSplit(totalSplitRequested);

        // Reset totalSplitRequested
        totalSplitRequested = 0;

        // Merge incoming veNFT into tokenId of splitting veNFT
        if (splitTokenId > 0) {
            votingEscrow.merge(incomingTokenId, splitTokenId);
        } else {
            splitTokenId = incomingTokenId;
        }

        // Record split timestamp
        lastSplitTimestamp = block.timestamp;

        // todo
        // voterProxyAssets.setPrimaryTokenId();

        // Enter next stage
        workingStage = 2;
    }

    function reattachGauges(address[] memory gaugeAddresses)
        external
        onlyStage(2)
    {
        // Process reattachGauge and reattachGaugeLength
        uint256 _reattachedGaugeLength = 0;
        address[] memory validGauges = new address[](gaugeAddresses.length);

        for (uint256 i = 0; i < gaugeAddresses.length; i++) {
            if (reattachGauge[gaugeAddresses[i]]) {
                reattachGauge[gaugeAddresses[i]] = false;
                validGauges[_reattachedGaugeLength] = gaugeAddresses[i];
                _reattachedGaugeLength++;
            }
        }
        // Update array length
        assembly {
            mstore(validGauges, _reattachedGaugeLength)
        }

        reattachGaugeLength -= _reattachedGaugeLength;

        lpDepositor.reattachGauges(validGauges);
    }

    function claimTips() external lock onlyStage(2) {
        require(reattachGaugeLength == 0, "Not all gauges were reattached");
        require(
            msg.sender == currentWorker || block.timestamp > workFinishDeadline,
            "Only current worker can claim tips unless over deadline"
        );
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer tip failed");

        // Reset status
        currentWorker = address(0);
        workingStage = 0;
    }

    /**
     * @notice Only allow inbound ERC721s during contract calls
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        require(_unlocked == 2, "No inbound ERC721s");
        return IERC721Receiver.onERC721Received.selector;
    }

    /****************************************
     *            Restricted Methods
     ****************************************/

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

