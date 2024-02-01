pragma solidity ^0.5.7;

import "./oraclizeAPI.sol";

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

contract Ownable {
    address public owner;

    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor(address initialOwner) public {
        require(initialOwner != address(0));
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(owner);
        owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address who) external view returns (uint256);
}

interface Watcher {
    function draw() external payable returns (bool);
}

contract Drawer is Ownable, usingOraclize {
    using SafeMath for uint256;

    enum State {Stopped, Active}
    State public state = State.Stopped;

    mapping(address => bool) _watchers;
    mapping(bytes32 => address) _quiries;

    uint256 public gasPrice;
    uint256 public gasLimit;
    uint256 public blockTime;

    event OracleCall(
        address watcher,
        uint256 delay,
        uint256 gasPrice,
        uint256 gasLimit
    );
    event WatcherCall(address watcher, bool success);
    event InsufficientFunds();

    modifier inActiveState() {
        require(state == State.Active);
        _;
    }

    modifier inStoppedState() {
        require(state == State.Stopped);
        _;
    }

    constructor(
        address[] memory newWatchers,
        uint256 currentGasPrice,
        uint256 currentGasLimit,
        uint256 currentBlockTime
    ) public payable Ownable(msg.sender) {
        setWatchers(newWatchers);
        setGasPrice(currentGasPrice);
        setGasLimit(currentGasLimit);
        setCurrentBlockTime(currentBlockTime);

        if (msg.value > 0) {
            startQuery();
        }
    }

    function() external payable {
        if (msg.value > 0) {
            startQuery();
        }
    }

    function donate() external payable {}

    function __delegateCall(uint256 blocks, bool update) public returns (bool) {
        if (!isWatcher(msg.sender)) {
            return true;
        }

        if (update) {
            _update(blocks * blockTime);
        }

        return true;
    }

    function stopQuery() external onlyOwner inActiveState {
        state = State.Stopped;
    }

    function startQuery() public payable onlyOwner inStoppedState {
        state = State.Active;
    }

    function setWatchers(address[] memory newWatchers) public onlyOwner {
        for (uint256 i = 0; i < newWatchers.length; i++) {
            require(_isContract(newWatchers[i]));
            _watchers[newWatchers[i]] = true;
        }
    }

    function removeWatchers(address[] memory watchers) public onlyOwner {
        for (uint256 i = 0; i < watchers.length; i++) {
            _watchers[watchers[i]] = false;
        }
    }

    function setGasPrice(uint256 newValue) public onlyOwner {
        require(newValue > 0);
        gasPrice = newValue;
        oraclize_setCustomGasPrice(newValue);
    }

    function setGasLimit(uint256 newValue) public onlyOwner {
        require(newValue > 0);
        gasLimit = newValue;
    }

    function setCurrentBlockTime(uint256 newValue) public onlyOwner {
        require(newValue > 0);
        blockTime = newValue;
    }

    function __callback(
        bytes32 myid,
        string memory result,
        bytes memory proof
    ) public {
        require(msg.sender == oraclize_cbAddress());

        proof;
        result;

        if (state == State.Active) {
            address watcher = _quiries[myid];
            bool sendResult = Watcher(watcher).draw();
            emit WatcherCall(address(watcher), sendResult);
        }
    }

    function _update(uint256 delay) internal {
        if (oraclize_getPrice("URL") > address(this).balance) {
            emit InsufficientFunds();
        } else {
            bytes32 id = oraclize_query(delay, "URL", "-", gasLimit);
            _quiries[id] = msg.sender;
            emit OracleCall(msg.sender, delay, gasPrice, gasLimit);
        }
    }

    function withdraw(address payable receiver, uint256 value)
        external
        onlyOwner
    {
        require(receiver != address(0));
        receiver.transfer(value);
    }

    function withdrawERC20(address ERC20Token, address recipient)
        external
        onlyOwner
    {
        uint256 amount = IERC20(ERC20Token).balanceOf(address(this));
        IERC20(ERC20Token).transfer(recipient, amount);
    }

    function isWatcher(address addr) public view returns (bool) {
        return (_watchers[addr]);
    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}

