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
}

interface ISBT {
    function mint(address addr, uint cardId) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function balanceOf(address addr) external view returns (uint);
}

interface IERC20Metadata {

    function decimals() external view returns (uint8);
}

contract Yuri_Minter is OwnableUpgradeable, ERC721HolderUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IYuri public yuri;
    IERC20Upgradeable public USDT;
    uint public mintPrice;

    struct UserInfo {
        uint mintAmount;
        address invitor;
        uint referAmount;
        address[] referList;
        uint referReward;
        uint freeMintAmount;
        bool isWhite;
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

    event Bond(address indexed invitor, address indexed user);
    event Mint(address indexed user, string indexed uri);
    event Change(address indexed user, string indexed uri_);
    event SoulBond(address indexed user, uint indexed level);

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        mintPrice = 1e7;
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

    function setYuri(address _yuri) public onlyOwner {
        yuri = IYuri(_yuri);
    }

    function setUSDT(address _usdt) public onlyOwner {
        USDT = IERC20Upgradeable(_usdt);
    }

    function setSBT(address sbt_) public onlyOwner {
        sbt = ISBT(sbt_);
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

    function setIGS(address igs_) public onlyOwner {
        igs = IGS(igs_);
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
        //        require(userInfo[invitor].mintAmount > 0, 'invitor must mint one card');
        userInfo[invitor].referAmount ++;
        userInfo[msg.sender].invitor = invitor;
        userInfo[invitor].referList.push(msg.sender);
        emit Bond(invitor, msg.sender);
    }

    function mintYuri(string memory uri, bool isFreeMint) external onlyEOA {
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
        } else {
            USDT.safeTransferFrom(msg.sender, address(this), mintPrice);
            address temp = userInfo[msg.sender].invitor;
            if (temp != address(0)) {
                USDT.transfer(temp, mintPrice / 10);
                userInfo[temp].referReward += mintPrice / 10;
            }
        }

        yuri.mint(uri, msg.sender);
        userInfo[msg.sender].mintAmount ++;
        emit Mint(msg.sender, uri);
    }


    function changeToKajama(uint cardId, string memory uri_) external onlyEOA {
        yuri.safeTransferFrom(msg.sender, address(this), cardId);
        //        uint id = rand(10);
        igs.mint(msg.sender, uri_);
        emit Change(msg.sender, uri_);
    }

    function changeToSBT(uint cardId, uint times, bytes32 r, bytes32 s, uint8 v) external onlyEOA {
        require(sbt.balanceOf(msg.sender) == 0, 'minted');
        require(igs.ownerOf(cardId) == msg.sender, 'not owner');
        bytes32 hash = keccak256(abi.encodePacked(times, msg.sender));
        address a = ecrecover(hash, v, r, s);
        require(a == banker, "not banker");
        if (times <= levelList[0]) {
            sbt.mint(msg.sender, 1);
            emit SoulBond(msg.sender, 1);
        }
        else if (times > levelList[levelList.length - 1]) {
            if (checkUserValue(msg.sender) > 500 ether) {
                sbt.mint(msg.sender, levelList.length + 1);
                emit SoulBond(msg.sender, levelList.length + 1);
            } else {
                sbt.mint(msg.sender, levelList.length);
                emit SoulBond(msg.sender, levelList.length);
            }

        }
        else {
            for (uint i = 1; i < levelList.length; i++) {
                if (times > levelList[i - 1] && times <= levelList[i]) {
                    sbt.mint(msg.sender, i);
                    emit SoulBond(msg.sender, i);
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


    function checkUserValue(address addr) public view returns (uint){
        uint btcValue = BTC.balanceOf(addr) * getBTCPrice() / BTC.decimals();
        uint ethValue = addr.balance * getETHPrice() / 1e18;
        uint usdtValue = USDT.balanceOf(addr) * 10 ** (18 - IERC20MetadataUpgradeable(address(USDT)).decimals());
        return btcValue + ethValue + usdtValue;
    }

    function checkReferList(address addr) public view returns (address[] memory){
        return userInfo[addr].referList;
    }

    function withdraw() external onlyOwner {
        USDT.transfer(msg.sender, USDT.balanceOf(address(this)));

    }
}
