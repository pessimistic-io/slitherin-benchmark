pragma solidity ^0.6.12;

import "./FarmUtils.sol";

contract VaultFarms {
    using SafeMath for uint256;

    address public farmCEO;
    address public arbear;
    address public zapperstaker;
    uint256 public minSarvPct;

    bool public isSetup;

    mapping (address => uint256) public farmWeight;
    mapping (address => uint256) public farmWeightAnned;
    mapping (address => uint256) public farmAnnedOn;
    uint256[] public lockups;
    mapping (uint256 => address) public lockupIdPool;
    mapping (uint256 => address) public lockupIdUser;
    mapping (address => uint256[]) public lockupUserIds;
    mapping (uint256 => uint256) public lockupIdAmount;
    mapping (uint256 => uint256) public lockupIdLPAmount;

    function userLockups(address _user) public view returns (uint[] memory) {
        return lockupUserIds[_user];
    }

    function userLockupsLength(address _user) public view returns (uint) {
        return lockupUserIds[_user].length;
    }

    function migratefarmCEO(address _farmCEO) public  {
        require(farmCEO == msg.sender);
        farmCEO = _farmCEO;
    }

    bool public isTipCEO;

    function setIsTipCEO(bool _tip) public  {
        require(farmCEO == msg.sender);
        isTipCEO = _tip;
    }

    function initFarming() public  {
        require(farmCEO == msg.sender);
        //1k arbear is sent to farmCEO
        IERC20(arbear).transfer(msg.sender, 1000*10**9);
        isSetup = true;
    }

    uint public zsAnnedOn;
    address public zsAnned;

    // 7 days waiting period before zapperstaker can be altered
    // can be voided by invoking the same function with 0x0
    function annZapperStaker(address _zs) public  {
        require(farmCEO == msg.sender);
        zsAnnedOn = block.timestamp;
        zsAnned = _zs;
    }

    function setZapperStaker(address _zs) public  {
        require(farmCEO == msg.sender);
        if (zapperstaker == address(0)) {
            zapperstaker = _zs;
        } else {
            require(block.timestamp > zsAnnedOn.add(7 days));
            zapperstaker = zsAnned;
        }
    }

    function setArBear(address _arbear) public  {
        require(farmCEO == msg.sender);
        require(arbear == address(0));
        arbear = _arbear;
    }

    // 5 day timelock period for adding new farms:
    // only effective once 5 days passed since it was announced
    // farm announcement can be cancelled
    // address LP token, uint256 totalArBearSupplyToFarm
    function addFarmTimeLocked(address _farm) public  {
        require(farmCEO == msg.sender);
        require(block.timestamp > farmAnnedOn[_farm].add(5 days));
        farmWeight[_farm] = farmWeightAnned[_farm];
    }

    // can only be called during initialization before isSetup() is true
    // same as addfarm but adds initial farms directly
    // isSetup is a one-way var, can't be switched back to false
    function _addFarmInitialDuringSetupOnly(address _farm, uint _weight) public  {
        require(farmCEO == msg.sender);
        require(!isSetup);
        farmWeight[_farm] = _weight;
    }

    function announceFarm(address _farm, uint256 _weight) public  {
        require(farmCEO == msg.sender);
        farmAnnedOn[_farm] = block.timestamp;
        farmWeightAnned[_farm] = _weight;
    }

    function recallAnnouncementFarm(address _farm) public  {
        require(farmCEO == msg.sender);
        farmAnnedOn[_farm] = 0;
    }

    // stop accepting new LP depostis in case some memecoin goes full rug
    // doesn't affect existing farmers
    function removeFarm(address _farm, uint256 _weight) public  {
        require(farmCEO == msg.sender);
        farmWeight[_farm] = _weight;
    }


    function setFarmSarvPct(uint256 _spct) public  {
        require(farmCEO == msg.sender);
        minSarvPct = _spct;
    }

    function farmBear(address _farm, uint256 _amountFull, uint256 _sarvPct, uint256 _min1, uint256 _min2) public  {
        require(farmWeight[_farm] != 0, "fw");
        require(_sarvPct >= minSarvPct , "s");
        IERC20(_farm).transferFrom(msg.sender, address(this), _amountFull);

        uint256 weightForAllSupply = farmWeight[_farm];
        uint256 weightPerLPToken = weightForAllSupply.div(IERC20(_farm).totalSupply());

        uint256 amountForSarv = _amountFull.mul(_sarvPct).div(100);
        uint256 amountAftersArv = _amountFull.sub(amountForSarv);
        uint256 bearMinted = amountAftersArv.mul(weightPerLPToken).div(10**9);
        uint arrayLength = lockupUserIds[msg.sender].length;
        uint prevLockupId;
        for (uint i=0; i<arrayLength; i++) {
            uint _id = lockupUserIds[msg.sender][i];
            if (lockupIdPool[_id] == _farm) {
                prevLockupId = _id;
                break;
            }
        }
        if (prevLockupId != 0) {
            lockupIdAmount[prevLockupId] = lockupIdAmount[prevLockupId].add(bearMinted);
            lockupIdLPAmount[prevLockupId] = lockupIdLPAmount[prevLockupId].add(amountAftersArv);
        } else {
            lockups.push(lockups.length);
            uint newId = lockups.length;
            lockupIdAmount[newId] = lockupIdAmount[newId].add(bearMinted);
            lockupIdPool[newId] = _farm;
            lockupIdLPAmount[newId] = lockupIdLPAmount[newId].add(amountAftersArv);
            lockupIdUser[newId] = msg.sender;
            lockupUserIds[msg.sender].push(newId);
        }

        IERC20(_farm).transfer(zapperstaker, amountForSarv);
        //min1, min2 can be 0 for now (until MEVing starts)
        IZapperStaker(zapperstaker).zapandstake(amountForSarv, _farm, msg.sender, _min1, _min2);

        IERC20(arbear).transfer(msg.sender, bearMinted);
        if (isTipCEO && (bearMinted > 100)) {
        IERC20(arbear).transfer(farmCEO, bearMinted.mul(1).div(100));
        }
        emit Farmed(_farm, _amountFull, bearMinted, msg.sender);
    }


    function unFarmBear(address _farm) external {
        uint arrayLength = lockupUserIds[msg.sender].length;
        uint prevLockupId;
        for (uint i=0; i<arrayLength; i++) {
            uint _id = lockupUserIds[msg.sender][i];
            if (lockupIdPool[_id] == _farm) {
                prevLockupId = _id;
                break;
            }
        }
        uint arbearToUnfarm = lockupIdAmount[prevLockupId];
        lockupIdAmount[prevLockupId] = 0;
        IERC20(arbear).transferFrom(msg.sender, address(this), arbearToUnfarm);

        uint lpToUnfarm = lockupIdLPAmount[prevLockupId];
        lockupIdLPAmount[prevLockupId] = 0;
        IERC20(_farm).transfer(msg.sender, lpToUnfarm);
        emit Unfarmed(_farm, lpToUnfarm, arbearToUnfarm, msg.sender);
    }

	constructor() public {
        farmCEO = msg.sender;
        isTipCEO = true;
	}


    event Farmed(address indexed farm, uint indexed amount, uint amountBear, address sender);
    event Unfarmed(address indexed farm, uint indexed amount, uint amountBear, address sender);
}

interface IZapperStaker {
    function zapandstake(uint256 _amount, address _farm, address _farmer, uint _minTok1, uint minTok2) external;
}

