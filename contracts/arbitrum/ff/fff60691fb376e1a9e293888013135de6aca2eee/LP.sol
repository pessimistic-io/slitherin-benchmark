// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "./Pausable.sol";
import "./Ownable.sol";
import "./IVault.sol";
import "./IRevenue.sol";
import "./ERC20.sol";

library SafeMath {
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

interface IStorage {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stakeFor(address _from, address _to,uint _value) external returns (uint);
    function withdraw(address account, uint _index) external;
    function getUserStakeLength(address _addr) external view returns (uint256);
}

contract LP is Ownable, Pausable, ERC20 {
    using SafeMath for uint256;

    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
    }

    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    IStorage public stor;
    uint256 public rewardDuration = 1;
    uint256 public refundTotal;
    uint256 public rewardTotal;

    address public revenue;
    address public helper;

    mapping(address => Boardseat) private directors;
    BoardSnapshot[] private boardHistory;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    uint public depositFee;
    uint public withdrawFee;
    uint constant private denominator = 10000;

    mapping(address => uint) public depositTime;
    mapping(address => uint) public rewardTime;

    address public vault;

    int public totalVaultIncome;

    mapping(address => uint) public depositAmt;

    constructor(address _stor) Ownable() Pausable() ERC20("Vortex ETH LP", "VX-ELP"){ 
        depositFee = 20;
        withdrawFee = 50;

        stor = IStorage(_stor);
        BoardSnapshot memory genesisSnapshot = BoardSnapshot({
            time: block.timestamp,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        boardHistory.push(genesisSnapshot);
    }

    function setVault(address _vault) external onlyOwner() {
        vault = _vault;
    }

    function setRevenue(address _revenue) external onlyOwner() {
        revenue = _revenue;
    }

    function setDepositFee(uint _fee) external onlyOwner() {
        depositFee = _fee;
    }

    function setWithdrawFee(uint _fee) external onlyOwner() {
        withdrawFee = _fee;
    }

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() public view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256){
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director) internal view returns (BoardSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerShare;

        uint256 rewardEarned = stor.balanceOf(director)
        .mul(latestRPS.sub(storedRPS)).div(1e18)
        .add(directors[director].rewardEarned);
        return rewardEarned;
    }

    modifier updateReward(address director) {
        (, uint256 amount) = getTotalIncome().trySub(rewardTotal);
        if(amount>0 && getLatestSnapshot().time.add(rewardDuration) < block.timestamp) {
            allocate(amount);
        }
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }

    function deposit() external payable whenNotPaused() updateReward(msg.sender) {
        uint _amt = msg.value;
        require(_amt != 0, "value is 0");
        payable(revenue).transfer(_amt * depositFee / denominator);
        uint _depositAmt = _amt - _amt * depositFee / denominator;

        uint _lpAmt;
        if ((totalSupply() != 0) && (getCurrentReserve() != 0)) {
            _lpAmt = _depositAmt * totalSupply() / getCurrentReserve();
        }
        else {
            _lpAmt = _depositAmt;
        }

        payable(vault).transfer(_depositAmt);
        depositTime[msg.sender] = block.timestamp;
        depositAmt[msg.sender] = depositAmt[msg.sender] + _depositAmt;
        
        _mint(msg.sender, _lpAmt);

        stor.stakeFor(msg.sender, msg.sender, _lpAmt);
    }

    function withdraw() external whenNotPaused() updateReward(msg.sender) {
        uint _lpAmt = balanceOf(msg.sender);
        require(_lpAmt != 0, "amount is 0");
        uint _amt = getCurrentReserve() * _lpAmt / totalSupply();
        if (block.timestamp - depositTime[msg.sender] <= 24 hours) {
            uint _fee = _amt * withdrawFee / denominator;
            IVault(vault).withdraw(revenue, _fee);
            _amt = _amt - _fee;
        }

        IVault(vault).withdraw(msg.sender, _amt);
        _burn(msg.sender, _lpAmt);

        uint len = stor.getUserStakeLength(msg.sender);
        for(uint i = 0; i < len; i++){
            stor.withdraw(msg.sender, 0);
        }

        totalVaultIncome = totalVaultIncome + int(_amt) - int(depositAmt[msg.sender]);
        depositAmt[msg.sender] = 0;
    }

    function getReward() external updateReward(msg.sender) whenNotPaused() {
        require(rewardTime[msg.sender] + 24 hours <= block.timestamp, "reward not expire");

        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            directors[msg.sender].rewardEarned = 0;
            IRevenue(revenue).lpReward(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
            refundTotal = refundTotal.add(reward);
        }

        rewardTime[msg.sender] = block.timestamp;
    }

    function changeDuration(uint256 _rewardDuration) public onlyOwner{
        rewardDuration = _rewardDuration;
    }

    function getLPPrice(uint _amt) external view returns(uint) {
        uint _lpAmt;
        if ((totalSupply() != 0) && (getCurrentReserve() != 0)) {
            _lpAmt = _amt * totalSupply() / getCurrentReserve();
        }
        else {
            _lpAmt = _amt;
        }
        return _lpAmt;
    }

    function getTotalIncome() public view returns (uint){
        uint total = IRevenue(revenue).lp_revenue();
        return total.add(refundTotal);
    }

    function getAccumulatedIncome() public view returns (int) {
        return int(getTotalIncome()) + totalVaultIncome;
    }

    function getCurrentReserve() public view returns(uint) {
        return vault.balance;
    }

    function addNewSnapshot(uint256 amount) private{
        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(stor.totalSupply()));

        BoardSnapshot memory newSnapshot = BoardSnapshot({
            time: block.timestamp,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardHistory.push(newSnapshot);
        rewardTotal = rewardTotal.add(amount);
    }

    function allocate(uint256 amount) private{
        if(stor.totalSupply() > 0){
            addNewSnapshot(amount);
            emit RewardAdded(msg.sender, amount);
        }
    }

    function pause() external onlyOwner() {
        _pause();
    }

    function unpause() external onlyOwner() {
        _unpause();
    }

    function rescue(address _token) external onlyOwner() {
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this))-1);
    }

    function rescueETH() external onlyOwner() {
        payable(address(owner())).transfer(address(this).balance);
    }

    receive() payable external { }
}
