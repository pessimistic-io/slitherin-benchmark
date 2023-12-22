pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";

contract PepeLStaking {
    using SafeMath for uint256;

    IERC20 public lpToken;
    IERC20 public ethToken;
    address public owner;
    uint256 public vestingDuration = 7 days;

    struct Staker {
        uint256 amount;
        uint256 startTime;
    }

    mapping(address => Staker) public stakers;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    constructor(address _lpToken, address _ethToken) {
        lpToken = IERC20(_lpToken);
        ethToken = IERC20(_ethToken);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    function stake(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        lpToken.transferFrom(msg.sender, address(this), _amount);

        if (stakers[msg.sender].amount > 0) {
            _claimRewards(msg.sender);
        } else {
            stakers[msg.sender].startTime = block.timestamp;
        }

        stakers[msg.sender].amount = stakers[msg.sender].amount.add(_amount);
        totalStaked = totalStaked.add(_amount);

        emit Staked(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external {
        require(stakers[msg.sender].amount >= _amount, "Insufficient staked balance");

        _claimRewards(msg.sender);

        stakers[msg.sender].amount = stakers[msg.sender].amount.sub(_amount);
        totalStaked = totalStaked.sub(_amount);

        lpToken.transfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    function claimRewards() external {
        _claimRewards(msg.sender);
    }

    function _claimRewards(address _user) internal {
        require(stakers[_user].amount > 0, "No staked balance");

        uint256 elapsedTime = block.timestamp.sub(stakers[_user].startTime);

        if (elapsedTime >= vestingDuration) {
            uint256 ethBalance = ethToken.balanceOf(address(this));
            uint256 reward = ethBalance.mul(stakers[_user].amount).div(totalStaked);

            ethToken.transfer(_user, reward);

            emit RewardsClaimed(_user, reward);
            stakers[_user].startTime = block.timestamp;
        }
    }

    function withdraw(uint256 _amount) external onlyOwner {
        require(ethToken.balanceOf(address(this)) >= _amount, "Insufficient contract balance");
        ethToken.transfer(owner, _amount);
    }
}
