// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./AccessControl.sol";

contract Matrix is AccessControl {
    struct UserRound {
        uint256 round;
        uint256 sub;
        uint256 price;
        uint256 timestamp;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public maxRound = 4;
    uint256 public maxSubRound = 12;
    uint256 public waitSubRound = 604800; // 7 days 604800
    uint256 public waitNextRound = 604800; // 7 days 604800
    address public USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public receiverActive = 0x0D564801cB47d7Ab32460c5310c9500cD344D2f8;
    address public receiverVote = 0x2549f3b8fB042EFBb63e94439f202554bDb0B715;
    address public userContract = 0x7E8455F575F4Fc7513AaEdc22B8df0B7C68cbD99;

    mapping(uint256 => uint256) public roundVoteFee;
    mapping(uint256 => uint256) public roundActivePriceFee;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        public timeVotes; // user => round => sub round => timestamp
    mapping(address => UserRound) public userRoundDetail;
    mapping(address => bool) public isFinish;

    event ACTIVE_ROUND(
        address indexed user,
        uint256 round,
        uint256 price,
        uint256 timestamp
    );
    event VOTE_ROUND(
        address indexed user,
        uint256 round,
        uint256 sub,
        uint256 price,
        uint256 timestamp
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, userContract);
        roundVoteFee[1] = 15e6;
        roundVoteFee[2] = 30e6;
        roundVoteFee[3] = 45e6;
        roundVoteFee[4] = 60e6;
        roundActivePriceFee[1] = 5e6;
        roundActivePriceFee[2] = 10e6;
        roundActivePriceFee[3] = 15e6;
        roundActivePriceFee[4] = 20e6;
    }

    function voteRound() public {
        UserRound storage ur = userRoundDetail[msg.sender];
        require(!isFinish[msg.sender], "you have finish");
        require(ur.timestamp < block.timestamp, "can not vote right now");
        require(
            ur.round > 0 && ur.round <= maxRound,
            "can not vote this round"
        );
        require(ur.sub > 0 && ur.sub <= maxSubRound, "can not vote this sub");
        require(
            IERC20(USDT).balanceOf(msg.sender) >= roundVoteFee[ur.round],
            "the balance in the account is not sufficient to proceed."
        );

        // history round
        IERC20(USDT).transferFrom(
            msg.sender,
            receiverVote,
            roundVoteFee[ur.round]
        );
        emit VOTE_ROUND(
            msg.sender,
            ur.round,
            ur.sub,
            roundVoteFee[ur.round],
            block.timestamp
        );

        // next round
        uint256 nextSub = ur.sub + 1;
        if (nextSub > 12) {
            if (ur.round + 1 <= maxRound) {
                timeVotes[msg.sender][ur.round + 1][0] =
                    timeVotes[msg.sender][ur.round][12] +
                    waitNextRound;

                ur.round = ur.round + 1;
                ur.sub = 0;
                ur.price = roundActivePriceFee[ur.round];
                ur.timestamp = timeVotes[msg.sender][ur.round][0];
            } else {
                isFinish[msg.sender] = true;
            }
        } else {
            timeVotes[msg.sender][ur.round][nextSub] =
                block.timestamp +
                waitSubRound;
            ur.sub = nextSub;
            ur.timestamp = timeVotes[msg.sender][ur.round][nextSub];
        }
    }

    function activeRound() public {
        UserRound storage ur = userRoundDetail[msg.sender];
        require(!isFinish[msg.sender], "you have finish");
        require(ur.round > 0 && ur.round <= maxRound, "not found round");
        require(ur.sub == 0, "active fail");
        require(ur.timestamp < block.timestamp, "can not active right now");
        require(
            roundActivePriceFee[ur.round] > 0,
            "this round has not been set up yet."
        );
        require(
            IERC20(USDT).balanceOf(msg.sender) >= roundActivePriceFee[ur.round],
            "the balance in the account is not sufficient to proceed."
        );

        timeVotes[msg.sender][ur.round][0] = block.timestamp;
        timeVotes[msg.sender][ur.round][1] = timeVotes[msg.sender][ur.round][0];
        ur.sub = 1;
        ur.price = roundVoteFee[ur.round];
        ur.timestamp = timeVotes[msg.sender][ur.round][1];

        IERC20(USDT).transferFrom(
            msg.sender,
            receiverActive,
            roundActivePriceFee[ur.round]
        );
        emit ACTIVE_ROUND(
            msg.sender,
            ur.round,
            roundActivePriceFee[ur.round],
            block.timestamp
        );
    }

    function setUSDTContract(address _contract) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        USDT = _contract;
    }

    function setActiveReceiver(address _address) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        receiverActive = _address;
    }

    function setVoteReceiver(address _address) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        receiverVote = _address;
    }

    function setUserContract(address _address) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        userContract = _address;
    }

    function clearUnknownToken(address _tokenAddress) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        uint256 contractBalance = IERC20(_tokenAddress).balanceOf(
            address(this)
        );
        IERC20(_tokenAddress).transfer(address(msg.sender), contractBalance);
    }

    function setMaxRound(uint256 _number) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        maxRound = _number;
    }

    function setMaxSubRound(uint256 _number) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        maxSubRound = _number;
    }

    function setRoundPrice(uint256 _round, uint256 _price) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        roundVoteFee[_round] = _price;
    }

    function setRoundActivePrice(uint256 _round, uint256 _price) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        roundActivePriceFee[_round] = _price;
    }

    function setUserRoundDetail(
        address _user,
        uint256 _round,
        uint256 _sub,
        uint256 _timestamp
    ) public returns (bool) {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        userRoundDetail[_user] = UserRound(
            _round,
            _sub,
            _sub == 0 ? roundActivePriceFee[_round] : roundVoteFee[_round],
            _timestamp
        );
        return true;
    }

    function setWaitSubRound(uint256 _number) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        waitSubRound = _number;
    }

    function setWaitNextRound(uint256 _number) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        waitNextRound = _number;
    }

    function setAccountTimeVote(
        address _user,
        uint256 _round,
        uint256 _sub,
        uint256 _timestamp
    ) public returns (bool) {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        timeVotes[_user][_round][_sub] = _timestamp;
        return true;
    }
}

