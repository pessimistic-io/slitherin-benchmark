pragma solidity 0.8.16;

import "./ITokenBooster.sol";
import "./IBaseV1Voter.sol";
import "./IBaseV1Minter.sol";

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract MonolithVoter is Initializable, OwnableUpgradeable {
    uint256 public tokenID;

    IBaseV1Voter public solidlyVoter;
    IBaseV1Minter public solidlyMinter;
    uint256 public solidlyMinterActivePeriod;

    ITokenBooster public tokenBooster;
    address public poolSetter;
    address public veDepositor;

    uint256 public constant WEEK = 1 weeks;
    uint256 public startTime;

    // the maximum number of pools to submit a vote for
    // must be low enough that `submitVotes` can submit the vote
    // data without the call reaching the block gas limit
    uint256 public constant MAX_SUBMITTED_VOTES = 50;

    // beyond the top `MAX_SUBMITTED_VOTES` pools, we also record several
    // more highest-voted pools. this mitigates against inaccuracies
    // in the lower end of the vote weights that can be caused by negative voting.
    uint256 public constant MAX_VOTES_WITH_BUFFER = MAX_SUBMITTED_VOTES + 10;

    // token -> week -> weight allocated
    mapping(address => mapping(uint256 => int256)) public poolVotes;
    // user -> week -> weight used
    mapping(address => mapping(uint256 => uint256)) public userVotes;

    // user -> week -> Votes
    mapping(address => mapping(uint256 => Vote[])) public userPoolVotes;

    address[2] public fixedVotePools;

    // [uint24 id][int40 poolVotes]
    // handled as an array of uint64 to allow memory-to-storage copy
    mapping(uint256 => uint64[MAX_VOTES_WITH_BUFFER]) public topVotes;

    address[] public poolAddresses;
    mapping(address => PoolData) public poolData;

    uint256 public lastWeek; // week of the last received vote (+1)
    uint256 public topVotesLength; // actual number of items stored in `topVotes`
    uint256 public minTopVote; // smallest vote-weight for pools included in `topVotes`
    uint256 public minTopVoteIndex; // `topVotes` index where the smallest vote is stored (+1)

    struct ProtectionData {
        address[2] pools;
        uint40 lastUpdate;
    }
    struct Vote {
        address pool;
        int256 weight;
    }
    struct PoolData {
        uint24 addressIndex;
        uint16 currentWeek;
        uint8 topVotesIndex;
    }

    event VotedForPoolIncentives(
        address indexed voter,
        address[] pools,
        int256[] voteWeights,
        uint256 usedWeight,
        uint256 totalWeight
    );
    event PoolProtectionSet(
        address address1,
        address address2,
        uint40 lastUpdate
    );
    event SubmittedVote(address caller, address[] pools, int256[] weights);

    function initialize(IBaseV1Voter _voter, IBaseV1Minter _minter)
        public
        initializer
    {
        __Ownable_init();

        solidlyVoter = _voter;
        solidlyMinter = _minter;
        solidlyMinterActivePeriod = solidlyMinter.active_period();

        // position 0 is empty so that an ID of 0 can be interpreted as unset
        poolAddresses.push(address(0));
    }

    function setAddresses(
        ITokenBooster _tokenLocker,
        address _poolSetter,
        address _veDepositor,
        address[2] calldata _fixedVotePools
    ) external onlyOwner {
        tokenBooster = _tokenLocker;
        poolSetter = _poolSetter;
        veDepositor = _veDepositor;
        startTime = _tokenLocker.startTime();

        // hardcoded pools always receive 5% of the vote
        // and cannot receive negative vote weights
        fixedVotePools = _fixedVotePools;
    }

    function setTokenID(uint256 _tokenID) external returns (bool) {
        require(msg.sender == veDepositor);
        tokenID = _tokenID;
        return true;
    }

    function getWeek() public view returns (uint256) {
        if (startTime == 0) return 0;
        return (block.timestamp - startTime) / 604800;
    }

    /**
        @notice The current pools and weights that would be submitted
                when calling `submitVotes`
     */
    function getCurrentVotes() external view returns (Vote[] memory votes) {
        (address[] memory pools, int256[] memory weights) = _currentVotes();
        votes = new Vote[](pools.length);
        for (uint256 i = 0; i < votes.length; i++) {
            votes[i] = Vote({pool: pools[i], weight: weights[i]});
        }
        return votes;
    }

    function getCurrentUserVotes(address _user)
        external
        view
        returns (Vote[] memory votes)
    {
        return userPoolVotes[_user][getWeek()];
    }

    /**
        @notice Get an account's unused vote weight for for the current week
        @param _user Address to query
        @return uint Amount of unused weight
     */
    function availableVotes(address _user) external view returns (uint256) {
        uint256 week = getWeek();
        uint256 usedWeight = userVotes[_user][week];
        uint256 totalWeight = tokenBooster.userWeight(_user) / 1e18;
        return totalWeight - usedWeight;
    }

    function _updateUserPoolVotes(
        address[] memory _pools,
        int256[] memory _weights
    ) internal {
        for (uint256 i = 0; i < _pools.length; i++) {
            userPoolVotes[msg.sender][getWeek()].push(
                Vote({pool: _pools[i], weight: _weights[i]})
            );
        }
    }

    function clearVotes() external {
        Vote[] memory votes = userPoolVotes[msg.sender][getWeek()];
        address[] memory pools = new address[](votes.length);
        int256[] memory weights = new int256[](votes.length);

        for (uint256 i = 0; i < votes.length; i++) {
            pools[i] = votes[i].pool;
            weights[i] = -votes[i].weight;
        }

        voteForPools(pools, weights);

        delete userPoolVotes[msg.sender][getWeek()];
    }

    /**
        @notice Vote for one or more pools
        @dev Vote-weights received via this function are aggregated but not sent to Solidly.
             To submit the vote to solidly you must call `submitVotes`.
             Voting does not carry over between weeks, votes must be resubmitted.
        @param _pools Array of pool addresses to vote for
        @param _weights Array of vote weights. Votes can be negative, the total weight calculated
                        from absolute values.
     */
    function voteForPools(address[] memory _pools, int256[] memory _weights)
        public
    {
        require(
            _pools.length == _weights.length,
            "_pools.length != _weights.length"
        );
        require(_pools.length > 0, "Must vote for at least one pool");

        _updateUserPoolVotes(_pools, _weights);

        uint256 week = getWeek();
        uint256 totalUserWeight = userVotes[msg.sender][week];

        // copy these values into memory to avoid repeated SLOAD / SSTORE ops
        uint256 _topVotesLengthMem = topVotesLength;
        uint256 _minTopVoteMem = minTopVote;
        uint256 _minTopVoteIndexMem = minTopVoteIndex;
        uint64[MAX_VOTES_WITH_BUFFER] memory t = topVotes[week];

        if (week + 1 > lastWeek) {
            _topVotesLengthMem = 0;
            _minTopVoteMem = 0;
            lastWeek = week + 1;
        }
        for (uint256 x = 0; x < _pools.length; x++) {
            address _pool = _pools[x];
            int256 _weight = _weights[x];

            // so user can take his votes back by negative weight
            totalUserWeight = uint256(int256(totalUserWeight) + _weight);

            require(_weight != 0, "Cannot vote zero");

            // update accounting for this week's votes
            int256 poolWeight = poolVotes[_pool][week];
            uint256 id = poolData[_pool].addressIndex;
            if (poolWeight == 0 || poolData[_pool].currentWeek <= week) {
                require(
                    solidlyVoter.gauges(_pool) != address(0),
                    "Pool has no gauge"
                );
                if (id == 0) {
                    id = poolAddresses.length;
                    poolAddresses.push(_pool);
                }
                poolData[_pool] = PoolData({
                    addressIndex: uint24(id),
                    currentWeek: uint16(week + 1),
                    topVotesIndex: 0
                });
            }

            int256 newPoolWeight = poolWeight + _weight;
            require(newPoolWeight >= 0, "Pool weight cannot be negative");

            uint256 absNewPoolWeight = abs(newPoolWeight);
            assert(absNewPoolWeight < 2**39); // this should never be possible

            poolVotes[_pool][week] = newPoolWeight;

            if (poolData[_pool].topVotesIndex > 0) {
                // pool already exists within the list
                uint256 voteIndex = poolData[_pool].topVotesIndex - 1;

                if (newPoolWeight == 0) {
                    // pool has a new vote-weight of 0 and so is being removed
                    poolData[_pool] = PoolData({
                        addressIndex: uint24(id),
                        currentWeek: 0,
                        topVotesIndex: 0
                    });
                    _topVotesLengthMem -= 1;
                    if (voteIndex == _topVotesLengthMem) {
                        delete t[voteIndex];
                    } else {
                        t[voteIndex] = t[_topVotesLengthMem];
                        uint256 addressIndex = t[voteIndex] >> 40;
                        poolData[poolAddresses[addressIndex]]
                            .topVotesIndex = uint8(voteIndex + 1);
                        delete t[_topVotesLengthMem];
                        if (_minTopVoteIndexMem > _topVotesLengthMem) {
                            // the value we just shifted was the minimum weight
                            _minTopVoteIndexMem = voteIndex + 1;
                            // continue here to avoid iterating to locate the new min index
                            continue;
                        }
                    }
                } else {
                    // modify existing record for this pool within `topVotes`
                    t[voteIndex] = pack(id, newPoolWeight);
                    if (absNewPoolWeight < _minTopVoteMem) {
                        // if new weight is also the new minimum weight
                        _minTopVoteMem = absNewPoolWeight;
                        _minTopVoteIndexMem = voteIndex + 1;
                        // continue here to avoid iterating to locate the new min voteIndex
                        continue;
                    }
                }
                if (voteIndex == _minTopVoteIndexMem - 1) {
                    // iterate to find the new minimum weight
                    (_minTopVoteMem, _minTopVoteIndexMem) = _findMinTopVote(
                        t,
                        _topVotesLengthMem
                    );
                }
            } else if (_topVotesLengthMem < MAX_VOTES_WITH_BUFFER) {
                // pool is not in `topVotes`, and `topVotes` contains less than
                // MAX_VOTES_WITH_BUFFER items, append
                t[_topVotesLengthMem] = pack(id, newPoolWeight);
                _topVotesLengthMem += 1;
                poolData[_pool].topVotesIndex = uint8(_topVotesLengthMem);
                if (absNewPoolWeight < _minTopVoteMem || _minTopVoteMem == 0) {
                    // new weight is the new minimum weight
                    _minTopVoteMem = absNewPoolWeight;
                    _minTopVoteIndexMem = poolData[_pool].topVotesIndex;
                }
            } else if (absNewPoolWeight > _minTopVoteMem) {
                // `topVotes` contains MAX_VOTES_WITH_BUFFER items,
                // pool is not in the array, and weight exceeds current minimum weight

                // replace the pool at the current minimum weight index
                uint256 addressIndex = t[_minTopVoteIndexMem - 1] >> 40;
                poolData[poolAddresses[addressIndex]] = PoolData({
                    addressIndex: uint24(addressIndex),
                    currentWeek: 0,
                    topVotesIndex: 0
                });
                t[_minTopVoteIndexMem - 1] = pack(id, newPoolWeight);
                poolData[_pool].topVotesIndex = uint8(_minTopVoteIndexMem);

                // iterate to find the new minimum weight
                (_minTopVoteMem, _minTopVoteIndexMem) = _findMinTopVote(
                    t,
                    MAX_VOTES_WITH_BUFFER
                );
            }
        }

        // make sure user has not exceeded available weight
        uint256 totalWeight = tokenBooster.userWeight(msg.sender) / 1e18;
        require(totalUserWeight <= totalWeight, "Available votes exceeded");

        // write memory vars back to storage
        topVotes[week] = t;
        topVotesLength = _topVotesLengthMem;
        minTopVote = _minTopVoteMem;
        minTopVoteIndex = _minTopVoteIndexMem;
        userVotes[msg.sender][week] = totalUserWeight;

        emit VotedForPoolIncentives(
            msg.sender,
            _pools,
            _weights,
            totalUserWeight,
            totalWeight
        );
    }

    /**
        @notice Submit the current votes to Solidly
        @dev This function is unguarded and so votes may be submitted at any time.
             Solidly has no restriction on the frequency that an account may vote,
             however emissions are only calculated from the active votes at the
             beginning of each epoch week.
     */
    function submitVotes() external returns (bool) {
        (address[] memory pools, int256[] memory weights) = _currentVotes();
        solidlyVoter.vote(tokenID, pools, weights);
        emit SubmittedVote(msg.sender, pools, weights);
        return true;
    }

    function _currentVotes()
        internal
        view
        returns (address[] memory pools, int256[] memory weights)
    {
        uint256 week = getWeek();
        uint256 length = 2; // length is always +2 to ensure room for the hardcoded gauges
        if (
            week + 1 == lastWeek &&
            solidlyMinter.active_period() > solidlyMinterActivePeriod
        ) {
            // `lastWeek` only updates on a call to `voteForPool`
            // if the current week is > `lastWeek`, there have not been any votes this week
            length += topVotesLength;
        }

        uint256[MAX_VOTES_WITH_BUFFER] memory absWeights;
        pools = new address[](length);
        weights = new int256[](length);

        // unpack `topVotes`
        for (uint256 i = 0; i < length - 2; i++) {
            (uint256 id, int256 weight) = unpack(topVotes[week][i]);
            pools[i] = poolAddresses[id];
            weights[i] = weight;
            absWeights[i] = abs(weight);
        }

        // if more than `MAX_SUBMITTED_VOTES` pools have votes, discard the lowest weights
        if (length > MAX_SUBMITTED_VOTES + 2) {
            while (length > MAX_SUBMITTED_VOTES + 2) {
                uint256 minValue = type(uint256).max;
                uint256 minIndex = 0;
                for (uint256 i = 0; i < length - 2; i++) {
                    uint256 weight = absWeights[i];
                    if (weight < minValue) {
                        minValue = weight;
                        minIndex = i;
                    }
                }
                uint256 idx = length - 3;
                weights[minIndex] = weights[idx];
                pools[minIndex] = pools[idx];
                absWeights[minIndex] = absWeights[idx];
                delete weights[idx];
                delete pools[idx];
                length -= 1;
            }
            assembly {
                mstore(pools, length)
                mstore(weights, length)
            }
        }

        // calculate absolute total weight and find the indexes for the hardcoded pools
        uint256 totalWeight;
        uint256[2] memory fixedVoteIds;
        address[2] memory _fixedVotePools = fixedVotePools;
        for (uint256 i = 0; i < length - 2; i++) {
            totalWeight += absWeights[i];
            if (pools[i] == _fixedVotePools[0]) fixedVoteIds[0] = i + 1;
            else if (pools[i] == _fixedVotePools[1]) fixedVoteIds[1] = i + 1;
        }

        // add 5% hardcoded vote
        int256 fixedWeight = int256((totalWeight * 11) / 200);
        if (fixedWeight == 0) fixedWeight = 1;
        length -= 2;
        for (uint256 i = 0; i < 2; i++) {
            if (fixedVoteIds[i] == 0) {
                pools[length + i] = _fixedVotePools[i];
                weights[length + i] = fixedWeight;
            } else {
                weights[fixedVoteIds[i] - 1] += fixedWeight;
            }
        }

        return (pools, weights);
    }

    function _findMinTopVote(
        uint64[MAX_VOTES_WITH_BUFFER] memory t,
        uint256 length
    ) internal pure returns (uint256, uint256) {
        uint256 _minTopVoteMem = type(uint256).max;
        uint256 _minTopVoteIndexMem;
        for (uint256 i = 0; i < length; i++) {
            uint256 value = t[i] % 2**39;
            if (value < _minTopVoteMem) {
                _minTopVoteMem = value;
                _minTopVoteIndexMem = i + 1;
            }
        }
        return (_minTopVoteMem, _minTopVoteIndexMem);
    }

    function abs(int256 value) internal pure returns (uint256) {
        return uint256(value > 0 ? value : -value);
    }

    function pack(uint256 id, int256 weight) internal pure returns (uint64) {
        // tightly pack as [uint24 id][int40 weight] for storage in `topVotes`
        uint64 value = uint64((id << 40) + abs(weight));
        if (weight < 0) value += 2**39;
        return value;
    }

    function unpack(uint256 value)
        internal
        pure
        returns (uint256 id, int256 weight)
    {
        // unpack a value in `topVotes`
        id = (value >> 40);
        weight = int256(value % 2**40);
        if (weight > 2**39) weight = -(weight % 2**39);
        return (id, weight);
    }
}

