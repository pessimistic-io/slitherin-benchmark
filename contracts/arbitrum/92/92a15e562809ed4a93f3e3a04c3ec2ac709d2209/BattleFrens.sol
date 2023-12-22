// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./NFAERC721.sol";

interface IFREN {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function ownerOf(uint256 tokenId) external view returns (address);
}

contract BattleFrens is Ownable, ReentrancyGuard {
    FrensArmy frensNFT;
    address public NFA_ERC721 = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    address public NFA_ERC20 = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    address public constant fren_grave = 0x000000000000000000000000000000000000dEaD;
    address public constant zero = 0x0000000000000000000000000000000000000000;
    uint128 private constant TWO127 = 0x80000000000000000000000000000000;
    uint128 private constant TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint128 private constant LN2 = 0xb17217f7d1cf79abc9e3b39803f2f6af;
    uint256 public decimals = 1e18;
    uint256 public minBet = 6900;
    uint256 public currBattle_id;
    uint256 public rewardperc = 6;
    uint256 public burnperc = 4;

    bool public fren1Joined;
    bool public fren2Joined;

    mapping(address => uint256) public frenRewardDebt;
    mapping(uint256 => bool) public _hasHat;
    mapping(address => bool) private _isNonFren;
    mapping(uint256 => address) public fren1; //mapping battle_id to fren1
    mapping(uint256 => address) public fren2; //mapping battle_id to fren2
    mapping(address => bool) public waitingPlayers; // players waiting to play
    mapping(uint256 => mapping(address => uint256)) public frenVital; // mapping battle_id frenVitality
    mapping(uint256 => mapping(address => uint256)) public frenBets; // mapping battle_id frenBet
    mapping(uint256 => bool) public btl_HasStarted; // mapping battle_id to hasStarted
    mapping(uint256 => bool) public btl_HasFinished; // mapping battle_id to hasStarted
    mapping(uint256 => address) public WinnerFren; //mapping battle_id to WinnerFren
    mapping(uint256 => address) public LoserFren; //mapping battle_id to WinnerFren
    mapping(uint256 => mapping(address => string)) public frenImg; // mapping battle_id images

    event Fren1joined(address indexed fren1, uint256 indexed battleid, string tokenURI);
    event Fren2joined(address indexed fren2, uint256 indexed battleid, string tokenURI);
    event BattleFinished(address indexed winner, uint256 indexed battleid, string winnerURI);

    constructor() {
        frensNFT = FrensArmy(NFA_ERC721);
    }

    function setAddress(
        address _Fren_NFT,
        address _Fren_Token,
        uint256 _rewardperc,
        uint256 _rewardburn
    ) public onlyOwner {
        NFA_ERC721 = _Fren_NFT;
        NFA_ERC20 = _Fren_Token;
        frensNFT = FrensArmy(NFA_ERC721);
        rewardperc = _rewardperc;
        burnperc = _rewardburn;
    }

    function overRideCounter(uint256 _currBattle) public onlyOwner {
        currBattle_id = _currBattle;
    }

    function fren1join(uint256 _battleid, uint256 _amountNFA, string memory _tokenURI) public {
        uint256 amount = _amountNFA * decimals;
        string memory tokenURI = _tokenURI;
        frenImg[_battleid][msg.sender] = _tokenURI;
        require(!btl_HasStarted[_battleid], "Battle already Begun");
        require(IFREN(NFA_ERC20).balanceOf(tx.origin) > amount, "You must have more $NFA");
        require(fren1[_battleid] == zero, "Fren1 already joined");
        require(_battleid < currBattle_id + 3, "Not current Battle");
        fren1[_battleid] = msg.sender;
        frenBets[_battleid][msg.sender] = amount;
        IFREN(NFA_ERC20).transferFrom(msg.sender, address(this), amount);
        fren1Joined = true;
        emit Fren1joined(fren1[_battleid], _battleid, tokenURI);
    }

    function fren2join(uint256 _battleid, uint256 _amountNFA, string memory _tokenURI) public {
        uint256 amount = _amountNFA * decimals;
        string memory tokenURI = _tokenURI;
        frenImg[_battleid][msg.sender] = _tokenURI;
        require(!btl_HasStarted[_battleid], "Battle already Begun");
        require(IFREN(NFA_ERC20).balanceOf(msg.sender) > amount, "You must have more $NFA");
        require(fren2[_battleid] == zero, "Fren2 already joined");
        require(_battleid == currBattle_id, "Not current Battle");
        fren2[_battleid] = msg.sender;
        frenBets[_battleid][msg.sender] = amount;
        IFREN(NFA_ERC20).transferFrom(msg.sender, address(this), amount);
        fren2Joined = true;

        emit Fren2joined(fren2[_battleid], _battleid, tokenURI);
    }

    function startbattle(uint256 _battleid) public {
        address _fren1 = fren1[_battleid];
        address _fren2 = fren2[_battleid];
        require(!btl_HasStarted[_battleid], "Battle already Begun");
        require(_fren1 != zero && _fren2 != zero, "Waiting for Fren");
        require(_fren1 == msg.sender || _fren2 == msg.sender, "You are not a Fren");

        frenVital[_battleid][_fren1] = vitalityCalculator(_fren1);
        frenVital[_battleid][_fren2] = vitalityCalculator(_fren2);
        uint256 totalVitals = frenVital[_battleid][_fren1] + frenVital[_battleid][_fren2];
        uint256 totalbet = frenBets[_battleid][_fren1] + frenBets[_battleid][_fren2];
        btl_HasStarted[_battleid] = true;

        uint256 Fren1XP = (frenVital[_battleid][_fren1] + frenBets[_battleid][_fren1]) / (totalVitals + totalbet);
        uint256 Fren2XP = (frenVital[_battleid][_fren2] + frenBets[_battleid][_fren2]) / (totalVitals + totalbet);
        uint256 totalXP = Fren1XP + Fren2XP;
        uint256 randomNumber = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, block.difficulty))) %
            totalXP);

        if (Fren1XP >= Fren2XP) {
            if (randomNumber < Fren1XP) {
                WinnerFren[_battleid] = _fren1;
                LoserFren[_battleid] = _fren2;
            } else {
                WinnerFren[_battleid] = _fren2;
                LoserFren[_battleid] = _fren1;
            }
        }
        if (Fren2XP > Fren1XP) {
            if (randomNumber < Fren2XP) {
                WinnerFren[_battleid] = _fren1;
                LoserFren[_battleid] = _fren2;
            } else {
                WinnerFren[_battleid] = _fren2;
                LoserFren[_battleid] = _fren1;
            }
        }
        address loser = LoserFren[_battleid];
        address winner = WinnerFren[_battleid];
        frenRewardDebt[winner] = frenBets[_battleid][winner] + ((frenBets[_battleid][loser] * rewardperc) / 10);

        uint256 betamount = frenBets[_battleid][loser];
        string memory winnerURI = frenImg[_battleid][winner];
        currBattle_id++;
        fren1Joined = false;
        fren2Joined = false;
        IFREN(NFA_ERC20).transfer(fren_grave, ((betamount * burnperc) / 10));

        emit BattleFinished(WinnerFren[_battleid], _battleid, winnerURI);
    }

    function vitalityCalculator(address _user) public view returns (uint256) {
        uint256 multiplier = 10 ** 18;
        uint256 nfa_erc20_balance = IFREN(NFA_ERC20).balanceOf(_user) / multiplier;
        uint256 nfa_erc721_balance = IFREN(NFA_ERC721).balanceOf(_user);
        uint256 gmAmount = frensNFT.user_GM(_user);
        uint256 userPoints = gmAmount * nfa_erc721_balance * nfa_erc20_balance;

        return userPoints;
    }

    function getReward() public nonReentrant {
        require(frenRewardDebt[msg.sender] > 0, "Your Fren doesn't have pending rewards");
        require(IFREN(NFA_ERC721).balanceOf(msg.sender) > 0, "You don't own a Fren");
        uint256 reward = frenRewardDebt[msg.sender] - 1;
        frenRewardDebt[msg.sender] = 0;
        IFREN(NFA_ERC20).transfer(msg.sender, reward);
    }

    function setminBet(uint256 _minBet) public onlyOwner {
        minBet = _minBet;
    }

    function setNonFrens(address[] calldata _addresses, bool bot) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isNonFren[_addresses[i]] = bot;
        }
    }

    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);

        if (x >= 0x100000000000000000000000000000000) {
            x >>= 128;
            r += 128;
        }
        if (x >= 0x10000000000000000) {
            x >>= 64;
            r += 64;
        }
        if (x >= 0x100000000) {
            x >>= 32;
            r += 32;
        }
        if (x >= 0x10000) {
            x >>= 16;
            r += 16;
        }
        if (x >= 0x100) {
            x >>= 8;
            r += 8;
        }
        if (x >= 0x10) {
            x >>= 4;
            r += 4;
        }
        if (x >= 0x4) {
            x >>= 2;
            r += 2;
        }
        if (x >= 0x2) r += 1; // No need to shift x anymore
    }

    /**
     * Calculate log_2 (x / 2^128) * 2^128.
     *
     * @param x parameter value
     * @return log_2 (x / 2^128) * 2^128
     */
    function log_2(uint256 x) internal pure returns (int256) {
        require(x > 0);

        uint8 msb = mostSignificantBit(x);

        if (msb > 128) x >>= msb - 128;
        else if (msb < 128) x <<= 128 - msb;

        x &= TWO128_1;

        int256 result = (int256(int8(msb)) - 128) << 128; // Integer part of log_2

        int256 bit = int256(int128(TWO127));
        for (uint8 i = 0; i < 128 && x > 0; i++) {
            x = (x << 1) + ((x * x + TWO127) >> 128);
            if (x > TWO128_1) {
                result |= bit;
                x = (x >> 1) - TWO127;
            }
            bit >>= 1;
        }

        return result;
    }

    /**
     * Calculate ln (x / 2^128) * 2^128.
     *
     * @param x parameter value
     * @return ln (x / 2^128) * 2^128
     */
    function ln(uint256 x) internal pure returns (uint256) {
        require(x > 0);

        int256 l2 = log_2(x);
        if (l2 == 0) return 0;
        else {
            uint256 al2 = uint256(l2 > 0 ? l2 : -l2);
            uint8 msb = mostSignificantBit(al2);
            if (msb > 127) al2 >>= msb - 127;
            al2 = (al2 * LN2 + TWO127) >> 128;
            if (msb > 127) al2 <<= msb - 127;

            return uint256(l2 >= 0 ? al2 : al2);
        }
    }
}

