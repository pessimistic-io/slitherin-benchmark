// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IMetaX.sol";
import "./SafeMath.sol";
import "./MerkleProof.sol";
import "./AccessControl.sol";
import "./Ownable.sol";

contract BuilderIncentives is AccessControl, Ownable {
    using SafeMath for uint256;

    /** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    constructor(
        uint256 _Today
    ) {
        Today = _Today;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

    /** MetaX Smart Contracts **/
    /* $MetaX */
    address public MetaX_Addr;
    IERC20 public MX;

    function setMetaX(address _MetaX_Addr) public onlyOwner {
        MetaX_Addr = _MetaX_Addr;
        MX = IERC20(_MetaX_Addr);
    }

    /* BlackHole SBT */
    address public BlackHole_Addr;
    IMetaX public BH;

    function setBlackHole(address _BlackHole_Addr) public onlyOwner {
        BlackHole_Addr = _BlackHole_Addr;
        BH = IMetaX(_BlackHole_Addr);
    }

    /* PlanetGenesis */
    address public PlanetGenesis_Addr;
    IERC721 public PG;

    function setPlanetGenesis(address _PlanetGenesis_Addr) public onlyOwner {
        PlanetGenesis_Addr = _PlanetGenesis_Addr;
        PG = IERC721(_PlanetGenesis_Addr);
    }

    /* PlanetBadges */
    address public PlanetBadges_Addr;
    IMetaX public PB;

    function setPlanetBadges(address _PlanetBadges_Addr) public onlyOwner {
        PlanetBadges_Addr = _PlanetBadges_Addr;
        PB = IMetaX(_PlanetBadges_Addr);
    }

    /* Excess Claimable Builder */
    address public ExcessClaimableBuilder;
    IMetaX public ECB;

    function setExcessClaimableBuilder(address _ExcessClaimableBuilder) public onlyOwner {
        ExcessClaimableBuilder = _ExcessClaimableBuilder;
        ECB = IMetaX(_ExcessClaimableBuilder);
    }

    /** Daily Reset **/
    function dailyReset(bytes32 _merkleRoot) public onlyRole(Admin) {
        Burn(); /* Burning daily unclaimed tokens */
        setRoot(_merkleRoot); /* Set the merkleRoot for POSW verification */
        setToday(); /* Update the timestamp of Today by 1 interval */
    }

    /** Daily Quota **/
    uint256 public T0 = 1676332800; /* Genesis time @Feb 14th 2023 */

    uint256 public dailyQuota = 684931 ether; /* 5% allocation | halve every 2 years | daily released */

    function Halve() public onlyOwner {
        require(block.timestamp >= T0 + 730 days, "BuilderIncentives: Halving every 2 years.");
        dailyQuota = dailyQuota.div(2); /* Daily released tokens halve */
        for (uint256 i = 0; i < Rate.length; i++) {
            Rate[i] = Rate[i].div(2); /* Minting rate halves */
            Limit[i] = Limit[i].div(2); /* Daily minting limit halves */
        }
        T0 += 730 days; /* Update T0 for next halve */
    }

    uint256 public Today; /* The timestamp of today @00:00 UTC */

    function setToday() public onlyRole(Admin) {
        require(block.timestamp - Today > 1 days, "BuilderIncentives: Still within today.");
        Today += 1 days;
    }

    /** Builder Incentives Ability **/
    uint256[] public Rate = [
        /* Rate * 10 ** 14 */
        100,   /* Lv.1  */
        200,   /* Lv.2  */
        300,   /* Lv.3  */
        400,   /* Lv.4  */
        500,   /* Lv.5  */
        650,   /* Lv.6  */
        800,   /* Lv.7  */
        1000,  /* Lv.8  */
        1200,  /* Lv.9  */
        1500,  /* Lv.10 */
        1750,  /* Lv.11 */
        1860,  /* Lv.12 */
        2000   /* Lv.13 */
    ];

    uint256[] public Limit = [
        /* Limit * 10 ** 18 */
        3000,  /* Lv.1  */
        4380,  /* Lv.2  */
        5000,  /* Lv.3  */
        6800,  /* Lv.4  */
        8000,  /* Lv.5  */
        10000, /* Lv.6  */
        13800, /* Lv.7  */
        18000, /* Lv.8  */
        25000, /* Lv.9  */
        30000, /* Lv.10 */
        35000, /* Lv.11 */
        40000, /* Lv.12 */
        50000  /* Lv.13 */
    ];

    /* Additional 3 levels by owning PlanetGenesis NFT */
    function boostPG() public view returns (bool) {
        if (PlanetGenesis_Addr == address(0) || PG.balanceOf(msg.sender) == 0) {
            return false;
        } else {
            return true;
        }
    }

    /* Additional 10% of social mining ability by owning 10+ different series of PlanetBadges NFT */
    function boostPB() public view returns (bool) {
        if (PlanetBadges_Addr == address(0) || PB.getBoostNum(msg.sender) < 10) {
            return false;
        } else {
            return true;
        }
    }

    /** Builder $MetaX Claiming **/
    /* POSW Verification for Builder */
    bytes32 public merkleRoot;

    function setRoot(bytes32 _merkleRoot) public onlyRole(Admin) {
        merkleRoot = _merkleRoot;
    }

    function Verify(
        uint256 POSW_Overall,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory POSW_SocialPlatform,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        require(Id_SocialPlatform.length == POSW_SocialPlatform.length, "BuilderIncentives: Incorrect POSW inputs.");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, POSW_Overall, Id_SocialPlatform, POSW_SocialPlatform));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    mapping(address => uint256) public recentClaimed_Time; /* Recording recent claim time of wallet */

    mapping(address => mapping(uint256 => uint256)) public recentClaimed_Tokens; /* Recording daily claim tokens of wallet */

    /* Claim $MetaX for Builder */
    function Algorithm(uint256 _POSW, uint256 _tokenId_BH) public view returns (uint256 amount, uint256 todayExcess) {
        uint256 _level = BH.getLevel(_tokenId_BH);

        if (boostPG()) {
            _level += 3;
        }

        uint256 _rate = Rate[_level];
        uint256 _limit = Limit[_level].mul(10000);

        if (boostPB()) {
            _rate = _rate.mul(110).div(100);
            _limit = _limit.mul(110).div(100);
        }

        uint256 _decimals = 10**14;
        uint256 todayClaimable = (_POSW.mul(_rate)) + (ECB._getExcess(_tokenId_BH).div(_decimals));

        if (todayClaimable > _limit) {
            amount = _limit;
            todayExcess = todayClaimable - _limit;
        } else {
            amount = todayClaimable;
        }
        if (todayClaimed[Today].div(_decimals) + amount > dailyQuota.div(_decimals)) {
            todayExcess += (todayClaimed[Today].div(_decimals)) + amount - (dailyQuota.div(_decimals));
            amount = dailyQuota.div(_decimals) - todayClaimed[Today].div(_decimals);
        }
        amount = amount.mul(_decimals);
        todayExcess = todayExcess.mul(_decimals);
    }

    function Amount(uint256 _POSW, uint256 _tokenId_BH) public view returns (uint256) {
        (uint256 amount, ) = BuilderIncentives.Algorithm(_POSW, _tokenId_BH);
        return amount;
    }

    function Excess(uint256 _POSW, uint256 _tokenId_BH) public view returns (uint256) {
        (, uint256 todayExcess) = BuilderIncentives.Algorithm(_POSW, _tokenId_BH);
        return todayExcess;
    }

    function Claim_Builder(
        uint256 _tokenId_BH,
        uint256 POSW_Overall,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory POSW_SocialPlatform,
        bytes32[] calldata merkleProof
    ) public {
        require(IERC721(BlackHole_Addr).ownerOf(_tokenId_BH) == msg.sender, "BuilderIncentives: You are not the owner of this BlackHole SBT.");
        require(Verify(POSW_Overall, Id_SocialPlatform, POSW_SocialPlatform, merkleProof), "BuilderIncentives: Incorrect POSW.");
        require(block.timestamp <= Today + 1 days, "BuilderIncentives: Today's claiming process has not started.");
        require(recentClaimed_Time[msg.sender] < Today, "BuilderIncentives: You can claim only once per day.");
        uint256 amount = Amount(POSW_Overall, _tokenId_BH);
        uint256 todayExcess = Excess(POSW_Overall, _tokenId_BH);
        require(todayClaimed[Today] + amount <= dailyQuota, "BuilderIncentives: Exceed today's limit.");
        
        MX.transfer(msg.sender, amount);
        todayClaimed[Today] += amount;
        recentClaimed_Tokens[msg.sender][Today] = amount;
        ECB._setExcess(_tokenId_BH, todayExcess);
        recentClaimed_Time[msg.sender] = block.timestamp;
        BH.addPOSW_Builder(_tokenId_BH, POSW_Overall, Id_SocialPlatform, POSW_SocialPlatform);
        emit builderClaimRecord(msg.sender, _tokenId_BH, POSW_Overall, amount, todayExcess, block.timestamp);
    }

    mapping(uint256 => uint256) public todayClaimed; /* accumulative tokens claimed daily */

    event builderClaimRecord(address builder, uint256 _tokenId, uint256 _POSW, uint256 $MetaX, uint256 Excess, uint256 _time);

    /** Burn **/
    uint256 public accumBurnt;

    address public immutable Burn_addr = 0x000000000000000000000000000000000000dEaD;

    function Burn() public onlyRole(Admin) {
        require(block.timestamp - Today > 1 days, "BuilderIncentives: Still within today.");
        require(todayBurnt[Today] == 0, "BuilderIncentives: Unclaimed tokens have been burnt.");
        uint256 todayUnclaimed = dailyQuota - todayClaimed[Today];
        MX.transfer(Burn_addr, todayUnclaimed);
        todayBurnt[Today] += todayUnclaimed;
        accumBurnt += todayUnclaimed;
        emit burnRecord(todayUnclaimed, block.timestamp);
    }

    function Burn_Amount(uint256 amount) public onlyOwner {
        require(amount <= MX.balanceOf(address(this)), "BuilderIncentives: Insufficient balance.");
        MX.transfer(Burn_addr, amount);
        todayBurnt[Today] += amount;
        accumBurnt += amount;
        emit burnRecord(amount, block.timestamp);
    }

    mapping(uint256 => uint256) public todayBurnt; /* accumulative tokens burnt daily */

    event burnRecord(uint256 burnAmount, uint256 time);
}

