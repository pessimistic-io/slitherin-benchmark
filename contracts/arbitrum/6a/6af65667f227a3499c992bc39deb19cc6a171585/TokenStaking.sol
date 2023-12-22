// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IVester} from "./IVester.sol";
import {ERC20Vote} from "./ERC20Vote.sol";
import {Util} from "./Util.sol";

interface ITokenStakingPlugin {
    function onAllocate(address who, uint256 amount) external;
    function onDeallocate(address who, uint256 amount) external;
}

contract TokenStaking is Util {
    error NotWhitelisted();
    error NotEnoughAllocatedTokens();
    error NotEnoughUnallocatedTokens();
    error BurnTimeTooShort();

    struct Checkpoint {
        uint32 fromTimestamp;
        uint96 votes;
    }
    struct Plugin {
        uint256 amount;
        address target;
        uint256 deallocationFee;
        address deallocationTarget;
    }

    string public constant name = "Staked Rodeo";
    string public constant symbol = "xRDO";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public allocated;
    mapping(address => mapping(uint256 => uint256)) public allocations;
    mapping(address => address) internal _delegates;
    mapping(address => mapping(uint256 => Checkpoint)) public checkpoints;
    mapping(address => uint256) public numCheckpoints;
    mapping(address => bool) public whitelist;
    IERC20 public token;
    IVester public vester;
    uint256 public vestingTimeMin = 15 days;
    uint256 public vestingTimeMax = 180 days;
    uint256 public vestingFee = 0.5e18;
    address public vestingFeeTarget;
    mapping(uint256 => Plugin) public plugins;

    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event SetPlugin(uint256 indexed index, address plugin, uint256 deallocationFee, address deallocationTarget);
    event Mint(address indexed recipient, uint256 amount);
    event Burn(address indexed recipient, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event Allocated(address indexed who, uint256 indexed index, uint256 amount);
    event Deallocated(address indexed who, uint256 indexed index, uint256 amount, uint256 fee);

    constructor(address _token, address _vester) {
        token = IERC20(_token);
        vester = IVester(_vester);
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "paused") paused = data == 1;
        if (what == "vestingTimeMin") vestingTimeMin = data;
        if (what == "vestingTimeMax") vestingTimeMax = data;
        if (what == "vestingFee") vestingFee = data;
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "token") token = IERC20(data);
        if (what == "vester") vester = IVester(data);
        if (what == "whitelist") whitelist[data] = !whitelist[data];
        if (what == "vestingFeeTarget") vestingFeeTarget = data;
        emit File(what, data);
    }

    function setPlugin(uint256 index, address target, uint256 deallocationFee, address deallocationTarget) external auth {
        Plugin storage plugin = plugins[index];
        plugin.target = target;
        plugin.deallocationFee = deallocationFee;
        plugin.deallocationTarget = deallocationTarget;
        emit SetPlugin(index, target, deallocationFee, deallocationTarget);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        if (!whitelist[msg.sender]) revert NotWhitelisted();
        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        _moveDelegates(delegates(msg.sender), delegates(to), amount);
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (!whitelist[msg.sender]) revert NotWhitelisted();
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        _moveDelegates(delegates(from), delegates(to), amount);
        emit Transfer(from, to, amount);
        return true;
    }

    function delegates(address delegator) public view returns (address delegatee) {
        address current = _delegates[delegator];
        delegatee = current == address(0) ? delegator : current;
    }

    function getCurrentVotes(address account) public view returns (uint256 votes) {
        unchecked {
            uint256 nCheckpoints = numCheckpoints[account];
            votes = nCheckpoints != 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
        }
    }

    function delegate(address delegatee) public {
        address currentDelegate = delegates(msg.sender);
        _delegates[msg.sender] = delegatee;
        _moveDelegates(currentDelegate, delegatee, balanceOf[msg.sender]);
        emit DelegateChanged(msg.sender, currentDelegate, delegatee);
    }

    function getPriorVotes(address account, uint256 timestamp) public view returns (uint96 votes) {
        require(block.timestamp > timestamp, "NOT_YET_DETERMINED");
        uint256 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) return 0;
        unchecked {
            if (checkpoints[account][nCheckpoints - 1].fromTimestamp <= timestamp) {
                return checkpoints[account][nCheckpoints - 1].votes;
            }
            if (checkpoints[account][0].fromTimestamp > timestamp) return 0;
            uint256 lower;
            uint256 upper = nCheckpoints - 1;
            while (upper > lower) {
                uint256 center = upper - (upper - lower) / 2;
                Checkpoint memory cp = checkpoints[account][center];
                if (cp.fromTimestamp == timestamp) {
                    return cp.votes;
                } else if (cp.fromTimestamp < timestamp) {
                    lower = center;
                } else {
                    upper = center - 1;
                }
            }
            return checkpoints[account][lower].votes;
        }
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount != 0) {
            if (srcRep != address(0)) {
                uint256 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum != 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint256 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum != 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint256 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        unchecked {
            if (nCheckpoints != 0 && checkpoints[delegatee][nCheckpoints - 1].fromTimestamp == block.timestamp) {
                checkpoints[delegatee][nCheckpoints - 1].votes = safeCastTo96(newVotes);
            } else {
                checkpoints[delegatee][nCheckpoints] = Checkpoint(safeCastTo32(block.timestamp), safeCastTo96(newVotes));
                numCheckpoints[delegatee] = nCheckpoints + 1;
            }
        }
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function mint(uint256 amount) external live loop {
        token.transferFrom(msg.sender, address(this), amount);
        totalSupply += amount;
        unchecked {
            balanceOf[msg.sender] += amount;
        }
        _moveDelegates(address(0), delegates(msg.sender), amount);
        emit Transfer(address(0), msg.sender, amount);
        emit Mint(msg.sender, amount);
    }

    function burn(uint256 amount, uint256 time) external live loop {
        uint256 available = balanceOf[msg.sender] - allocated[msg.sender];
        if (available < amount) revert NotEnoughUnallocatedTokens();
        _burn(msg.sender, amount);
        // TODO, shorter for private participants
        if (time < vestingTimeMin) revert BurnTimeTooShort();
        if (time > vestingTimeMax) time = vestingTimeMax;
        uint256 size = vestingTimeMax - vestingTimeMin;
        uint256 rate = vestingFee * (size - (time - vestingTimeMin)) / size;
        uint256 fee = amount * rate / 1e18;
        token.transfer(vestingFeeTarget, fee);
        token.approve(address(vester), amount - fee);
        vester.vest(1, msg.sender, address(token), amount - fee, 0, 0, time);
        emit Burn(msg.sender, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        _moveDelegates(delegates(from), address(0), amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    function allocate(uint256 index, uint256 amount) public live loop {
        uint256 available = balanceOf[msg.sender] - allocated[msg.sender];
        if (available < amount) revert NotEnoughUnallocatedTokens();
        allocated[msg.sender] += amount;
        allocations[msg.sender][index] += amount;

        Plugin storage plugin = plugins[index];
        plugin.amount += amount;
        if (plugin.target != address(0)) {
            ITokenStakingPlugin(plugin.target).onAllocate(msg.sender, amount);
        }

        emit Allocated(msg.sender, index, amount);
    }

    function deallocate(uint256 index, uint256 amount) public live loop {
        uint256 available = allocations[msg.sender][index];
        if (available < amount) revert NotEnoughAllocatedTokens();
        allocated[msg.sender] -= amount;
        allocations[msg.sender][index] -= amount;

        Plugin storage plugin = plugins[index];
        plugin.amount -= amount;
        uint256 fee;
        if (plugin.target != address(0)) {
            ITokenStakingPlugin(plugin.target).onDeallocate(msg.sender, amount);
            fee = amount * plugin.deallocationFee / 1e18;
            if (fee > 0) {
                _burn(msg.sender, fee);
                token.transfer(plugin.deallocationTarget, fee);
            }
        }

        emit Deallocated(msg.sender, index, amount, fee);
    }

    function getUser(address user, uint256 indexes) public view returns (uint256, uint256, uint256[] memory) {
        uint256[] memory amounts = new uint256[](indexes);
        for (uint256 i = 0; i < indexes; i++) {
            amounts[i] = allocations[user][i];
        }
        return (balanceOf[user], allocated[user], amounts);
    }

    function safeCastTo32(uint256 x) internal pure returns (uint32 y) {
        require(x <= type(uint32).max);
        y = uint32(x);
    }

    function safeCastTo96(uint256 x) internal pure returns (uint96 y) {
        require(x <= type(uint96).max);
        y = uint96(x);
    }
}

