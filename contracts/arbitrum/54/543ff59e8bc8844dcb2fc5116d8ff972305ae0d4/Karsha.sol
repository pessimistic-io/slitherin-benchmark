// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./SafeMath.sol";
import "./Address.sol";

import "./IsPana.sol";
import "./IKarsha.sol";
import "./ERC20.sol";
import "./PanaAccessControlled.sol";

contract Karsha is IKarsha, ERC20, PanaAccessControlled {

    /* ========== DEPENDENCIES ========== */

    using Address for address;
    using SafeMath for uint256;

    /* ========== MODIFIERS ========== */

    modifier onlyStaking() {
        require(msg.sender == staking, "Only Staking");
        _;
    }

    /* ========== EVENTS ========== */

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    /* ========== DATA STRUCTURES ========== */

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }

    /* ========== STATE VARIABLES ========== */

    IsPana public sPANA;
    address public staking; // minter

    mapping(address => mapping(uint256 => Checkpoint)) public checkpoints;
    mapping(address => uint256) public numCheckpoints;
    mapping(address => address) public delegates;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _staking, address _sPana, address _authority)
        ERC20("Karsha", "KARSHA", 18)
        PanaAccessControlled(IPanaAuthority(_authority))
    {
        require(_sPana != address(0), "Zero address: sPANA");
        sPANA = IsPana(_sPana);
    }

    function setStaking(address _newStaking) external onlyGovernor {
        require(_newStaking != address(0), "Zero address found: Staking");
        staking = _newStaking;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
        @notice mint KARSHA
        @param _to address
        @param _amount uint
     */
    function mint(address _to, uint256 _amount) external override onlyStaking {
        _mint(_to, _amount);
    }

    /**
        @notice burn KARSHA
        @param _from address
        @param _amount uint
     */
    function burn(address _from, uint256 _amount) external override onlyStaking {
        require(balanceOf(_from) >= _amount, "ERC20: burn amount exceeds balance");
        _burn(_from, _amount);
    }

    /**
        @notice transfer KARSHA
        @param _to address
        @param _amount uint
     */
    function transfer(address _to, uint256 _amount) public override(IKarsha,ERC20) returns (bool){
        require(balanceOf(msg.sender) >= _amount, "ERC20: transfer amount exceeds balance");                 
        return super.transfer(_to,_amount);
    }

    /**
        @notice transferFrom KARSHA
        @param sender address
        @param recipient address
        @param amount uint
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override(IKarsha,ERC20) returns (bool) {
        require(balanceOf(sender) >= amount, "ERC20: transfer amount exceeds balance");  
        return super.transferFrom(sender,recipient,amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice pull index from sPANA token
     */
    function index() public view override returns (uint256) {
        return sPANA.index();
    }

    /**
        @notice converts KARSHA balance to PANA
        @param _address address
        @return uint
     */
    function balanceOfPANA(address _address) public view override returns (uint256) {
        return balanceFrom(balanceOf(_address));
    }

    /**
        @notice converts KARSHA amount to PANA
        @param _amount uint
        @return uint
     */
    function balanceFrom(uint256 _amount) public view override returns (uint256) {
        return _amount.mul(index()).div(10**decimals());
    }

    /**
        @notice converts PANA amount to KARSHA
        @param _amount uint
        @return uint
     */
    function balanceTo(uint256 _amount) public view override returns (uint256) {
        return _amount.mul(10**decimals()).div(index());
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "KARSHA::getPriorVotes: not yet determined");

        uint256 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = _balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint256 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint256 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint256 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == block.number) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(block.number, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    /**
        @notice Ensure delegation moves when token is transferred.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        _moveDelegates(delegates[from], delegates[to], amount);
    }
}

