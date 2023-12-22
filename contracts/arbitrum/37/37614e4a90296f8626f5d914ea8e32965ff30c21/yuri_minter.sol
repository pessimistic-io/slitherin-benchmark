// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import ERC721holderupgradable
import "./ERC721HolderUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IChain.sol";

interface IYuri {
    function mint(string memory uri, address addr) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function balanceOf(address addr) external view returns (uint);
}

interface IGS {
    function mint(address addr, string memory uri) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function balanceOf(address addr) external view returns (uint);

    function checkUserCardList(address player) external view returns (uint[] memory);
}

interface ISBT {
    function mint(address addr, uint cardId) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function balanceOf(address addr) external view returns (uint);

    function checkUserCardId(address addr) external view returns (uint);

    function cardMintAmount(uint cardId) external view returns (uint);
}

interface IERC20Metadata {

    function decimals() external view returns (uint8);
}

contract Yuri_Minter is OwnableUpgradeable, ERC721HolderUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IYuri public yuri;
    IERC20Upgradeable public USDT;
    uint public mintPrice;

    struct Status {
        bool AIGCStatus;
        bool KajamaStatus;
        bool SbtStatus;
    }

    Status public status;

    struct UserInfo {
        uint mintAmount;
        address invitor;
        uint referAmount;
        address[] referList;
        uint referReward;
        uint freeMintAmount;
        bool isWhite;
        uint usdtMintAmount;
    }

    mapping(address => UserInfo) public userInfo;

    IGS public igs;
    ISBT public sbt;
    mapping(uint => bool) public isChange;
    address public banker;
    AggregatorV3Interface public BTCPriceFeed;
    AggregatorV3Interface public ETHPriceFeed;
    IERC20MetadataUpgradeable public BTC;
    uint[]  levelList;
    uint randomSeed;

    uint airDropNum;
    uint public airDropTotal;
    IERC20Upgradeable public token;

    struct AirDropInfo {
        bool isArbClaimed;
        bool isYuriClaimed;
        bool isSbtClaimed;
        bool isIgsClaimed;
        uint totalClaimed;
    }

    uint totalFreeMint;
    uint totalBond;
    uint totalUsdtMint;
    mapping(address => AirDropInfo) public airDropInfo;
    uint[] airDropRate;
    uint public mintYuriEndTime;
    mapping(uint => bool) public kajamaClaimed;
    mapping(uint => uint) public soulBondMap;
    uint public soulBondEndTime;
    uint[] soulBondRate;
    mapping(uint => bool) public soulBonded;

    event Bond(address indexed invitor, address indexed user);
    event Mint(address indexed user, string indexed uri);
    event Change(address indexed user, string indexed uri_);
    event SoulBond(address indexed user, uint indexed level);
    event ClaimArbitrum(address indexed user, uint amount);
    event ClaimYuri(address indexed user, uint amount);
    event ClaimKajama(address indexed user, uint amount);
    event ClaimSoulBond(address indexed user, uint amount);

    uint airDropNums;
    bool[4] airDropStatus;
    uint public aigcAirDropStartTime;
    mapping(address => bool) public aigcAirDropClaimed;

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        mintPrice = 2e6;
        airDropRate = [10, 15, 25, 50];
        soulBondEndTime = block.timestamp + 360 days;
        soulBondRate = [0, 3, 7, 15, 20, 25, 30];
        mintYuriEndTime = block.timestamp + 30 days;
        airDropNum = 95480;
        airDropTotal = 1000000 ether;
    }

    modifier onlyEOA(){
        require(msg.sender == tx.origin, "onlyEOA");
        _;
    }

    function rand(uint256 _length) internal returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, randomSeed)));
        randomSeed ++;
        return random % _length + 1;
    }

    function setMintPrice(uint _price) public onlyOwner {
        mintPrice = _price;
    }

    function setAirDropStatus(bool[4] memory status_) public onlyOwner {
        airDropStatus = status_;
    }

    function setYuri(address _yuri) public onlyOwner {
        yuri = IYuri(_yuri);
    }

    function setUSDT(address _usdt) public onlyOwner {
        USDT = IERC20Upgradeable(_usdt);
    }

    function setSBT(address sbt_) public onlyOwner {
        sbt = ISBT(sbt_);
    }

    function setYuriToken(address token_) public onlyOwner {
        token = IERC20Upgradeable(token_);
    }

    function setAirDropTotalAmount(uint amount) public onlyOwner {
        airDropTotal = amount;
    }

    function setLevelList(uint[] memory list) public onlyOwner {
        levelList = list;
    }

    function setPriceFeed(address btc_, address eth_) public onlyOwner {
        BTCPriceFeed = AggregatorV3Interface(btc_);
        ETHPriceFeed = AggregatorV3Interface(eth_);
    }

    function setToken(address btc_) public onlyOwner {
        BTC = IERC20MetadataUpgradeable(btc_);
        //        ETH = IERC20Upgradeable(eth_);
    }

    function setMintYuriEndTime(uint time) public onlyOwner {
        mintYuriEndTime = time;
    }

    function setIGS(address igs_) public onlyOwner {
        igs = IGS(igs_);
    }

    function setSoulBondEndTime(uint time) public onlyOwner {
        soulBondEndTime = time;
    }

    function setBanker(address addr) external onlyOwner {
        banker = addr;
    }

    function setWhite(address[] memory addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            userInfo[addrs[i]].isWhite = b;
        }
    }

    function bond(address invitor) external onlyEOA {
        require(userInfo[msg.sender].invitor == address(0), 'already bond');
        require(invitor != msg.sender, 'can not bond self');
        require(block.timestamp < mintYuriEndTime, 'bond yuri end');
        //        require(userInfo[invitor].mintAmount > 0, 'invitor must mint one card');
        userInfo[invitor].referAmount ++;
        userInfo[msg.sender].invitor = invitor;
        userInfo[invitor].referList.push(msg.sender);
        totalBond++;
        emit Bond(invitor, msg.sender);
    }

    function mintYuri(string memory uri, bool isFreeMint) external onlyEOA {
        require(status.AIGCStatus, 'not open yet');
        require(block.timestamp <= aigcAirDropStartTime, 'mint yuri end');
        if (isFreeMint) {
            require(userInfo[msg.sender].freeMintAmount < 10, 'out of limit');
            uint referAmount = userInfo[msg.sender].referAmount;
            uint toMintAmount = referAmount / 3;
            if (userInfo[msg.sender].isWhite) {
                toMintAmount ++;
            }
            uint freeMintAmount = toMintAmount - userInfo[msg.sender].freeMintAmount;
            require(freeMintAmount > 0, 'no free mint');
            userInfo[msg.sender].freeMintAmount += 1;
            totalFreeMint ++;
        } else {
            require(userInfo[msg.sender].mintAmount - userInfo[msg.sender].freeMintAmount < 500, 'out of limit');
            USDT.safeTransferFrom(msg.sender, address(this), mintPrice);
            address temp = userInfo[msg.sender].invitor;
            if (temp != address(0)) {
                USDT.transfer(temp, mintPrice / 10);
                userInfo[temp].referReward += mintPrice / 10;
            }
            USDT.transfer(0x21f2e2eFB73Ce38BeFbdE175Ba3fA501696c1c34, USDT.balanceOf(address(this)));
            userInfo[msg.sender].usdtMintAmount++;
            totalUsdtMint ++;
        }

        yuri.mint(uri, msg.sender);
        userInfo[msg.sender].mintAmount ++;

        emit Mint(msg.sender, uri);
    }


    function changeToKajama(uint cardId, string memory uri_) external onlyEOA {
        require(status.KajamaStatus, 'not open yet');
        yuri.safeTransferFrom(msg.sender, address(this), cardId);
        //        uint id = rand(10);
        igs.mint(msg.sender, uri_);
        emit Change(msg.sender, uri_);
    }

    function changeToSBT(uint cardId, uint times, bytes32 r, bytes32 s, uint8 v) external onlyEOA {
        require(status.SbtStatus, 'not open yet');
        require(sbt.balanceOf(msg.sender) == 0, 'minted');
        require(igs.ownerOf(cardId) == msg.sender, 'not owner');
        require(soulBonded[cardId] == false, 'already soul bonded');
        soulBonded[cardId] = true;
        bytes32 hash = keccak256(abi.encodePacked(times, msg.sender));
        address a = ecrecover(hash, v, r, s);
        require(a == banker, "not banker");
        if (times <= levelList[0]) {
            sbt.mint(msg.sender, 1);
            if (block.timestamp < soulBondEndTime) {
                soulBondMap[1]++;
            }
            emit SoulBond(msg.sender, 1);
        }
        else if (times > levelList[levelList.length - 1]) {
            if (checkUserValue(msg.sender) > 500 ether) {
                sbt.mint(msg.sender, levelList.length + 1);
                if (block.timestamp < soulBondEndTime) {
                    soulBondMap[levelList.length + 1]++;
                }
                emit SoulBond(msg.sender, levelList.length + 1);
            } else {
                sbt.mint(msg.sender, levelList.length);
                if (block.timestamp < soulBondEndTime) {
                    soulBondMap[levelList.length]++;
                }
                emit SoulBond(msg.sender, levelList.length);
            }

        }
        else {
            for (uint i = 1; i < levelList.length; i++) {
                if (times > levelList[i - 1] && times <= levelList[i]) {
                    sbt.mint(msg.sender, i);
                    emit SoulBond(msg.sender, i);
                    if (block.timestamp < soulBondEndTime) {
                        soulBondMap[i]++;
                    }
                }
            }
        }


    }

    function getBTCPrice() public view returns (uint) {
        (, int price, , ,) = BTCPriceFeed.latestRoundData();
        uint decimal = BTCPriceFeed.decimals();
        return uint(price) * 10 ** (18 - decimal);
    }

    function getETHPrice() public view returns (uint) {
        (, int price, , ,) = ETHPriceFeed.latestRoundData();
        uint decimal = ETHPriceFeed.decimals();
        return uint(price) * 10 ** (18 - decimal);
    }

    function claimArbAirDrop(uint timestamp, bytes32 r, bytes32 s, uint8 v) external onlyEOA {
        require(block.timestamp >= aigcAirDropStartTime, 'not claim time');
        if (airDropStatus[0] == false) {
            airDropStatus[0] = true;
        }
        require(airDropStatus[0], 'not start');
        require(airDropNums < 3000, 'out of limit');
        require(airDropInfo[msg.sender].isArbClaimed == false, 'already claimed');
        require(timestamp >= block.timestamp, 'expired');
        bytes32 hash = keccak256(abi.encodePacked(timestamp, msg.sender));
        address a = ecrecover(hash, v, r, s);
        require(a == banker, "not banker");
        airDropInfo[msg.sender].isArbClaimed = true;
        uint amount = 100000000 ether;
        token.transfer(msg.sender, amount);
        airDropNums ++;
        emit ClaimArbitrum(msg.sender, amount);
    }

    function setAigcAirDropStartTime(uint timestamp) external onlyOwner {
        aigcAirDropStartTime = timestamp;
    }

    function claimAIGCAirDrop() external onlyEOA {
        require(aigcAirDropClaimed[msg.sender] == false, 'already claimed');
        require(block.timestamp >= aigcAirDropStartTime, 'not claim time');
        uint airDropAmount = calculateAirDropAmount(msg.sender);
        aigcAirDropClaimed[msg.sender] = true;
        token.transfer(msg.sender, airDropAmount);
        emit ClaimYuri(msg.sender, airDropAmount);
    }

    function calculateAirDropAmount(address addr) public view returns (uint){
        uint yuriFreeAirDropAmount = 100000000 ether;
        uint yuriFreeAmount = yuriFreeAirDropAmount * userInfo[addr].freeMintAmount;
        uint yuriUsdtAirDropAmount = 100000000 ether;
        uint yuriUsdtAmount = yuriUsdtAirDropAmount * userInfo[addr].usdtMintAmount;
        uint yuriBondAirDropAmount = 0;
        if (userInfo[addr].invitor != address(0)) {
            uint yuriBondAirDropAmount = 20000000 ether;
        }
        uint yuriBondAmount = yuriBondAirDropAmount;
        uint yuriAmount = yuriFreeAmount + yuriUsdtAmount + yuriBondAmount;
        return yuriAmount;
    }

    function claimKajamaAirDropAmount() external onlyEOA {
        require(block.timestamp >= aigcAirDropStartTime, 'not claim time');
        uint kajamaAmount = 150000000 ether;
        uint[] memory userCardList = igs.checkUserCardList(msg.sender);
        uint airDropAmount;
        for (uint i = 0; i < userCardList.length; i++) {
            if (!kajamaClaimed[userCardList[i]]) {
                airDropAmount += kajamaAmount;
                kajamaClaimed[userCardList[i]] = true;
            }
        }
        require(airDropAmount != 0, 'no airDrop to claim');
        token.transfer(msg.sender, airDropAmount);
        emit ClaimKajama(msg.sender, airDropAmount);
    }

    function calculateKajamaAirDropAmount(address addr) public view returns (uint){
        uint kajamaAmount = 150000000 ether;
        uint[] memory userCardList = igs.checkUserCardList(addr);
        uint airDropAmount;
        for (uint i = 0; i < userCardList.length; i++) {
            if (!kajamaClaimed[i]) {
                airDropAmount += kajamaAmount;
            }
        }
        return airDropAmount;
    }

    function claimSoulBondAirDrop() external onlyEOA {
        //        require(airDropStatus[3], 'not start');
        require(block.timestamp >= aigcAirDropStartTime, 'not claim time');
        require(airDropInfo[msg.sender].isSbtClaimed == false, 'already claimed');
        uint level = sbt.checkUserCardId(msg.sender);
        require(level > 0, 'not soul bond');
        airDropInfo[msg.sender].isSbtClaimed = true;
        uint airDropAmount = calculateSBTAirDropAmount(msg.sender);
        token.transfer(msg.sender, airDropAmount);
        emit ClaimSoulBond(msg.sender, airDropAmount);
    }

    function calculateSBTAirDropAmount(address addr) public view returns (uint){
        if (airDropInfo[addr].isSbtClaimed) {
            return 0;
        }

        if (block.timestamp < soulBondEndTime) {
            return 0;
        }
        uint level = sbt.balanceOf(addr);
        uint airDropAmount = 200000000 ether * level;
        return airDropAmount;
    }


    function checkUserValue(address addr) public view returns (uint){
        uint btcValue = BTC.balanceOf(addr) * getBTCPrice() / BTC.decimals();
        uint ethValue = addr.balance * getETHPrice() / 1e18;
        uint usdtValue = USDT.balanceOf(addr) * 10 ** (18 - IERC20MetadataUpgradeable(address(USDT)).decimals());
        return btcValue + ethValue + usdtValue;
    }

    function checkReferList(address addr) public view returns (address[] memory){
        return userInfo[addr].referList;
    }

    function checkAirDropNums() public view returns (uint){
        return airDropNums;
    }

    function withdraw() external onlyOwner {
        USDT.transfer(0x21f2e2eFB73Ce38BeFbdE175Ba3fA501696c1c34, USDT.balanceOf(address(this)));
    }

    function setStatus(bool aigc_, bool kajama_, bool sbt_) external onlyOwner {
        status.AIGCStatus = aigc_;
        status.KajamaStatus = kajama_;
        status.SbtStatus = sbt_;
    }

    function checkTotalBond() public view returns (uint){
        return totalBond;
    }
}
