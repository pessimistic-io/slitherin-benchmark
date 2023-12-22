// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC721.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

contract StakeRebel is Ownable, Pausable, ReentrancyGuard, IERC721Receiver {

    // 0=>7;1=>30;2=>90;3=>180;4=>365;
    uint16[5] TIME_LOCK_DAY = [7, 30, 90, 180, 365];
    uint16[5] TIME_BONUS_X100 = [80, 100, 130, 170, 200];
    uint16 TRAIT_BONUS = 4;

    ERC20 public token;
    ERC721 public nft;

    uint256 public rewardPerSecond;

    // struct to store a stake's token, and earning values
    struct Stake {
        uint256 tokenId;
        uint8 timeLevel;
        uint256 unlockTime;
        uint256 lastClaimTime;
    }

    // maps address to nft stakes
    mapping(address => Stake[]) public stakelist;
    // maps tokenId to owner address
    mapping(uint256 => address) public auth;
    // maps tokenId to unlockTime
    mapping(uint256 => uint256) public unlock;
    // maps tokenId to trait
    mapping(uint256 => uint16) public traits;

    event StakeEvent(uint256 tokenId, uint8 timeLevel, uint256 time);
    event WithdrawEvent(uint256 tokenId, uint256 time);
    event ClaimEvent(uint256 tokenId, uint256 reward);
    event ClaimAllEvent(uint256 reward);

    constructor(address _token, address _nft, uint256 _rewardPerSecond) {
        token = ERC20(_token);
        nft = ERC721(_nft);
        rewardPerSecond = _rewardPerSecond;
        // init traits
        traits[1855] = TRAIT_BONUS;
        traits[1044] = TRAIT_BONUS;
        traits[565] = TRAIT_BONUS;

        traits[74] = TRAIT_BONUS;
        traits[566] = TRAIT_BONUS;

        traits[163] = TRAIT_BONUS;
        traits[304] = TRAIT_BONUS;
        traits[862] = TRAIT_BONUS;
        traits[1124] = TRAIT_BONUS;
        traits[1583] = TRAIT_BONUS;
        traits[1751] = TRAIT_BONUS;

        traits[354] = TRAIT_BONUS;
        traits[482] = TRAIT_BONUS;
        traits[593] = TRAIT_BONUS;
        traits[1117] = TRAIT_BONUS;
        traits[1486] = TRAIT_BONUS;

        traits[244] = TRAIT_BONUS;
        traits[1995] = TRAIT_BONUS;
    }

    function stakeMulti(uint256[] memory tokenIds, uint8 timeLevel) external nonReentrant whenNotPaused {
        require(timeLevel < 5, "Invalid timeLevel");
        for (uint i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(nft.ownerOf(tokenId) == msg.sender, "Not your nft");
            nft.safeTransferFrom(msg.sender, address(this), tokenId);
            auth[tokenId] = msg.sender;
            unlock[tokenId] = block.timestamp + TIME_LOCK_DAY[timeLevel] * (1 days);
            stakelist[msg.sender].push(Stake({
                tokenId: tokenId,
                timeLevel: timeLevel,
                unlockTime: unlock[tokenId],
                lastClaimTime: block.timestamp
            }));
            emit StakeEvent(tokenId, timeLevel, block.timestamp);
        }
    }

    function withdraw(uint256 tokenId) public whenNotPaused
        _auth(tokenId)
        _unlock(tokenId)
    {
        claim(tokenId);
        delete auth[tokenId];
        delete unlock[tokenId];
        for (uint i = 0; i < stakelist[msg.sender].length - 1; i++) {
            if (stakelist[msg.sender][i].tokenId == tokenId) {
                stakelist[msg.sender][i] = stakelist[msg.sender][stakelist[msg.sender].length - 1];
                break;
            }
        }
        stakelist[msg.sender].pop();
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        emit WithdrawEvent(tokenId, block.timestamp);
    }

    function claim(uint256 tokenId) public whenNotPaused
        _auth(tokenId)
    {
        for (uint i = 0; i < stakelist[msg.sender].length; i++) {
            Stake storage stake = stakelist[msg.sender][i];
            if (stake.tokenId == tokenId) {
                uint256 reward = calculateReward(tokenId, stake.timeLevel, stake.lastClaimTime);
                stake.lastClaimTime = block.timestamp;
                token.transfer(msg.sender, reward);
                emit ClaimEvent(tokenId, reward);
                break;
            }
        }
    }

    function withdrawMulti(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        for (uint i = 0; i < tokenIds.length; i++) {
            withdraw(tokenIds[i]);
        }
    }

    function claimAll() external nonReentrant whenNotPaused {
        require(stakelist[msg.sender].length > 0, "Not find stake");
        uint256 reward = 0;
        for (uint i = 0; i < stakelist[msg.sender].length; i++) {
            Stake storage stake = stakelist[msg.sender][i];
            reward += calculateReward(stake.tokenId, stake.timeLevel, stake.lastClaimTime);
            stake.lastClaimTime = block.timestamp;
        }
        token.transfer(msg.sender, reward);
        emit ClaimAllEvent(reward);
    }

    modifier _auth(uint256 tokenId) {
        require(auth[tokenId] == msg.sender, "Not your nft");
        _;
    }

    modifier _unlock(uint256 tokenId) {
        require(block.timestamp >= unlock[tokenId], "You can't withdraw yet");
        _;
    }

    function calculateReward(uint256 tokenId, uint8 timeLevel, uint256 lastClaimTime) public view returns (uint256 reward) {
        return (block.timestamp - lastClaimTime) * rewardPerSecond * TIME_BONUS_X100[timeLevel] / 100 * (1 + traits[tokenId]);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
      return IERC721Receiver.onERC721Received.selector;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }
}

