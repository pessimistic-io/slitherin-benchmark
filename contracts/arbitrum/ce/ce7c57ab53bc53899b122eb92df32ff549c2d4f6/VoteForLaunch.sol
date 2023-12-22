// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./TransferHelper.sol";
import "./Ownable.sol";
import "./IVoteForLaunch.sol";

contract VoteForLaunch is Ownable {
    uint32 public UNDEPLOYED_EXPIRE = 3 * 24 * 3600;
    uint32 public MAX_VOTING_DAYS = 10 * 24 * 3600;
    uint16 public PASSED_RATIO = 3000; // Passed if 30% of total ballots voted.
    uint128 public totalBallots = 10000000 * 10**18 * 10 / 100; // 10% of total supply
    uint128 public newVoteDeposit = 1000 * 10**18;
    uint128 public totalDeposit = 0;
    uint128 public totalVoted = 0;

    IERC20 public voteToken;
    address public inscriptionFactory;

    mapping(string => IVoteForLaunch.Application) public applications; // tick => Application
    mapping(string => IVoteForLaunch.Ballot[]) public everyVotes;
    mapping(string => mapping(address => uint)) public Ids; // min is 1

    string[] public tickArray;
    mapping(string => uint) public tickIds; // min is 1

    mapping(address => uint128) public deposits;   // user => deposit amount
    mapping(address => uint128) public ballots;    // user => ballots

    mapping(string => bool) public reservedTicks;     // check if tick is occupied
    mapping(string => bool) public deployedTicks;     // note: not all deployed ticks are voted

    event NewApplication(string tick, address applicant, uint40 expireAt, string cid, uint128 deposit);
    event AddVote(string tick, address applicant, address voter, uint128 amount);
    event CancelVote(string tick, address applicant, address voter, uint128 amount);
    event Deposit(address sender, uint128 amount, uint ballots);
    event Withdraw(address sender, uint128 amount, uint ballots);

    constructor() {
        _batchUpdateStockTick();
    }

    function newVote(string memory _tick, uint40 _expireSeconds, string memory _cid) public {
        require(_expireSeconds <= MAX_VOTING_DAYS, "more than max days to vote");
        require(!reservedTicks[_tick], "reserved ticks can not apply");
        require(applications[_tick].expireAt == 0, "tick application exist");
        require(bytes(_tick).length < 6, "tick name too long");

        // Deposit for new vote
        require(voteToken.allowance(msg.sender, address(this)) >= newVoteDeposit, "allowance of ferc as deposit not enough");
        require(voteToken.balanceOf(msg.sender) >= newVoteDeposit, "balance of ferc as deposit not enough");
        TransferHelper.safeTransferFrom(address(voteToken), msg.sender, address(this), newVoteDeposit);

        applications[_tick] = IVoteForLaunch.Application(
            0,
            newVoteDeposit,
            msg.sender,
            uint40(block.timestamp + _expireSeconds),
            0,
            false,
            _cid,
            false,
            0
        );

        if(tickIds[_tick] == 0) {
            tickArray.push(_tick);
            tickIds[_tick] = tickArray.length;
        }

        emit NewApplication(_tick, msg.sender, uint40(block.timestamp + _expireSeconds), _cid, newVoteDeposit);
    }

    function withdrawNewVote(string memory _tick) public {
        IVoteForLaunch.Application memory application = applications[_tick];
        require(application.applicant == msg.sender, "only applicant can withdraw");
        require(application.expireAt + UNDEPLOYED_EXPIRE < block.timestamp, "should be wait until some days after vote finish");
        require(application.deposit > 0, "deposit is zero");
        TransferHelper.safeTransfer(address(voteToken), application.applicant, application.deposit);
        applications[_tick].deposit = 0;
    }

    function deposit(uint128 _amount) public {
        require(voteToken.allowance(msg.sender, address(this)) >= _amount, "allowance is not enough");
        require(voteToken.balanceOf(msg.sender) >= _amount, "balance is not enough");
        TransferHelper.safeTransferFrom(address(voteToken), msg.sender, address(this), _amount);

        deposits[msg.sender] += _amount;
        totalDeposit += _amount;
        ballots[msg.sender] += _amount;
        emit Deposit(msg.sender, _amount, _amount);
    }

    function withdraw(uint128 _amount) public {
        require(deposits[msg.sender] >= _amount, "balance is not enough");
        require(ballots[msg.sender] >= _amount, "ballots is not enough");
        
        deposits[msg.sender] -= _amount;
        totalDeposit -= _amount;
        ballots[msg.sender] -= _amount;
        
        TransferHelper.safeTransfer(address(voteToken), msg.sender, _amount);
        emit Withdraw(msg.sender, _amount, _amount);
    }

    function addVote(string memory _tick, uint128 _ballots) public {
        require(ballots[msg.sender] >= _ballots, "you ballots is not enough");
        require(applications[_tick].expireAt >= block.timestamp, "vote is expired");
        require(Ids[_tick][msg.sender] == 0, "you have voted, cancel and revote if you want");

        applications[_tick].totalVotes += _ballots;
        applications[_tick].topVotes = applications[_tick].totalVotes;

        everyVotes[_tick].push(IVoteForLaunch.Ballot(msg.sender, _ballots));
        Ids[_tick][msg.sender] = totalVoters(_tick);
        ballots[msg.sender] -= _ballots;
        totalVoted += _ballots;

        if(!applications[_tick].passed && applications[_tick].totalVotes >= totalBallots * PASSED_RATIO / 10000) {
            applications[_tick].passed = true;
            applications[_tick].passedTimestamp = uint40(block.timestamp);
        }
        emit AddVote(_tick, applications[_tick].applicant, msg.sender, _ballots);
    }

    function cancelVote(string memory _tick) public {
        uint128 voted = everyVotes[_tick][Ids[_tick][msg.sender] - 1].amount;
        require(voted > 0, "You did not voted");
        ballots[msg.sender] += voted;
        totalVoted -= voted;
        applications[_tick].totalVotes -= voted;

        _removeVoteByAddress(_tick, msg.sender);
        
        emit CancelVote(_tick, applications[_tick].applicant, msg.sender, voted);
    }

    function cancelFailedApplication(string memory _tick) public {
        IVoteForLaunch.Application memory application = applications[_tick];
        require(application.expireAt < block.timestamp, "vote is not expired");
        require(!application.passed, "tick is passed");
        _reset(_tick);
    }

    function cancelUndeployedApplication(string memory _tick) public {
        IVoteForLaunch.Application memory application = applications[_tick];
        require(application.passed && !application.deployed && application.passedTimestamp + UNDEPLOYED_EXPIRE < block.timestamp, "waiting for deploying");
        _reset(_tick);
    }

    function getCurrentVotes(string memory _tick) public view returns(IVoteForLaunch.Ballot[] memory) {
        return everyVotes[_tick];
    }

    function totalVoters(string memory _tick) public view returns(uint) {
        return everyVotes[_tick].length;
    }

    function getVotesByAddress(string memory _tick, address _addr) public view returns(uint128 votes) {
        if(Ids[_tick][_addr] > 0) votes = everyVotes[_tick][Ids[_tick][_addr] - 1].amount;
    }

    function getApplication(string memory _tick) public view returns(IVoteForLaunch.Application memory) {
        return applications[_tick];
    }

    function getVotedApplications(address _addr) public view returns(
        IVoteForLaunch.Application[] memory applications_,
        uint128[] memory amount_,
        bool[] memory isExpireForVote_,
        bool[] memory isExpireForDeploy_,
        bool[] memory canDeploy_,
        uint8[] memory code_,
        string[] memory description_,
        string[] memory tick_
    ) {
        uint len = tickArray.length;
        if(len > 0) {
            tick_ = new string[](len);
            applications_ = new IVoteForLaunch.Application[](len);
            amount_ = new uint128[](len);
            isExpireForVote_ = new bool[](len);
            isExpireForDeploy_ = new bool[](len);
            canDeploy_ = new bool[](len);
            code_ = new uint8[](len);
            description_ = new string[](len);

            uint index = 0;
            for(uint i = 0; i < len; i++) {
                string memory _tick = tickArray[i];
                uint128 _votes = getVotesByAddress(_tick, _addr);
                if(applications[_tick].expireAt == 0) continue;
                tick_[index] = _tick;
                applications_[index] = applications[_tick];
                amount_[index] = _votes;
                isExpireForVote_[index] = isExpireForVote(_tick);
                isExpireForDeploy_[index] = isExpireForDeploy(_tick);
                (bool _canDeploy, uint8 _code, string memory _description) = getStatus(_tick, _addr);
                canDeploy_[index] = _canDeploy;
                code_[index] = _code;
                description_[index] = _description;
                index++;
            }
        }
    }

    function getStatus(string memory _tick, address _sender) public view returns(bool result, uint8 code, string memory description) {
        // Check the diagram: https://drive.google.com/file/d/1hSIF4OeWjPh7wBGYIgXdjr5WVciky1x8/view?usp=sharing
        IVoteForLaunch.Application memory application = applications[_tick];
        if(reservedTicks[_tick]) return(false, 1, "#1 reserved tick name");
        else if(deployedTicks[_tick]) {
            if(application.expireAt == 0) return(false, 2, "#2 double name but no vote");
            else if(application.deployed) return(false, 8, "#8 tick has deployed");
            else if(!application.passed) return(false, 3, "#3 vote not passed");
            else if(block.timestamp > application.passedTimestamp + UNDEPLOYED_EXPIRE) return(false, 4, "#4 vote passed but not deployed on time");
            else if(application.applicant == _sender) return(true, 11, "#11");
            else return(false, 7, "#7 you are not applicant");
        } else {
            if(application.expireAt == 0) return(true, 12, "#12");
            else if(application.deployed) return(false, 9, "#9 tick has deployed");
            else if(block.timestamp > application.expireAt && !application.passed) return(true, 13, "#13");
            else if(block.timestamp <= application.expireAt && !application.passed) return(false, 5, "#5 vote not passed");
            else if(block.timestamp > application.passedTimestamp + UNDEPLOYED_EXPIRE) return(true, 14, "#14");
            else if(application.applicant == _sender) return(true, 15, "#15");
            else return(false, 6, "#6 you are not applicant");
        }
    }

    function isPassed(string memory _tick, address _sender) public view returns(bool) {
        IVoteForLaunch.Application memory application = applications[_tick];
        return application.expireAt > 0 && application.passed && _sender == application.applicant;
    }

    function isExpireForVote(string memory _tick) public view returns(bool) {
        return block.timestamp > applications[_tick].expireAt;
    }

    function isExpireForDeploy(string memory _tick) public view returns(bool) {
        return applications[_tick].passed && block.timestamp > applications[_tick].passedTimestamp + UNDEPLOYED_EXPIRE;
    }

    function setDeployedTicks(string memory _tick, uint8 _code) public {
        require(msg.sender == inscriptionFactory, "calls only from factory");
        deployedTicks[_tick] = true;
        if(_code == 13 || _code == 14) {
            _reset(_tick);
        } else if(_code == 11 || _code == 15) {
            _removeDeposit(_tick); // If the vote succeed and deployed by the applicant, don't cancel votes, let the voters cancel by themselves
        }
        if(applications[_tick].expireAt > 0) applications[_tick].deployed = true;
    }

    // ===================================
    // ============ only Owner ===========
    // ===================================
    function updateNewVoteDeposit(uint128 _amount) public onlyOwner {
        newVoteDeposit = _amount;
    }

    function updateVoteToken(address _addr) public onlyOwner {
        voteToken = IERC20(_addr);
    }

    function updateInscriptionFactory(address _addr) public onlyOwner {
        inscriptionFactory = _addr;
    }

    function updateBaseBallots(uint128 _value) public onlyOwner {
        totalBallots = _value;
    }

    function updateUndeployedExpire(uint32 _value) public onlyOwner {
        UNDEPLOYED_EXPIRE = _value;
    }

    function updateMaxVotingDays(uint32 _value) public onlyOwner {
        MAX_VOTING_DAYS = _value;
    }

    function updatePassedRatio(uint16 _value) public onlyOwner {
        PASSED_RATIO = _value;
    }

    // ===================================
    // ======== Private functions ========
    // ===================================
    // Upgrade from v1 to v2
    function _batchUpdateStockTick() private {
        string[4] memory v1StockTicks = [
            "ferc",
            "fdao",
            "cash",
            "fair"
        ];

        for(uint256 i = 0; i < v1StockTicks.length; i++) {
            reservedTicks[v1StockTicks[i]] = true;
        }
    }

    function _reset(string memory _tick) private {
        _removeDeposit(_tick);
        _removeAllVotes(_tick);
        _removeFromTickArray(_tick);
        delete(applications[_tick]);
    }

    function _removeDeposit(string memory _tick) private {
        if(applications[_tick].deposit > 0) TransferHelper.safeTransfer(address(voteToken), applications[_tick].applicant, applications[_tick].deposit);
    }

    function _removeAllVotes(string memory _tick) private {
        // remove all votes, including vote history data
        for(uint i = 0; i < totalVoters(_tick); i++) {
            IVoteForLaunch.Ballot memory ballot = everyVotes[_tick][uint(i)];
            ballots[ballot.addr] += ballot.amount;
            delete(Ids[_tick][ballot.addr]);
            emit CancelVote(_tick, applications[_tick].applicant, ballot.addr, ballot.amount);
        }
        delete(everyVotes[_tick]);
    }

    function _removeFromTickArray(string memory _tick) private {
        uint len = tickArray.length;
        if(len == 0) return;
        if(tickIds[_tick] == 0) return;
        uint id = tickIds[_tick] - 1;

        if(id < len - 1) {
            tickArray[id] = tickArray[len - 1];
            tickArray.pop();
            tickIds[tickArray[id]] = id + 1;
        } else {
            tickArray.pop();
        }
        delete(tickIds[_tick]);
    }

    function _removeVoteByAddress(string memory _tick, address _addr) private {
        uint _totalVoters = totalVoters(_tick);
        require(_totalVoters > 0, "no votes");
        require(Ids[_tick][_addr] > 0, "You did not voted");
        uint id = Ids[_tick][_addr] - 1;

        if(id < _totalVoters - 1) {
            // exchange
            everyVotes[_tick][id] = everyVotes[_tick][_totalVoters - 1];
            everyVotes[_tick].pop();
            Ids[_tick][everyVotes[_tick][id].addr] = id + 1;
        } else {
            // no exchange
            everyVotes[_tick].pop();
        }
        delete(Ids[_tick][_addr]);
    }
}
