// SPDX-License-Identifier: GPL-3.0

/**

https://t.me/arbistellar
https://twitter.com/ArbiStellar
https://arbistellar.xyz/

*/

pragma solidity ^0.8.0;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./SpaceTravelers.sol";
import "./STLR.sol";
import "./STLRNodeManagerUpgradeableV3.sol";

contract Missions is
Initializable,
PausableUpgradeable,
OwnableUpgradeable,
ReentrancyGuardUpgradeable {

    uint256 public totalTokenEarned;
    uint public maximumTokenStaking;

    // Multiplier for each species
    uint256[] public multipliers;
    // Quest reward for each time quest
    uint256[] public questRewards;
    // time lock in days for each quest
    uint80[] public timeLocked;

    uint256 public totalHumanStaked;
    uint256 public totalRobotStaked;
    uint256 public totalAlienStaked;

    bool public rescueEnabled;
    bool public stopNewEntrance;

    uint8[] typeNft;
    uint256 public totalNftStaked;
    mapping(uint256=>Stake) public poolStackByTokenId;
    mapping(address=>uint[]) public tokenIdsByAddressStaked;

    uint[] Robots;
    uint[] Aliens;

    uint status;

    STLR stlr;
    SpaceTravelers stls;
    NodesManagerUpgradeableV3 nodeManager;

    struct Stake {
        uint8 quest;
        uint8 grade;
        address owner;
        uint80 depositTimestamp;
        uint80 endOfStaking;
        uint tokenId;
    }

    event NftsAddPoolEvent(address indexed account, uint[] indexed tokenIds);
    event NftRemovePoolEvent(uint tokenIds,uint indexed typeNft, uint indexed owed,uint indexed status, bool unstake);

    function initialize(address _stls, address _stlr, address _nodeManager) external initializer
    {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        totalTokenEarned = 0;
        maximumTokenStaking = 50_000 ether;

        // Divide by 100
        multipliers = [100,120,160];
        // Divide by 100
        questRewards = [20,77,240];
        timeLocked = [2 days,7 days,20 days];

        totalHumanStaked = 0;
        totalRobotStaked = 0;
        totalAlienStaked = 0;

        status = 0;

        nodeManager = NodesManagerUpgradeableV3(_nodeManager);
        stlr = STLR(payable(_stlr));
        stls = SpaceTravelers(_stls);
    }

    function addManyToStaking(address account, uint[] memory tokenIds, uint8 quest)
    external
    _updateEarnings
    whenNotPaused
    {
        uint256[] memory nodesOwned = nodeManager.getNodeIdsOf(account);
        require(nodesOwned.length >= 1, "STAKING: You need to own at least a node");
        require((account == msg.sender && account == tx.origin), "STAKING: This is not your account");
        require(!stopNewEntrance, "STAKING: New entrance is disable");
        require(questRewards.length-1 >= quest, "STAKING: Quest does not exist");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (account != address(stls)) {
                require(stls.ownerOf(tokenIds[i]) == account, "STAKING: Not your NFT");
                stls.approve(account, address(this), tokenIds[i]);
                stls.transferFrom(account, address(this), tokenIds[i]);

            } else if (tokenIds[i] == 0) {
                continue;
            }
            addNftToStaking(msg.sender, tokenIds[i], quest);
        }
        emit NftsAddPoolEvent(account, tokenIds);
    }

    function addNftToStaking(address _account, uint _tokenId, uint8 quest)
    internal
    {
        uint8 race = stls.getRace(_tokenId);
        poolStackByTokenId[_tokenId] = Stake({
        owner: _account,
        tokenId: _tokenId,
        grade: race,
        depositTimestamp: uint80(block.timestamp),
        endOfStaking: uint80(block.timestamp) + timeLocked[quest],
        quest: quest
        });

        if (!_isPresent(_tokenId,_account))
            tokenIdsByAddressStaked[_account].push(_tokenId);

        totalNftStaked += 1;

        if (race == 3){
            totalAlienStaked += 1;
        }
        else if (race == 2) {
            totalRobotStaked += 1;
        }
        else if (race == 1) {
            totalHumanStaked += 1;
        }
        else {
            revert("STAKING: race is not allowed");
        }
    }

    function isHuman(uint256 tokenId) internal view returns (bool) {
        return stls.getRace(tokenId) == 1;
    }

    function isRobot(uint256 tokenId) internal view returns (bool) {
        return stls.getRace(tokenId) == 2;
    }

    function isAlien(uint256 tokenId) internal view returns (bool) {
        return stls.getRace(tokenId) == 3;
    }

    function unStake(uint[] memory tokenIds)
    external
    payable
    whenNotPaused
    {
        require(tokenIds.length > 0, "STAKING: Select minimal one stls");

        uint256 owed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            owed += _unStake(tokenIds[i]);
        }
        if (owed == 0) return;
        require(totalTokenEarned + owed < maximumTokenStaking , "STAKING: Sorry maximum token is minted");
        stlr.mint(msg.sender, owed);
        totalTokenEarned += owed;
    }

    function _unStake(uint tokenId)
    internal
    returns (uint256 owed)
    {
        Stake memory stake = poolStackByTokenId[tokenId];

        require ((stake.owner == msg.sender), "STAKING: Not your NFT");
        require(!(block.timestamp - stake.depositTimestamp < timeLocked[stake.quest]), "STAKING: Please respect delay to unstack");

        if (totalTokenEarned < maximumTokenStaking) {
            owed = questRewards[stake.quest] * 10**18 / 100 * multipliers[stake.grade-1] / 100 ;
        }
        uint8 race = stls.getRace(tokenId);

        _removeValueAddressStake(tokenId, stake.owner);
        stls.safeTransferFrom(address(this), msg.sender, tokenId);
        delete poolStackByTokenId[tokenId];

        totalNftStaked -= 1;
        if (isHuman(tokenId))
            totalHumanStaked -= 1;
        else if (isRobot(tokenId))
            totalRobotStaked -= 1;
        else if (isAlien(tokenId))
            totalAlienStaked -= 1;
        else
            revert("STAKING: race is not allowed");

        emit NftRemovePoolEvent(tokenId, race, owed, 0, true);
        return owed;
    }


    function _isPresent(uint value, address owner)
    internal
    view
    returns (bool check)
    {
        uint[] storage tokenIds = tokenIdsByAddressStaked[owner];
        for(uint i=0;i < tokenIds.length; i++) {
            if (tokenIds[i] == value) {
                return true;
            }
        }
        return false;
    }

    function _removeValueAddressStake(uint value, address owner)
    internal
    {
        uint[] storage tokenIds = tokenIdsByAddressStaked[owner];
        for(uint i=0;i < tokenIds.length; i++) {
            if (tokenIds[i] == value) {
                uint tokenId = tokenIds[i];
                uint last = tokenIds[tokenIds.length-1];
                tokenIds[i] = last;
                tokenIds[tokenIds.length-1] = tokenId;
                tokenIds.pop();
                tokenIdsByAddressStaked[owner] = tokenIds;
            }
        }
    }

    function getMyNftStaking()
    external
    view
    returns (uint[] memory tokenIds)
    {
        tokenIds = tokenIdsByAddressStaked[msg.sender];
        return tokenIds;
    }

    function getNftsInfo(uint[] memory tokenIds)
    public
    view
    returns (Stake[] memory)
    {
        Stake[] memory stakedNfts = new Stake[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            stakedNfts[i] = poolStackByTokenId[tokenIds[i]];
        }
        return stakedNfts;
    }

    function getNfInfo(uint _tokenId)
    public
    view
    returns (Stake memory)
    {
        return poolStackByTokenId[_tokenId];
    }

    modifier _updateEarnings() {
        require(totalTokenEarned < maximumTokenStaking, "STAKING: All tokens minted");
        _;
    }

    function setStopNewEntrance(bool _newEntrance)
    external
    onlyOwner
    {
        if (_newEntrance) stopNewEntrance = false;
        else stopNewEntrance = true;
    }

    function setPaused(bool _paused)
    external
    onlyOwner
    {
        if (_paused) _pause();
        else _unpause();
    }


    function setMaximunTokenStaking(uint _newMax)
    public
    onlyOwner
    {
        maximumTokenStaking = _newMax;
    }

    function setRescueEnabled()
    external
    onlyOwner
    {
        if (rescueEnabled)
            rescueEnabled = false;
        else
        rescueEnabled = true;
    }

    // use with caution - rescue only if you are facing a staking problem
    function rescue(address account, uint256[] memory tokenIds)
    external
    {
        require(rescueEnabled, "STAKING: Rescue is not activate");
        require(account == msg.sender, "STAKING: Not your account");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            Stake memory stake = poolStackByTokenId[tokenIds[i]];
            require(stake.owner == account, "STAKING: Not your NFT");
            stls.transferFrom(address(this), msg.sender, tokenIds[i]);
            delete poolStackByTokenId[tokenIds[i]];
            totalNftStaked -= 1;
            if (isHuman(tokenIds[i])) totalHumanStaked -= 1;
            else if (isRobot(tokenIds[i])) totalRobotStaked -= 1;
            else if (isAlien(tokenIds[i])) totalAlienStaked -= 1;
            else revert("STAKING: race is not allowed");
            _removeValueAddressStake(tokenIds[i], stake.owner);
            emit NftRemovePoolEvent(tokenIds[i], stls.getRace(tokenIds[i]), 0, 6, true);
        }
    }

    function setNodeAddress(address addr) public onlyOwner {
        nodeManager = NodesManagerUpgradeableV3(addr);
    }

    function setStlrAddress(address addr) public onlyOwner {
        stlr = STLR(payable(addr));
    }

    function setStlsAddress(address addr) public onlyOwner {
        stls = SpaceTravelers(addr);
    }


}

