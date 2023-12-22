// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20.sol";
import "./VeERC20Upgradeable.sol";
import "./Whitelist.sol";
import "./Math.sol";
import "./SafeOwnableUpgradeable.sol";
import "./IMasterRelay.sol";
import "./IVeRelay.sol";
import "./IRelayNFT.sol";

interface IVe {
    function vote(address _user, int256 _voteDelta) external;
}

contract VeRelay is
    Initializable,
    SafeOwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VeERC20Upgradeable,
    IVeRelay,
    IVe
{
    // Staking user info
    struct UserInfo {
        uint256 amount; // relay staked by user
        uint256 lastRelease; // time of last veRelay claim or first deposit if user has not claimed yet
        // the id of the currently staked nft
        // important note: the id is offset by +1 to handle tokenID = 0
        // stakedNftId = 0 (default value) means that no NFT is staked
        uint256 stakedNftId;
    }

    // Locking user info
    struct LockedPosition {
        uint128 initialLockTime;
        uint128 unlockTime;
        uint128 relayLocked;
        uint128 veRelayAmount;
    }

    /// @notice the relay token
    IERC20 public relay;

    /// @notice the masterRelay contract
    IMasterRelay public masterRelay;

    /// @notice the NFT contract
    IRelayNFT public nft;

    /// @notice max veRelay to staked relay ratio
    /// Note if user has 10 relay staked, they can only have a max of 10 * maxStakeCap veRelay in balance
    uint256 public maxStakeCap;

    /// @notice the rate of veRelay generated per second, per relay staked
    uint256 public generationRate;

    /// @notice invVvoteThreshold threshold.
    /// @notice voteThreshold is the tercentage of cap from which votes starts to count for governance proposals.
    /// @dev inverse of the threshold to apply.
    /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
    /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
    /// Formula is invVoteThreshold = (1 / th) * 100
    uint256 public invVoteThreshold;

    /// @notice whitelist wallet checker
    /// @dev contract addresses are by default unable to stake relay, they must be previously whitelisted to stake relay
    Whitelist public whitelist;

    /// @notice user info mapping
    // note Staking user info
    mapping(address => UserInfo) public users;

    uint256 public maxNftLevel;
    uint256 public xpEnableTime;

    // reserve more space for extensibility
    uint256[100] public xpRequiredForLevelUp;

    address public voter;

    /// @notice amount of vote used currently for each user
    mapping(address => uint256) public usedVote;
    /// @notice store the last block when a contract stake NFT
    mapping(address => uint256) internal lastBlockToStakeNftByContract;

    // Note used to prevent storage collision
    uint256[2] private __gap;

    /// @notice min and max lock days
    uint128 public minLockDays;
    uint128 public maxLockDays;

    /// @notice the max cap for locked positions
    uint256 public maxLockCap;

    /// @notice Locked RELAY user info
    mapping(address => LockedPosition) public lockedPositions;

    /// @notice total amount of relay locked
    uint256 public totalLockedRelay;

    /// @notice events describing staking, unstaking and claiming
    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);

    /// @notice events describing NFT staking and unstaking
    event StakedNft(address indexed user, uint256 indexed nftId);
    event UnstakedNft(address indexed user, uint256 indexed nftId);

    /// @notice events describing locking mechanics
    event Lock(address indexed user, uint256 unlockTime, uint256 amount, uint256 veRelayToMint);
    event ExtendLock(address indexed user, uint256 daysToExtend, uint256 unlockTime, uint256 veRelayToMint);
    event AddToLock(address indexed user, uint256 amountAdded, uint256 veRelayToMint);
    event Unlock(address indexed user, uint256 unlockTime, uint256 amount, uint256 veRelayToBurn);

    function initialize(
        IERC20 _relay,
        IMasterRelay _masterRelay,
        IRelayNFT _nft
    ) public initializer {
        // require(address(_masterRelay) != address(0), 'zero address');
        require(address(_relay) != address(0), 'zero address');
        // require(address(_nft) != address(0), 'zero address');

        // Initialize veRELAY
        __ERC20_init('veRelay', 'veRELAY');
        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        // set generationRate (veRelay per sec per relay staked)
        generationRate = 3888888888888;

        // set maxStakeCap
        maxStakeCap = 100;

        // set inv vote threshold
        // invVoteThreshold = 20 => th = 5
        invVoteThreshold = 20;

        // set master relay
        masterRelay = _masterRelay;

        // set relay
        relay = _relay;

        // set nft, can be zero address at first
        nft = _nft;

        initializeNft();
        initializeLockDays();
    }

    function _verifyVoteIsEnough(address _user) internal view {
        require(balanceOf(_user) >= usedVote[_user], 'VeRelay: not enough vote');
    }

    function _onlyVoter() internal view {
        require(msg.sender == voter, 'VeRelay: caller is not voter');
    }

    function initializeNft() public onlyOwner {
        maxNftLevel = 1; // to enable leveling, call setMaxNftLevel
        xpRequiredForLevelUp = [uint256(0), 3000 ether, 30000 ether, 300000 ether, 3000000 ether];
    }

    function initializeLockDays() public onlyOwner {
        minLockDays = 7; // 1 week
        maxLockDays = 357; // 357/(365/12) ~ 11.7 months
        maxLockCap = 120; // < 12 month max lock

        // ~18 month max stake, can set separately
        // maxStakeCap = 180;
    }

    /**
     * @dev pause pool, restricting certain operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, enabling certain operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice set min and max lock days
    function setLockDaysAndCap(
        uint256 _minLockDays,
        uint256 _maxLockDays,
        uint256 _maxLockCap
    ) external onlyOwner {
        require(_minLockDays < _maxLockDays && _maxLockDays < type(uint128).max, 'lock days are invalid');
        minLockDays = uint128(_minLockDays);
        maxLockDays = uint128(_maxLockDays);
        maxLockCap = _maxLockCap;
    }

    /// @notice sets masterRelay address
    /// @param _masterRelay the new masterRelay address
    function setMasterRelay(IMasterRelay _masterRelay) external onlyOwner {
        require(address(_masterRelay) != address(0), 'zero address');
        masterRelay = _masterRelay;
    }

    /// @notice sets NFT contract address
    /// @param _nft the new NFT contract address
    function setNftAddress(IRelayNFT _nft) external onlyOwner {
        require(address(_nft) != address(0), 'zero address');
        nft = _nft;
    }

    /// @notice sets voter contract address
    /// @param _voter the new NFT contract address
    function setVoter(address _voter) external onlyOwner {
        require(address(_voter) != address(0), 'zero address');
        voter = _voter;
    }

    /// @notice sets whitelist address
    /// @param _whitelist the new whitelist address
    function setWhitelist(Whitelist _whitelist) external onlyOwner {
        require(address(_whitelist) != address(0), 'zero address');
        whitelist = _whitelist;
    }

    /// @notice sets maxStakeCap
    /// @param _maxStakeCap the new max ratio
    function setMaxStakeCap(uint256 _maxStakeCap) external onlyOwner {
        require(_maxStakeCap != 0, 'max cap cannot be zero');
        maxStakeCap = _maxStakeCap;
    }

    /// @notice sets generation rate
    /// @param _generationRate the new max ratio
    function setGenerationRate(uint256 _generationRate) external onlyOwner {
        require(_generationRate != 0, 'generation rate cannot be zero');
        generationRate = _generationRate;
    }

    /// @notice sets invVoteThreshold
    /// @param _invVoteThreshold the new var
    /// Formula is invVoteThreshold = (1 / th) * 100
    function setInvVoteThreshold(uint256 _invVoteThreshold) external onlyOwner {
        require(_invVoteThreshold != 0, 'invVoteThreshold cannot be zero');
        invVoteThreshold = _invVoteThreshold;
    }

    /// @notice sets setMaxNftLevel, the first time this function is called, leveling will be enabled
    /// @param _maxNftLevel the new var
    function setMaxNftLevel(uint8 _maxNftLevel) external onlyOwner {
        maxNftLevel = _maxNftLevel;

        if (xpEnableTime == 0) {
            // enable users to accumulate timestamp the first time this function is invoked
            xpEnableTime = block.timestamp;
        }
    }

    /// @notice checks wether user _addr has relay staked
    /// @param _addr the user address to check
    /// @return true if the user has relay in stake, false otherwise
    function isUserStaking(address _addr) public view override returns (bool) {
        return users[_addr].amount > 0;
    }

    /// @notice [Deprecated] return the result of `isUserStaking()` for backward compatibility
    function isUser(address _addr) external view returns (bool) {
        return isUserStaking(_addr);
    }

    /// @notice [Deprecated] return the `maxStakeCap` for backward compatibility
    function maxCap() external view returns (uint256) {
        return maxStakeCap;
    }

    /// @notice returns staked amount of relay for user
    /// @param _addr the user address to check
    /// @return staked amount of relay
    function getStakedRelay(address _addr) external view override returns (uint256) {
        return users[_addr].amount;
    }

    /// @dev explicity override multiple inheritance
    function totalSupply() public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.totalSupply();
    }

    /// @dev explicity override multiple inheritance
    function balanceOf(address account) public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice returns expected veRELAY amount to be minted given amount and number of days to lock
    function _expectedVeRelayAmount(uint256 _amount, uint256 _lockSeconds) private view returns (uint256) {
        return Math.wmul(_amount, _lockSeconds * generationRate);
    }

    function quoteExpectedVeRelayAmount(uint256 _amount, uint256 _lockDays) external view returns (uint256) {
        return _expectedVeRelayAmount(_amount, _lockDays * 1 days);
    }

    /// @notice locks RELAY in the contract, immediately minting veRELAY
    /// @param _amount amount of RELAY to lock
    /// @param _lockDays number of days to lock the _amount of RELAY for
    /// @return veRelayToMint the amount of veRELAY minted by the lock
    function lockRelay(uint256 _amount, uint256 _lockDays)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 veRelayToMint)
    {
        require(_amount > 0, 'amount to lock cannot be zero');
        require(lockedPositions[msg.sender].relayLocked == 0, 'user already has a lock, call addRelayToLock');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        // validate lock days
        require(_lockDays >= uint256(minLockDays) && _lockDays <= uint256(maxLockDays), 'lock days is invalid');

        // calculate veRELAY to mint and unlock time
        veRelayToMint = _expectedVeRelayAmount(_amount, _lockDays * 1 days);
        uint256 unlockTime = block.timestamp + 1 days * _lockDays;

        // validate that cap is respected
        require(veRelayToMint <= _amount * maxLockCap, 'lock cap is not respected');

        // check type safety
        require(unlockTime < type(uint128).max, 'overflow');
        require(_amount < type(uint128).max, 'overflow');
        require(veRelayToMint < type(uint128).max, 'overflow');

        // Request Relay from user
        relay.transferFrom(msg.sender, address(this), _amount);

        lockedPositions[msg.sender] = LockedPosition(
            uint128(block.timestamp),
            uint128(unlockTime),
            uint128(_amount),
            uint128(veRelayToMint)
        );

        totalLockedRelay += _amount;

        _mint(msg.sender, veRelayToMint);

        emit Lock(msg.sender, unlockTime, _amount, veRelayToMint);

        return veRelayToMint;
    }

    /// @notice adds Relay to current lock
    /// @param _amount the amount of relay to add to lock
    /// @return veRelayToMint the amount of veRELAY generated by adding to the lock
    function addRelayToLock(uint256 _amount) external override nonReentrant whenNotPaused returns (uint256 veRelayToMint) {
        require(_amount > 0, 'amount to add to lock cannot be zero');
        LockedPosition memory position = lockedPositions[msg.sender];
        require(position.relayLocked > 0, 'user doesnt have a lock, call lockRelay');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        require(position.unlockTime > block.timestamp, 'cannot add to a finished lock, please extend lock');

        // timeLeftInLock > 0
        uint256 timeLeftInLock = position.unlockTime - block.timestamp;

        veRelayToMint = _expectedVeRelayAmount(_amount, timeLeftInLock);

        // validate that cap is respected
        require(
            veRelayToMint + position.veRelayAmount <= (_amount + position.relayLocked) * maxLockCap,
            'lock cap is not respected'
        );

        // check type safety
        require(_amount + position.relayLocked < type(uint128).max, 'overflow');
        require(position.veRelayAmount + veRelayToMint < type(uint128).max, 'overflow');

        // Request Relay from user
        relay.transferFrom(msg.sender, address(this), _amount);

        lockedPositions[msg.sender].relayLocked += uint128(_amount);
        lockedPositions[msg.sender].veRelayAmount += uint128(veRelayToMint);

        totalLockedRelay += _amount;

        _mint(msg.sender, veRelayToMint);
        emit AddToLock(msg.sender, _amount, veRelayToMint);

        return veRelayToMint;
    }

    /// @notice Extends curent lock by days. The total amount of veRELAY generated is caculated based on the period
    /// between `initialLockTime` and the new `unlockPeriod`
    /// @dev the lock extends the duration taking into account `unlockTime` as reference. If current position is already unlockable, it will extend the position taking into consideration the registered unlock time, and not the block's timestamp.
    /// @param _daysToExtend amount of additional days to lock the position
    /// @return veRelayToMint amount of veRELAY generated by extension
    function extendLock(uint256 _daysToExtend)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 veRelayToMint)
    {
        require(_daysToExtend >= uint256(minLockDays), 'extend: days are invalid');

        LockedPosition memory position = lockedPositions[msg.sender];

        require(position.relayLocked > 0, 'extend: no relay locked');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        uint256 newUnlockTime = position.unlockTime + _daysToExtend * 1 days;
        require(newUnlockTime - position.initialLockTime <= uint256(maxLockDays * 1 days), 'extend: too much days');

        // calculate amount of veRELAY to mint for the extended days
        // distributive property of `_expectedVeRelayAmount` is assumed
        veRelayToMint = _expectedVeRelayAmount(position.relayLocked, _daysToExtend * 1 days);

        uint256 _maxCap = maxLockCap;
        // max user veRelay balance in case the extension was about to exceed lock
        if (veRelayToMint + position.veRelayAmount > position.relayLocked * _maxCap) {
            // mint enough to max the position
            veRelayToMint = position.relayLocked * _maxCap - position.veRelayAmount;
        }

        // validate type safety
        require(newUnlockTime < type(uint128).max, 'overflow');
        require(veRelayToMint + position.veRelayAmount < type(uint128).max, 'overflow');

        // assign new unlock time and veRELAY amount
        lockedPositions[msg.sender].unlockTime = uint128(newUnlockTime);
        lockedPositions[msg.sender].veRelayAmount = position.veRelayAmount + uint128(veRelayToMint);

        _mint(msg.sender, veRelayToMint);

        emit ExtendLock(msg.sender, _daysToExtend, newUnlockTime, veRelayToMint);

        return veRelayToMint;
    }

    /// @notice unlocks all RELAY for a user
    //// Lock needs to expire before unlock
    /// @return the amount of RELAY recovered by the unlock
    function unlockRelay() external override nonReentrant whenNotPaused returns (uint256) {
        LockedPosition memory position = lockedPositions[msg.sender];
        require(position.relayLocked > 0, 'no relay locked');
        require(position.unlockTime <= block.timestamp, 'not yet');
        uint256 relayToUnlock = position.relayLocked;
        uint256 veRelayToBurn = position.veRelayAmount;

        // delete the lock position from mapping
        delete lockedPositions[msg.sender];

        totalLockedRelay -= relayToUnlock;

        // burn corresponding veRELAY
        _burn(msg.sender, veRelayToBurn);

        // transfer the relay to the user
        relay.transfer(msg.sender, relayToUnlock);

        emit Unlock(msg.sender, position.unlockTime, relayToUnlock, veRelayToBurn);

        return relayToUnlock;
    }

    /// @notice deposits RELAY into contract
    /// @param _amount the amount of relay to deposit
    function deposit(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        if (isUserStaking(msg.sender)) {
            // if user exists, first, claim his veRELAY
            _claim(msg.sender);
            // then, increment his holdings
            users[msg.sender].amount += _amount;
        } else {
            // add new user to mapping
            users[msg.sender].lastRelease = block.timestamp;
            users[msg.sender].amount = _amount;
        }

        // Request Relay from user
        // SafeERC20 is not needed as RELAY will revert if transfer fails
        relay.transferFrom(msg.sender, address(this), _amount);

        // emit event
        emit Staked(msg.sender, _amount);
    }

    /// @notice asserts addres in param is not a smart contract.
    /// @notice if it is a smart contract, check that it is whitelisted
    /// @param _addr the address to check
    function _assertNotContract(address _addr) private view {
        if (_addr != tx.origin) {
            require(
                address(whitelist) != address(0) && whitelist.check(_addr),
                'Smart contract depositors not allowed'
            );
        }
    }

    /// @notice claims accumulated veRELAY
    function claim() external override nonReentrant whenNotPaused {
        require(isUserStaking(msg.sender), 'user has no stake');
        _claim(msg.sender);
    }

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claim(address _addr) private {
        uint256 amount;
        uint256 xp;
        (amount, xp) = _claimable(_addr);

        UserInfo storage user = users[_addr];

        // update last release time
        user.lastRelease = block.timestamp;

        if (amount > 0) {
            emit Claimed(_addr, amount);
            _mint(_addr, amount);
        }

        if (xp > 0) {
            uint256 nftId = user.stakedNftId;

            // if nftId > 0, user has nft staked
            if (nftId > 0) {
                --nftId; // remove offset

                // level is already validated in _claimable()
                nft.growXp(nftId, xp);
            }
        }
    }

    /// @notice returns amount of veRELAY that has been generated by staking (including those from NFT)
    /// @param _addr the address to check
    function veRelayGeneratedByStake(address _addr) public view returns (uint256) {
        return balanceOf(_addr) - lockedPositions[_addr].veRelayAmount;
    }

    /// @notice returns amount of veRELAY that has been generated by staking
    /// @param _addr the address to check
    function veRelayGeneratedByLock(address _addr) public view returns (uint256) {
        return lockedPositions[_addr].veRelayAmount;
    }

    /// @notice Calculate the amount of veRELAY that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of veRELAY that can be claimed by user
    function claimable(address _addr) external view returns (uint256 amount) {
        require(_addr != address(0), 'zero address');
        (amount, ) = _claimable(_addr);
    }

    /// @notice Calculate the amount of veRELAY that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of veRELAY that can be claimed by user
    /// @return xp potential xp for NFT staked
    function claimableWithXp(address _addr) external view returns (uint256 amount, uint256 xp) {
        require(_addr != address(0), 'zero address');
        return _claimable(_addr);
    }

    /// @notice Calculate the amount of veRELAY that can be claimed by user
    /// @dev private claimable function
    /// @param _addr the address to check
    /// @return amount of veRELAY that can be claimed by user
    /// @return xp potential xp for NFT staked
    function _claimable(address _addr) private view returns (uint256 amount, uint256 xp) {
        UserInfo storage user = users[_addr];

        // get seconds elapsed since last claim
        uint256 secondsElapsed = block.timestamp - user.lastRelease;

        // calculate pending amount
        // Math.mwmul used to multiply wad numbers
        uint256 pending = Math.wmul(user.amount, secondsElapsed * generationRate);

        // get user's veRELAY balance
        uint256 userVeRelayBalance = veRelayGeneratedByStake(_addr);

        // user veRELAY balance cannot go above user.amount * maxStakeCap
        uint256 maxVeRelayCap = user.amount * maxStakeCap;

        // handle nft effects
        uint256 nftId = user.stakedNftId;
        // if nftId > 0, user has nft staked
        if (nftId > 0) {
            --nftId; // remove offset
            uint32 speedo;
            uint32 pudgy;
            uint32 diligent;
            uint32 gifted;
            (speedo, pudgy, diligent, gifted, ) = nft.getRelayDetails(nftId);

            if (speedo > 0) {
                // Speedo: x% faster veRELAY generation
                pending = (pending * (100 + speedo)) / 100;
            }
            if (diligent > 0) {
                // Diligent: +D veRELAY every hour (subject to cap)
                pending += ((uint256(diligent) * (10**decimals())) * secondsElapsed) / 1 hours;
            }
            if (pudgy > 0) {
                // Pudgy: x% higher veRELAY cap
                maxVeRelayCap = (maxVeRelayCap * (100 + pudgy)) / 100;
            }
            if (gifted > 0) {
                // Gifted: +D veRELAY regardless of RELAY staked
                // The cap should also increase D
                maxVeRelayCap += uint256(gifted) * (10**decimals());
            }

            uint256 level = nft.getRelayLevel(nftId);
            if (level < maxNftLevel) {
                // Accumulate XP only after leveling is enabled
                if (user.lastRelease >= xpEnableTime) {
                    xp = pending;
                } else {
                    xp = (pending * (block.timestamp - xpEnableTime)) / (block.timestamp - user.lastRelease);
                }
                uint256 currentXp = nft.getRelayXp(nftId);

                if (xp + currentXp > xpRequiredForLevelUp[level]) {
                    xp = xpRequiredForLevelUp[level] - currentXp;
                }
            }
        }

        // first, check that user hasn't reached the max limit yet
        if (userVeRelayBalance < maxVeRelayCap) {
            // amount of veRELAY to reach max cap
            uint256 amountToCap = maxVeRelayCap - userVeRelayBalance;

            // then, check if pending amount will make user balance overpass maximum amount
            if (pending >= amountToCap) {
                amount = amountToCap;
            } else {
                amount = pending;
            }
        } else {
            amount = 0;
        }
        // Note: maxVeRelayCap doesn't affect growing XP
    }

    /// @notice withdraws staked relay
    /// @param _amount the amount of relay to unstake
    /// Note Beware! you will loose all of your veRELAY minted from staking if you unstake any amount of relay!
    /// Besides, if you withdraw all RELAY and you have staked NFT, it will be unstaked
    function withdraw(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to withdraw cannot be zero');
        require(users[msg.sender].amount >= _amount, 'not enough balance');

        uint256 nftId = users[msg.sender].stakedNftId;
        if (nftId > 0) {
            // claim to grow XP
            _claim(msg.sender);
        } else {
            users[msg.sender].lastRelease = block.timestamp;
        }

        // get user veRELAY balance that must be burned before updating his balance
        uint256 valueToBurn = _veRelayBurnedOnWithdraw(msg.sender, _amount);

        // update his balance before burning or sending back relay
        users[msg.sender].amount -= _amount;

        _burn(msg.sender, valueToBurn);

        // unstake NFT if all RELAY is unstaked
        if (users[msg.sender].amount == 0 && users[msg.sender].stakedNftId != 0) {
            _unstakeNft(msg.sender);
        }

        // send back the staked relay
        // SafeERC20 is not needed as RELAY will revert if transfer fails
        relay.transfer(msg.sender, _amount);

        // emit event
        emit Unstaked(msg.sender, _amount);
    }

    /// Calculate the amount of veRELAY that will be burned when RELAY is withdrawn
    /// @param _amount the amount of relay to unstake
    /// @return the amount of veRELAY that will be burned
    function veRelayBurnedOnWithdraw(address _addr, uint256 _amount) external view returns (uint256) {
        return _veRelayBurnedOnWithdraw(_addr, _amount);
    }

    /// Private function to calculate the amount of veRELAY that will be burned when RELAY is withdrawn
    /// Does NOT burn amount generated by locking upon withdrawal of staked RELAY.
    /// @param _amount the amount of relay to unstake
    /// @return the amount of veRELAY that will be burned
    function _veRelayBurnedOnWithdraw(address _addr, uint256 _amount) private view returns (uint256) {
        require(_amount <= users[_addr].amount, 'not enough relay');
        uint256 veRelayBalance = veRelayGeneratedByStake(_addr);
        uint256 nftId = users[_addr].stakedNftId;

        if (nftId == 0) {
            // user doesn't have nft staked
            return veRelayBalance;
        } else {
            --nftId; // remove offset
            (, , , uint32 gifted, uint32 hibernate) = nft.getRelayDetails(nftId);

            if (gifted > 0) {
                // Gifted: don't burn veRelay given by Gifted
                veRelayBalance -= uint256(gifted) * (10**decimals());
            }

            // retain some veRELAY using nft
            // if it is a smart contract, check lastBlockToStakeNftByContract is not the current block
            // in case of flash loan attack
            if (
                hibernate > 0 && (msg.sender == tx.origin || lastBlockToStakeNftByContract[msg.sender] != block.number)
            ) {
                // Hibernate: Retain x% veRELAY of cap upon unstaking
                return
                    veRelayBalance -
                    (veRelayBalance * hibernate * (users[_addr].amount - _amount)) /
                    users[_addr].amount /
                    100;
            } else {
                return veRelayBalance;
            }
        }
    }

    /// @notice hook called after token operation mint/burn
    /// @dev updates masterRelay
    /// @param _account the account being affected
    /// @param _newBalance the newVeRelayBalance of the user
    function _afterTokenOperation(address _account, uint256 _newBalance) internal override {
        _verifyVoteIsEnough(_account);
        if(address(masterRelay) != address(0)){
            masterRelay.updateFactor(_account, _newBalance);
        }
    }

    /// @notice This function is called when users stake NFTs
    function stakeNft(uint256 _tokenId) external override nonReentrant whenNotPaused {
        require(isUserStaking(msg.sender), 'user has no stake');

        nft.transferFrom(msg.sender, address(this), _tokenId);

        // first, claim his veRELAY
        _claim(msg.sender);

        // user has previously staked some NFT, try to unstake it
        if (users[msg.sender].stakedNftId != 0) {
            _unstakeNft(msg.sender);
        }

        users[msg.sender].stakedNftId = _tokenId + 1; // add offset

        if (msg.sender != tx.origin) {
            lastBlockToStakeNftByContract[msg.sender] = block.number;
        }

        _afterNftStake(msg.sender, _tokenId);
        emit StakedNft(msg.sender, _tokenId);
    }

    function _afterNftStake(address _addr, uint256 nftId) private {
        uint32 gifted;
        (, , , gifted, ) = nft.getRelayDetails(nftId);
        // mint veRELAY using nft
        if (gifted > 0) {
            // Gifted: +D veRELAY regardless of RELAY staked
            _mint(_addr, uint256(gifted) * (10**decimals()));
        }
    }

    /// @notice unstakes current user nft
    function unstakeNft() external override nonReentrant whenNotPaused {
        // first, claim his veRELAY
        // one should always has deposited if he has staked NFT
        _claim(msg.sender);

        _unstakeNft(msg.sender);
    }

    /// @notice private function used to unstake nft
    /// @param _addr the address of the nft owner
    function _unstakeNft(address _addr) private {
        uint256 nftId = users[_addr].stakedNftId;
        require(nftId > 0, 'No NFT is staked');
        --nftId; // remove offset

        nft.transferFrom(address(this), _addr, nftId);

        users[_addr].stakedNftId = 0;

        _afterNftUnstake(_addr, nftId);
        emit UnstakedNft(_addr, nftId);
    }

    function _afterNftUnstake(address _addr, uint256 nftId) private {
        uint32 gifted;
        (, , , gifted, ) = nft.getRelayDetails(nftId);
        // burn veRELAY minted by nft
        if (gifted > 0) {
            // Gifted: +D veRELAY regardless of RELAY staked
            _burn(_addr, uint256(gifted) * (10**decimals()));
        }
    }

    /// @notice gets id of the staked nft
    /// @param _addr the addres of the nft staker
    /// @return id of the staked nft by _addr user
    /// if the user haven't stake any nft, tx reverts
    function getStakedNft(address _addr) external view returns (uint256) {
        uint256 nftId = users[_addr].stakedNftId;
        require(nftId > 0, 'not staking NFT');
        return nftId - 1; // remove offset
    }

    /// @notice level up the staked NFT
    /// @param relayToBurn token IDs of relayes to burn
    function levelUp(uint256[] calldata relayToBurn) external override nonReentrant whenNotPaused {
        uint256 nftId = users[msg.sender].stakedNftId;
        require(nftId > 0, 'not staking NFT');
        --nftId; // remove offset

        uint16 level = nft.getRelayLevel(nftId);
        require(level < maxNftLevel, 'max level reached');

        uint256 sumOfLevels;

        for (uint256 i; i < relayToBurn.length; ++i) {
            uint256 level_ = nft.getRelayLevel(relayToBurn[i]); // 1 - 5
            uint256 exp = nft.getRelayXp(relayToBurn[i]);

            // only count levels which maxXp is reached;
            sumOfLevels += level_ - 1;
            if (exp >= xpRequiredForLevelUp[level_]) {
                ++sumOfLevels;
            } else {
                require(level_ > 1, 'invalid relayToBurn');
            }
        }
        require(sumOfLevels >= level, 'veRELAY: wut are you burning?');

        // claim verelay before level up
        _claim(msg.sender);

        // Remove effect from Gifted
        _afterNftUnstake(msg.sender, nftId);

        // require XP
        require(nft.getRelayXp(nftId) >= xpRequiredForLevelUp[level], 'veRELAY: XP not enough');

        // skill acquiring
        // acquire the primary skill of a burned relay
        {
            uint256 contributor = 0;
            if (relayToBurn.length > 1) {
                uint256 seed = _enoughRandom();
                contributor = (seed >> 8) % relayToBurn.length;
            }

            uint256 newAbility;
            uint256 newPower;
            (newAbility, newPower) = nft.getPrimaryAbility(relayToBurn[contributor]);
            nft.levelUp(nftId, newAbility, newPower);
            require(nft.getRelayXp(nftId) == 0, 'veRELAY: XP should reset');
        }

        // Re apply effect for Gifted
        _afterNftStake(msg.sender, nftId);

        // burn relayes
        for (uint16 i = 0; i < relayToBurn.length; ++i) {
            require(nft.ownerOf(relayToBurn[i]) == msg.sender, 'veRELAY: not owner');
            nft.burn(relayToBurn[i]);
        }
    }

    /// @dev your sure?
    function _enoughRandom() private view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        // solhint-disable-next-line
                        block.timestamp,
                        msg.sender,
                        blockhash(block.number - 1)
                    )
                )
            );
    }

    /// @notice level down the staked NFT
    function levelDown() external override nonReentrant whenNotPaused {
        uint256 nftId = users[msg.sender].stakedNftId;
        require(nftId > 0, 'not staking NFT');
        --nftId; // remove offset

        require(nft.getRelayLevel(nftId) > 1, 'wut?');

        _claim(msg.sender);

        // Remove effect from Gifted
        _afterNftUnstake(msg.sender, nftId);

        nft.levelDown(nftId);

        // grow to max XP after leveling down
        uint256 maxXp = xpRequiredForLevelUp[nft.getRelayLevel(nftId)];
        nft.growXp(nftId, maxXp);

        // Apply effect for Gifted
        _afterNftStake(msg.sender, nftId);

        // verelay should be capped
        uint32 pudgy;
        uint32 gifted;
        (, pudgy, , gifted, ) = nft.getRelayDetails(nftId);
        uint256 maxVeRelayCap = users[msg.sender].amount * maxStakeCap;
        maxVeRelayCap = (maxVeRelayCap * (100 + pudgy)) / 100 + uint256(gifted) * (10**decimals());

        if (veRelayGeneratedByStake(msg.sender) > maxVeRelayCap) {
            _burn(msg.sender, veRelayGeneratedByStake(msg.sender) - maxVeRelayCap);
        }
    }

    /// @notice get votes for veRELAY
    /// @dev votes should only count if account has > threshold% of current cap reached
    /// @dev invVoteThreshold = (1/threshold%)*100
    /// @param _addr the addres of the nft staker
    /// @return the valid votes
    function getVotes(address _addr) external view virtual override returns (uint256) {
        uint256 veRelayBalance = balanceOf(_addr);

        uint256 nftId = users[_addr].stakedNftId;
        // if nftId > 0, user has nft staked
        if (nftId > 0) {
            --nftId; //remove offset
            uint32 gifted;
            (, , , gifted, ) = nft.getRelayDetails(nftId);
            // burn veRELAY minted by nft
            if (gifted > 0) {
                veRelayBalance -= uint256(gifted) * (10**decimals());
            }
        }

        // check that user has more than voting treshold of maxStakeCap and maxLockCap
        if (
            veRelayBalance * invVoteThreshold >
            users[_addr].amount * maxStakeCap + lockedPositions[_addr].relayLocked * maxLockCap
        ) {
            return veRelayBalance;
        } else {
            return 0;
        }
    }

    function vote(address _user, int256 _voteDelta) external {
        _onlyVoter();

        if (_voteDelta >= 0) {
            usedVote[_user] += uint256(_voteDelta);
            _verifyVoteIsEnough(_user);
        } else {
            // reverts if usedVote[_user] < -_voteDelta
            usedVote[_user] -= uint256(-_voteDelta);
        }
    }
}
