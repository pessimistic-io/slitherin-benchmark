// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC721ReceiverUpgradeable.sol";

interface IVoter {
    function vote(uint256, address[] calldata, uint256[] calldata) external;
    function claimBribes(address[] memory, address[][] memory, uint256 tokenId) external;
    function claimFees(address[] memory, address[][] memory, uint256 tokenId) external;
    function _epochTimestamp() external view returns (uint256);
}

interface IVeToken {
    function increase_unlock_time(uint256, uint256) external; 
}

interface IGaugeStaker {
    function claimVeEmissions() external;
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external; 
    function claimMultipleOwnerRewards(address[] calldata _gauges, address[][] calldata _tokens) external;
}

contract BeefyNftHandlerV2 is OwnableUpgradeable {

    // Addresses used 
    IVeToken public ve;
    IGaugeStaker public gaugeStaker;
    uint256 public tokenId;

    mapping (address => bool) public operator; 

    struct ThisWeeksVote {
        uint256 epoch;
        address[] lps;
        uint256[] weights;
    }

    struct ThisWeeksBribes {
        uint256 epoch;
        address[] bribeGauges;
        address[][] bribeTokens;
    }

    struct ThisWeeksFees {
        uint256 epoch;
        address[] feeGauges;
        address[][] feeTokens;
    }

    ThisWeeksVote public thisWeeksVote;
    ThisWeeksBribes public thisWeeksBribes;
    ThisWeeksFees public thisWeeksFees;

    function initialize(
        IVeToken _ve,
        IGaugeStaker _gaugeStaker, 
        uint256 _tokenId
    ) public initializer {
        __Ownable_init();
        ve = _ve;
        gaugeStaker = _gaugeStaker;
        tokenId = _tokenId;
    }

    modifier onlyAuth {
        require(msg.sender == owner() || operator[msg.sender], "Not Auth");
        _;
    }

    function claimAllAndVote() external onlyAuth {
        _claimAll();
        _vote(thisWeeksVote.lps, thisWeeksVote.weights);
    }

    function claimAll() external onlyAuth {
        _claimAll();
    }

    function _claimAll() private {
        claimAndLock();
        _claimBribes(thisWeeksBribes.bribeGauges, thisWeeksBribes.bribeTokens);
        _claimFees(thisWeeksFees.feeGauges, thisWeeksFees.feeTokens);
    }

    function claimAndLock() public {
        gaugeStaker.claimVeEmissions();
    }

    // Maintain same vote as previous;
    function vote() external onlyAuth {
        _vote(thisWeeksVote.lps, thisWeeksVote.weights);
    }

    function vote(address[] calldata _lps, uint256[] calldata _weights) external onlyAuth {
        _vote(_lps, _weights);
    }

    function _vote(address[] memory _lps, uint256[] memory _weights) private {
        delete thisWeeksVote;
        thisWeeksVote.epoch = block.timestamp;
        thisWeeksVote.lps = _lps;
        thisWeeksVote.weights = _weights;
        gaugeStaker.vote(_lps, _weights);
    }

    function claimBribes() external onlyAuth {
        _claimBribes(thisWeeksBribes.bribeGauges, thisWeeksBribes.bribeTokens);
    }
    
    function claimBribes(address[] memory _bribeGauges, address[][] memory _bribeTokens) external onlyAuth {
        _claimBribes(_bribeGauges, _bribeTokens);
    }

    function _claimBribes(address[] memory _bribeGauges, address[][] memory _bribeTokens) private {
        delete thisWeeksBribes;
        thisWeeksBribes.epoch = block.timestamp;
        thisWeeksBribes.bribeGauges = _bribeGauges;
        thisWeeksBribes.bribeTokens = _bribeTokens;
        gaugeStaker.claimMultipleOwnerRewards(_bribeGauges, _bribeTokens);
    }

    function claimFees() external onlyAuth {
        _claimFees(thisWeeksFees.feeGauges, thisWeeksFees.feeTokens);
    }
    
    function claimFees(address[] memory _feeGauges, address[][] memory _feeTokens) external onlyAuth {
        _claimFees(_feeGauges, _feeTokens);
    }

    function _claimFees(address[] memory _feeGauges, address[][] memory _feeTokens) private {
        delete thisWeeksFees;
        thisWeeksFees.epoch = block.timestamp;
        thisWeeksFees.feeGauges = _feeGauges;
        thisWeeksFees.feeTokens = _feeTokens;
        gaugeStaker.claimMultipleOwnerRewards(_feeGauges, _feeTokens);
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        operator[_operator] = _status;
    }
}
