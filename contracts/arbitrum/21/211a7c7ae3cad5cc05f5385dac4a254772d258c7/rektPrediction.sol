//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

contract rektPrediction is Ownable, ReentrancyGuard {
    struct UserData {
        uint256 totalContributed;
        bool isTrue;
    }

    struct ContractData {
        uint64 startTime;
        uint64 endTime;
        uint64 finalTime;
        uint256 totalRektTeamA;
        uint64 totalUsersTeamA;
        uint256 totalRektTeamB;
        uint64 totalUsersTeamB;
        uint8 serviceFee;
        bool isFinalized;
    }

    IERC20 public constant rekt = IERC20(0x1D987200dF3B744CFa9C14f713F5334CB4Bc4D5D);
    uint256 private constant ACC_FACTOR = 10 ** 36;
    address constant public DEAD = 0x000000000000000000000000000000000000dEaD;

    string public description;
    bool private result;
    bool public isFinalized;

    uint256 private rewardPerContribution;
    uint256 public minContribution = 10**6; //1 rekt token
    uint256 public totalContributedTeamA;
    uint64 public totalUsersA;
    uint256 public totalContributedTeamB;
    uint64 public totalUsersB;

    uint64 public contributionStartTime;
    uint64 public contributionEndTime;
    uint64 public eventEndTime;
    uint8 public serviceFee = 10;

    mapping(address => UserData) public userContribution;

    event UserContribution(address indexed user, uint256 totalContribution, bool isTrue);
    event ClaimReward(address indexed user, uint256 deposit, uint256 reward);
    event SubmitResult(bool isTrue, uint256 time);
    event TimesSet(uint64 startTime, uint64 endTime, uint64 finalTime);
    event DescriptionUpdated(string description);
    event ServiceFeeUpdated(uint8 newFee);
    event MinContributionUpdated(uint256 newMinContributionAmount);

    constructor (
        address _owner,
        string memory _description
    ) {
        _transferOwnership(_owner);
        description = _description;

        emit DescriptionUpdated(_description);
    }

        function setTimes(
            uint64 _contributionStartTime,
            uint64 _contributionEndTime,
            uint64 _eventEndTime
        ) external onlyOwner {
        require(contributionStartTime == 0, "ALREADY SET"); //|| block.timestamp < contributionStartTime

        require(_contributionStartTime > block.timestamp, "START TIME MUST BE IN FUTURE");
        require(_contributionEndTime > _contributionStartTime, "END TIME MUST BE GREATER THAN START TIME");
        require(_eventEndTime > _contributionEndTime, "FINAL TIME MUST BE GREATER THAN END TIME");

        contributionStartTime = _contributionStartTime;
        contributionEndTime = _contributionEndTime;
        eventEndTime = _eventEndTime;

        emit TimesSet(contributionStartTime, contributionEndTime, eventEndTime);
    }

    function contribute(uint256 _amount, bool _isTrue) external nonReentrant {
        UserData memory user = userContribution[_msgSender()];
        require(
            block.timestamp >= contributionStartTime &&
            block.timestamp <= contributionEndTime,
            "OUTSIDE CONTRIBUTION PERIOD"
        );

        uint8 contribution = 1;

        if (user.totalContributed != 0) {
            require(user.isTrue == _isTrue, "CANNOT CONTRIBUTE TO ANOTHER TEAM");
            contribution = 0;
        }

        require(
            user.totalContributed + _amount >= minContribution &&
            _amount > 0,
            "LESS THAN MIN CONTRIBUTION"
        );

        require(rekt.transferFrom(_msgSender(), address(this), _amount), "REKT TRANSFER FAILED");

        user.totalContributed += _amount;
        user.isTrue = _isTrue;

        userContribution[_msgSender()] = user;

        if(_isTrue) {
            totalContributedTeamA += _amount;
            totalUsersA += contribution;
        } else {
            totalContributedTeamB += _amount;
            totalUsersB += contribution;
        }

        emit UserContribution(_msgSender(), user.totalContributed, user.isTrue);
    }

    function finalize(bool isTrue) external nonReentrant onlyOwner {
        require(
            block.timestamp >= eventEndTime &&
            eventEndTime != 0,
            "EVENT TIME NOT ENDED"
        );
        require(!isFinalized, "ALREADY FINALIZED");

        if (isTrue) {
            uint256 fee = totalContributedTeamB * serviceFee / 100;
            if (fee > 0) {
                totalContributedTeamB -= fee;
                require(rekt.transfer(DEAD, fee), "REKT TRANSFER FAILED");
            }
            rewardPerContribution = totalContributedTeamB * ACC_FACTOR / totalContributedTeamA;
        } else {
            uint256 fee = totalContributedTeamA * serviceFee / 100;
            if (fee > 0) {
                totalContributedTeamA -= fee;
                require(rekt.transfer(DEAD, fee), "REKT TRANSFER FAILED");
            }
            rewardPerContribution = totalContributedTeamA * ACC_FACTOR / totalContributedTeamB;
        }

        result = isTrue;
        isFinalized = true;
        emit SubmitResult(isTrue, block.timestamp);
    }

    function claimWin() external nonReentrant {
        require(block.timestamp >= eventEndTime, "EVENT TIME NOT ENDED");
        require(isFinalized, "NOT FINALIZED");

        UserData memory user = userContribution[_msgSender()];

        require(user.totalContributed > 0, "NO CONTRIBUTION");
        require(user.isTrue == checkResult(), "NOT IN WINNING TEAM");

        uint256 userReward = rewardPerContribution * user.totalContributed / ACC_FACTOR;
        uint256 totalReturnAmount = user.totalContributed +  userReward;

        emit ClaimReward(_msgSender(), user.totalContributed, userReward);
        delete userContribution[_msgSender()];

        require(rekt.transfer(_msgSender(), totalReturnAmount), "REKT TRANSFER FAILED");
    }

    function checkResult() public view returns (bool) {
        if (isFinalized) {
            return result;
        }
        revert("RESULT NOT SUBMITTED");
    }

    function changeDescription(string memory newDescription) external onlyOwner {
        require(contributionStartTime == 0, "CANNOT CHANGE AFTER START");
        bytes memory _description = bytes(newDescription);
        require(_description.length > 0, "EMPTY STRING");

        description = newDescription;

        emit DescriptionUpdated(description);
    }

    function changeTax(uint8 newFee) external onlyOwner {
        require(contributionStartTime == 0, "CANNOT CHANGE AFTER START");
        require(newFee <= 10, "MORE THAN 10%");

        serviceFee = newFee;

        emit ServiceFeeUpdated(serviceFee);
    }

    function changeMinContribution(uint256 newMinContribution) external onlyOwner {
        minContribution = newMinContribution;
        emit MinContributionUpdated(minContribution);
    }

    function viewContractData() external view returns (ContractData memory) {
        return(ContractData(
            contributionStartTime,
            contributionEndTime,
            eventEndTime,
            totalContributedTeamA,
            totalUsersA,
            totalContributedTeamB,
            totalUsersB,
            serviceFee,
            isFinalized
        ));
    }
}
