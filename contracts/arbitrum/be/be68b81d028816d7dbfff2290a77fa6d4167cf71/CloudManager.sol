// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Address.sol";
import "./SafeMath.sol";
import "./Context.sol";
import "./Cloud.sol";
import "./CloudTrait.sol";
import "./NimbusToken.sol";
import "./veNimbusToken.sol";
import "./RewardManager.sol";
import "./RPool.sol";
import "./Splitter.sol";
import "./ReetrancyGuard.sol";

contract CloudManager is Ownable, ReentrancyGuard {
    using Address for address;
    using SafeMath for uint256;

    NimbusCloud public cloud;
    CloudTrait public cloudTrait;
    NimbusToken public token;
    RewardManager public rManager;
    RPool public rPool;
    Splitter public splitter;
    veNimbusToken public veToken;
    address public DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint256[] public tsArr;
    mapping(uint256 => uint256[]) public aprArr;

    address public dao;

    mapping(CloudTrait.Level => uint256) public prices;

    modifier onlyAddress() {
        require(!_msgSender().isContract());
        _;
    }

    modifier onlyManager() {
        require(_msgSender() == owner() || _msgSender() == dao, "ERR: forbidden caller.");
        _;
    }

    constructor(
        NimbusCloud _cloud,
        CloudTrait _cloudTrait,
        NimbusToken _token,
        RPool _rPool,
        Splitter _splitter,
        veNimbusToken _veToken
    ) {
        cloud = _cloud;
        cloudTrait = _cloudTrait;
        token = _token;
        veToken = _veToken;
        rPool = _rPool;
        splitter = _splitter;
    }

    function createCloud(
        CloudTrait.Level _level,
        uint256 _amount
    ) external nonReentrant onlyAddress {
        require(_amount > 0 && _amount <= 20, "ERR: amount should be gt 0 and lte 20");
        uint256 price = getTotalPrice(_level, _amount);
        require(
            token.balanceOf(msg.sender) > price,
            "ERR: Token balance too low."
        );
        require(uint256(_level) >= 0 && uint256(_level) <= 2, "ERR: level does not exists");
        uint256 burnAmount = price.mul(200).div(1000);
        uint256 rewardPool = price.mul(250).div(1000);
        uint256 splitterAmount   =  price.mul(550).div(1000);
        token.transferFrom(
            msg.sender,
            DEAD_ADDRESS,
            burnAmount
        );
        token.transferFrom(
            msg.sender,
            address(rPool),
            rewardPool
        );
        token.transferFrom(
            msg.sender,
            address(splitter),
            splitterAmount
        );
        cloud.mint(_amount, msg.sender, _level);
        veToken.mint(msg.sender, getTotalPrice(_level, _amount));
    }

    function claimReward(uint256[] memory _tokenIds) external {
        uint256 rewards;
        uint256 taxes;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(
                cloud.ownerOf(_tokenIds[i]) == _msgSender(),
                "ERR: Caller is not the owner of given token."
            );
            uint256 reward = getRewardPerToken(_tokenIds[i]);
            uint256 tax = rManager.getClaimTax(cloudTrait.getMetadata(_tokenIds[i]).level);
            uint256 netReward = reward.sub(reward.mul(tax).div(1000));
            taxes = taxes.add(reward.sub(netReward));
            rewards = rewards.add(netReward);
            cloud.claim(_tokenIds[i], _msgSender());
        }
        rPool.claim(_msgSender(), rewards, taxes);
    }

    /***********************
        View function area
    ************************/

    function getRewardPerToken(
        uint256 _tokenId
    ) public view returns (uint256) {
        uint256 rewards;
        CloudTrait.Trait memory trait = cloudTrait.getMetadata(_tokenId);
        int256 index = binarySearch(tsArr, trait.lastClaim);
        if (index < 0) {
            return rManager.getRewardPerToken(
                trait.lastClaim,
                block.timestamp,
                aprArr[tsArr.length - 1][uint256(trait.level)],
                prices[trait.level]
            );
        } else {
            bool f = true; // is first ran?
            for (uint256 i = uint256(index); i < tsArr.length; i++) {
                uint256 start;
                uint256 end;
                if (f) {
                    start = trait.lastClaim;
                    f = false;
                } else {
                    start = tsArr[i];
                }
                if (i + 1 >= tsArr.length) {
                    end = block.timestamp;
                } else {
                    end = tsArr[i+1];
                }
                rewards += rManager.getRewardPerToken(
                    start,
                    end,
                    aprArr[i][uint256(trait.level)],
                    prices[trait.level]);
            }
        }
        return rewards;
    }

    function getTotalPrice(
        CloudTrait.Level _level,
        uint256 _amount
    ) public view returns (uint256) {
        return prices[_level] * _amount;
    }

    function getAPR() external view returns(uint256[] memory) {
        return aprArr[tsArr.length - 1];
    }

    function binarySearch(uint[] memory arr, uint x) public pure returns (int) {
        int left = 0;
        int right = int(arr.length) - 1;
        int result = -1;
        while (left <= right) {
            int mid = (left + right) / 2;
            if (arr[uint(mid)] < x) {
                result = mid;
                left = mid + 1;
            } else if (arr[uint(mid)] == x) {
                result = mid;
                break;
            } else {
                right = mid - 1;
            }
        }
        return result;
    }



    /***********************
        Owner function area
    ************************/

    function setPrice(
        CloudTrait.Level _level,
        uint256 _price
    ) external onlyOwner {
        prices[_level] = _price;
    }

    function setYield(
        uint256 _yieldL0,
        uint256 _yieldL1,
        uint256 _yieldL2
    ) external onlyManager {
        tsArr.push(block.timestamp);
        aprArr[tsArr.length-1] = [
            _yieldL0,
            _yieldL1,
            _yieldL2
        ];
    }

    /**
     * Set reward manager contract
     * @param _value : RM contract
     */
    function setRewardManagerContract(
        RewardManager _value
    ) external onlyOwner {
        rManager = _value;
    }

    /**
     * Set reward pool contract
     * @param _value : Reward pool contract
     */
    function setRPool(
        RPool _value
    ) external onlyOwner {
        rPool = _value;
    }

    function setDAOAddress(
        address _dao
    ) external onlyOwner {
        dao = _dao;
    }

    function setSplitter(Splitter _splitter) external onlyOwner {
        splitter = _splitter;
    }
}

