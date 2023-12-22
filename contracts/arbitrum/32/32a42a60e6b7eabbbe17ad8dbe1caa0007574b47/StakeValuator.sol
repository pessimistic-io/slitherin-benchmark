// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import { OnlyWhitelisted } from "./OnlyWhitelisted.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeMath } from "./SafeMath.sol";
import { Math } from "./Math.sol";
import { Interpolating } from "./Interpolating.sol";
import { PriceOracle, IOracle } from "./IStakeValuator.sol";
import { UserStake } from "./IMultiStaking.sol";
import { IStakingPerRewardController } from "./IStakingPerRewardController.sol";
import { IStakingPerTierController } from "./IStakingPerTierController.sol";
import { ISnapshottable } from "./ISnapshottable.sol";
//import { SafeERC20 } from '../libraries/SafeERC20.sol';
import { SafeERC20 } from "./SafeERC20.sol";
//import { MultiStakingPassthrough } from './MultiStakingPassthrough.sol';
import { IStakingPerStakeValuator } from "./IStakingPerStakeValuator.sol";


//contract StakeValuator is Interpolating, IMultiStaking, MultiStakingPassthrough {
contract StakeValuator is OnlyWhitelisted, IStakingPerRewardController, IStakingPerTierController {
    using SafeMath for uint256;

    IStakingPerStakeValuator public staking;

    // token => data
    mapping(IERC20 => PriceOracle) public priceOracle;
    // blockNumber => token => data
    mapping(uint256 => mapping(IERC20 => PriceOracle)) public priceOracleSnapshots;

    // the token used to value all other tokens
    IERC20 public baseToken;

    uint256[] public snapshotBlockNumbers;
    // blockNumber => user => amountBaseToken
    mapping(uint256 => mapping(address => uint256)) public snapshots;
    // blockNumber => bool
    mapping(uint256 => bool) public snapshotExists;
    // user => blockNumber
    mapping(address => uint256) public lastSnapshotBlockNumbers;

    uint8 public SNAPSHOTTER_TIER;
    uint8 public TIER_ORACLE_SETTER;

    event OracleSet(IERC20 indexed token, bool isOracle, IOracle oracle);
    event Snapshot(uint256 blockNumber);

    constructor(IERC20 _token, IStakingPerStakeValuator _staking) {
        require(address(_token) != address(0), "Token address cannot be 0x0");

        staking = _staking;

        // eliminate the possibility of a real snapshot at idx 0
        snapshotBlockNumbers.push(0);

        baseToken = _token;
        // baseToken has per definition a value of 1
        setOracle(_token, false, IOracle(address(uint160(10 ** IERC20Metadata(address(_token)).decimals()))));

        SNAPSHOTTER_TIER = consumeNextId();
        TIER_ORACLE_SETTER = consumeNextId();
    }


    ///////////////////////////////////////
    // Core functionality
    ///////////////////////////////////////

    /// @dev This is the key functionality of this contract, converting all other tokens to the base token, for further use by other contracts
    function getVestedTokens(address user) external view returns (uint256) {
        return calculateBaseValueAt(user, block.number);
    }
    /// @dev This is the key functionality of this contract, converting all other tokens to the base token, for further use by other contracts
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external view returns (uint256) {
        return calculateBaseValueAt(user, blockNumber);
    }

    function updateSnapshots(uint256 startIdx, uint256 endIdx) external {
        _updateSnapshots(startIdx, endIdx, msg.sender);
    }
    function _updateSnapshots(uint256 startIdx, uint256 endIdx, address account) internal {
        if (snapshotBlockNumbers.length == 0) {
            return; // early abort
        }

        require(endIdx > startIdx, "endIdx must be greater than startIdx");
        uint256 lastSnapshotBlockNumber = lastSnapshotBlockNumbers[account];
        uint256 lastBlockNumber = snapshotBlockNumbers[uint256(snapshotBlockNumbers.length).sub(1)];

        // iterate backwards through snapshots
        if (snapshotBlockNumbers.length < endIdx) {
            endIdx = uint256(snapshotBlockNumbers.length).sub(1);
        }
        // ensure snapshots aren't skipped
        require(startIdx == 0 || snapshotBlockNumbers[startIdx.sub(1)] <= lastSnapshotBlockNumber, "Can't skip snapshots");
        for (uint256 i = endIdx;  i > startIdx;  --i) {
            uint256 blockNumber = snapshotBlockNumbers[i];

            if (lastSnapshotBlockNumber >= blockNumber) {
                break; // done with user
            }

            // address => amount
            mapping(address => uint256) storage _snapshot = snapshots[blockNumber];

            // update the vested amount
            _snapshot[account] = calculateBaseValueAt(account, blockNumber);
        }

        // set user as updated
        lastSnapshotBlockNumbers[account] = lastBlockNumber;
    }
    function snapshot() external onlyWhitelistedTier(SNAPSHOTTER_TIER) {
        if (!snapshotExists[block.number]) {
            snapshotBlockNumbers.push(block.number);
            snapshotExists[block.number] = true;
            emit Snapshot(block.number);

            // because of the way external oracles work, we need to snapshot those external ones right now
            _updateOracleSnapshots();

            // pass the snapshot on
            staking.snapshot();
        }
    }

    function calculateBaseValueAt(address user, uint256 blockNumber) internal view returns (uint256 result) {
        IERC20[] memory _userTokens = staking.getUserTokens(user);
        for (uint256 i = 0;  i < _userTokens.length;  ++i) {
            result = result.add(calculateBaseValueAt(user, _userTokens[i], blockNumber));
        }
        return result;
    }
    function calculateBaseValueAt(address user, IERC20 _token, uint256 blockNumber) internal view returns (uint256 result) {
        return getValueAtSnapshotOf(
            _token, 
            staking.getVestedTokensAtSnapshot(user, _token, blockNumber), 
            blockNumber
        );
    }


    ///////////////////////////////////////
    // Housekeeping
    ///////////////////////////////////////

    function setOracle(IERC20[] memory _token, bool[] memory _isOracle, IOracle[] memory _oracle) public onlyWhitelistedTier(TIER_ORACLE_SETTER) {
        require(_token.length == _isOracle.length && _token.length == _oracle.length, "Array lengths must match");
        for (uint256 i = 0;  i < _token.length;  ++i) {
            setOracle(_token[i], _isOracle[i], _oracle[i]);
        }
    }
    function setOracle(IERC20 _token, bool _isOracle, IOracle _oracle) public onlyWhitelistedTier(TIER_ORACLE_SETTER) {
        _updateOracleSnapshots(_token);

        // update the current oracle
        priceOracle[_token] = PriceOracle(true, _isOracle, _oracle);
        emit OracleSet(_token, _isOracle, _oracle);
    }
    function _updateOracleSnapshots() internal {
        uint256 len = uint256(staking.tokensLength());
        for (uint256 i = 0;  i < len;  ++i) {
            IERC20 _token = staking.tokens(i);
            if (priceOracle[_token].isOracle) {
                // TODO test the oracle snapshots too
                _updateOracleSnapshots(_token);
            }
        }
    }
    function _updateOracleSnapshots(IERC20 _token) internal {
        // iterate backwards through snapshots
        uint256 endIdx = uint256(snapshotBlockNumbers.length).sub(1);
        for (uint256 i = endIdx;  i > 0;  --i) {
            uint256 blockNumber = snapshotBlockNumbers[i];

            if (priceOracleSnapshots[blockNumber][_token].exists) {
                break; // we've reached the end of the snapshots that need to be updated
            }

            PriceOracle memory oracle = priceOracle[_token];
            oracle.exists = true; // in case it's a default, we mark it so we won't re-set this one later
            if (oracle.isOracle) {
                // get and store the value, converting this to a fixed value
                (uint256 price, uint256 lastUpdated) = oracle.oracle.getPrice(_token);
                oracle.oracle = IOracle(address(uint160(price)));
                oracle.isOracle = false;
            }
            priceOracleSnapshots[blockNumber][_token] = oracle;
        }
    }


    ///////////////////////////////////////
    // View functions
    ///////////////////////////////////////

    function getValueFromOracle(PriceOracle memory _priceOracle, IERC20 _token) public view returns (uint256) {
        uint256 price = uint256(uint160(address(_priceOracle.oracle)));
        if (_priceOracle.isOracle) {
            // this shouldn't happen since we've converted it to a stored value at snapshot, but just in case..
            uint256 lastUpdated;
            (price, lastUpdated) = _priceOracle.oracle.getPrice(_token);
            // we intentionally don't care about lastUpdated to prevent vesting breaking completely if there's an oracle hiccup
        }
        return price;
    }
    function getValueAtSnapshot(IERC20 _token, uint256 _blockNumber) public view returns (uint256) {
        PriceOracle memory _priceOracle = priceOracleSnapshots[_blockNumber][_token];
        if (!snapshotExists[_blockNumber] || !_priceOracle.exists) {
            // no snapshot, just return the current value
            return getValue(_token);
        }

        // use the snapshot
        return getValueFromOracle(_priceOracle, _token);
    }
    function getValue(IERC20 _token) public view returns (uint256) {
        return getValueFromOracle(priceOracle[_token], _token);
    }
    function getValueOf(IERC20 _token, uint256 _amount) public view returns (uint256) {
        return getValue(_token).mul(_amount).div(10 ** IERC20Metadata(address(_token)).decimals());
    }
    function getValueAtSnapshotOf(IERC20 _token, uint256 _amount, uint256 _blockNumber) public view returns (uint256) {
        return getValueAtSnapshot(_token, _blockNumber).mul(_amount).div(10 ** IERC20Metadata(address(_token)).decimals());
    }


    ///////////////////////////////////////
    // Passthrough functions
    //  To fulfill interfaces of other contracts
    ///////////////////////////////////////

    function getStakers(uint256 idx) external view returns (address) {
        return staking.getStakers(idx);
    }
    function getStakersCount() external view returns (uint256) {
        return staking.getStakersCount();
    }
    function stakeFor(address _account, uint256 _amount) external {
        // collect the tokens
        uint256 allowance = baseToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Check the token allowance");
        SafeERC20.safeTransferFrom(baseToken, msg.sender, address(this), _amount);

        // stake the tokens onward
        baseToken.approve(address(staking), _amount);
        staking.stakeFor(_account, _amount);
    }
    function token() external view returns (IERC20) {
        return staking.token();
    }
}
