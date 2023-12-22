// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface token is IERC20 {
    function burn(uint256 amount) external;
}

interface IMasterChef {
    function mintRewards(address _receiver, uint256 _amount) external;
}

contract gSHEKEL is ERC20("gSHEKEL", "gSHEKEL"), Ownable, ReentrancyGuard { 
    using SafeERC20 for IERC20;
    using SafeERC20 for token;
    using SafeMath for uint256;

    token public SHEKEL;
    uint256 public rewardRate;
    address public masterChef;
    address public _operator;

    mapping(address => bool) public minters;

    constructor(token _token) {
        _operator = msg.sender;
        SHEKEL = _token;
    }

    modifier onlyMinter() {
        require(minters[msg.sender] == true, "Only minters allowed");
        _;
    }

    modifier onlyMasterChef() {
        require(msg.sender == masterChef, "Caller is not MasterChef contract");
        _;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    struct vestPosition {
        uint256 totalVested;
        uint256 lastInteractionTime;
        uint256 VestPeriod;
    }

    mapping (address => vestPosition[]) public userInfo;
    mapping (address => uint256) public userPositions;

    uint256 public vestingPeriod = 30 days;
    uint256 public shortVestingPeriod = 7 days;

    function mint(address recipient_, uint256 amount_) external onlyMinter returns (bool) {
        _mint(recipient_, amount_);
        return true;
    }

    function burn(uint256 _amount) external  {
        _burn(msg.sender, _amount);
    }

    function remainTime(address _address, uint256 id) public view returns(uint256) {
        uint256 timePass = block.timestamp.sub(userInfo[_address][id].lastInteractionTime);
        uint256 remain;
        if (timePass >= userInfo[msg.sender][id].VestPeriod){
            remain = 0;
        }
        else {
            remain = userInfo[msg.sender][id].VestPeriod- timePass;
        }
        return remain;
    }


    function vest(uint256 _amount) external nonReentrant {

        require(this.balanceOf(msg.sender) >= _amount, "gSHEKEL balance too low");

        userInfo[msg.sender].push(vestPosition({
            totalVested: _amount,
            lastInteractionTime: block.timestamp,
            VestPeriod: vestingPeriod
        }));

        userPositions[msg.sender] += 1; 
        _burn(msg.sender, _amount);
    }

   function vestHalf(uint256 _amount) external nonReentrant {

        require(this.balanceOf(msg.sender) >= _amount, "gSHEKEL balance too low");

        userInfo[msg.sender].push(vestPosition({
            totalVested: _amount.mul(100).div(200),
            lastInteractionTime: block.timestamp,
            VestPeriod: shortVestingPeriod
        }));
        
        userPositions[msg.sender] += 1; 
        _burn(msg.sender, _amount);
    }

    function lock(uint256 _amount) external nonReentrant {
        require(SHEKEL.balanceOf(msg.sender) >= _amount, "SHEKEL balance too low");
        uint256 amountOut = _amount;
        SHEKEL.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, amountOut);
        SHEKEL.burn(_amount);
    }

    function claim(uint256 id) external nonReentrant {
        require(remainTime(msg.sender, id) == 0, "vesting not end");
        vestPosition storage position = userInfo[msg.sender][id];
        uint256 claimAmount = position.totalVested;
        position.totalVested = 0;
        IMasterChef(masterChef).mintRewards(msg.sender, claimAmount);
    }

    function cancelVest(uint256 id) external nonReentrant {
        require(remainTime(msg.sender, id) > 0, "vesting not end");
        vestPosition storage position = userInfo[msg.sender][id];
        uint256 claimAmount = position.totalVested;
        SHEKEL.safeTransferFrom(msg.sender, address(this), claimAmount.mul(3000).div(10000));
        SHEKEL.burn(claimAmount.mul(3000).div(10000));
        position.totalVested = 0;
        position.VestPeriod = 0;
        _mint(msg.sender, claimAmount);
    }

    function setRewardRate(uint256 _rewardRate) public onlyMasterChef {
        rewardRate = _rewardRate;
    }

    function setMasterChef(address _masterChef) public onlyOwner {
        masterChef = _masterChef;
    }

    function transferOperator(address newOperator_) public onlyOwner {
        _transferOperator(newOperator_);
    }

    function _transferOperator(address newOperator_) internal {
        require(newOperator_ != address(0), "operator: zero address given for new operator");
        _operator = newOperator_;
    }

    function setMinters(address _minter, bool _canMint) public onlyOperator {
        minters[_minter] = _canMint;
    }

}

